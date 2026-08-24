#!/usr/bin/env python3
"""Screen-content assertions for appliance VM acceptance tests — the
`screen_contains` / `layer_on_screen` pair from the Q3-OCR work order.

Both take a live `QmpClient` (see `qmp_client.py`), screendump the current
framebuffer, run it through `ocr.py`'s multi-pass OCR pipeline, and report a
structured result carrying enough evidence (screenshot path, every pass's
recognized text, matched word geometry) to file a `fail()` artifact — see
`test_run.py`.

## `layer_on_screen` and the comp query-surface gap (investigated, not
## implemented — out of this work package's directory: appliance/tests/)

The work order asked this helper to cross-check against comp's own
debug/shell_control query surface, not just pixel OCR. Investigated both
sockets this compositor exposes:

- `codrive`'s `window_geometry` op (`crates/duduclaw-comp/src/codrive/
  window_geometry.rs`) — READ-ONLY, returns one xdg-toplevel's global
  origin/size by pid/app_id. Real geometry, but only for ordinary windows.
- `shell_control`'s `list_windows` op (`crates/duduclaw-comp/src/
  shell_control/protocol.rs`, `ShellWindowInfo`) — app_id/title/focused/
  minimized only. NO position or size fields at all.

Neither socket exposes geometry for a real `zwlr_layer_shell_v1` surface
(background/bottom/top/overlay layers — panels, docks, OSDs, the future ⌘K
palette). The data exists internally
(`crates/duduclaw-comp/src/layer_shell/mod.rs`'s `layer_map_for_output(...)
.layer_geometry(...)`, used today only for pointer hit-testing) but is
`pub(crate)`, never wired to either socket. Also worth knowing: per that
same module's own doc, `duduclaw-shell` has not migrated its dock/menu bar
onto real layer-shell surfaces as of WM-3 (2026-08-23) — they are still one
ordinary `xdg_toplevel` — so even a hypothetical `list_layers` op would
answer nothing for today's shell chrome; `window_geometry`/`list_windows`
are what actually apply to it right now.

Given this work package's directory boundary is `appliance/tests/` only
(comp/shell/sysd/gateway/cli are other 2026-08 wave-5 sessions' territory
this round), no comp change is made here. Minimal proposed addition for
whoever next touches `duduclaw-comp/src/shell_control/`:

    ShellControlRequest::ListLayers  // {"op":"list_layers"}, read-only
    -> Vec<ShellLayerInfo { namespace, layer, x, y, width, height, exclusive_zone }>

implemented by iterating `LAYERS_FRONT_TO_BACK` and reading
`layer_map_for_output(&output).layers()` + `.layer_geometry(surface)` for
each — the exact walk `layer_shell::DuduclawComp::layer_under_pointer`
already does internally, just answered over the socket instead of consumed
in-process. Same shape precedent as `codrive_window_geometry`'s reply enum.

Until that lands, `layer_on_screen` here verifies geometry the one way that
works UNCONDITIONALLY today, for toplevels and (if/when they exist)
layer-shell surfaces alike: it reads the pixels that actually hit the
screen, via OCR word bounding boxes. Arguably this is not just a
workaround — it validates what a human or an AI-vision consumer would
actually perceive, rather than trusting compositor-internal state that
could in principle diverge from what got painted. A `query_window_geometry`
cross-check helper is provided below for the toplevel case, since that
socket already exists and needed no comp change to reach.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path

from ocr import DEFAULT_LANG, OcrPass, find_word_run_bbox, iter_ocr_passes, ocr_evidence_text, text_found
from qmp_client import QmpClient
from serial_console import DEFAULT_ROOT_PASSWORD, SerialConsole, ensure_shell


@dataclass
class ScreenCheckResult:
    found: bool
    needle: str
    screenshot_path: str
    matched_bbox: tuple[int, int, int, int] | None  # (x, y, w, h) in ORIGINAL screen coords
    matched_pass_label: str | None
    evidence_text: str  # every attempted pass's OCR output, for a fail() artifact
    passes_tried: int


def _screendump(qmp: QmpClient, artifacts_dir: str | Path, tag: str) -> str:
    artifacts_dir = Path(artifacts_dir)
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    path = str(artifacts_dir / f"{tag}-{int(time.time() * 1000)}.png")
    qmp.screendump(path)
    return path


def screen_contains(
    text: str,
    qmp: QmpClient,
    artifacts_dir: str | Path,
    *,
    region: tuple[int, int, int, int] | None = None,
    lang: str = DEFAULT_LANG,
    screenshot_path: str | None = None,
) -> ScreenCheckResult:
    """Does `text` appear anywhere on the current screen (or, if `region` is
    given, anywhere within that pixel rectangle)?

    Case-insensitive and full-width/half-width–insensitive (`ocr.
    normalize_text`'s NFKC + casefold), and additionally tolerant of
    tesseract inserting/omitting whitespace between CJK glyphs
    (`ocr.normalize_nospace`) — see `ocr.py`'s module doc for why both
    normalizations are needed. Tries multiple OCR passes (plain, sparse-text,
    color-inverted) and stops at the first one that finds `text`; if none do,
    every attempted pass's recognized text is returned in `evidence_text` so
    a caller can write it to a `fail()` artifact for human review.
    """
    shot = screenshot_path or _screendump(qmp, artifacts_dir, "screen")
    passes: list[OcrPass] = []
    work_dir = Path(artifacts_dir) / "_ocr_work"
    for p in iter_ocr_passes(shot, work_dir=work_dir, lang=lang, region=region):
        passes.append(p)
        if text_found(p.full_text, text):
            bbox = find_word_run_bbox(p.words, text)
            return ScreenCheckResult(
                found=True,
                needle=text,
                screenshot_path=shot,
                matched_bbox=bbox,
                matched_pass_label=p.label,
                evidence_text=ocr_evidence_text(passes),
                passes_tried=len(passes),
            )
    return ScreenCheckResult(
        found=False,
        needle=text,
        screenshot_path=shot,
        matched_bbox=None,
        matched_pass_label=None,
        evidence_text=ocr_evidence_text(passes),
        passes_tried=len(passes),
    )


def wait_for_screen_contains(
    text: str,
    qmp: QmpClient,
    artifacts_dir: str | Path,
    *,
    timeout: float = 90.0,
    interval: float = 2.0,
    region: tuple[int, int, int, int] | None = None,
    lang: str = DEFAULT_LANG,
) -> ScreenCheckResult:
    """Poll `screen_contains` until it succeeds or `timeout` elapses — the
    boot-wait use case ("has the desktop/OOBE actually painted its first
    real text yet"). Bounded: never loops forever. Returns the LAST result
    (whether it succeeded or the final timed-out attempt) so the caller
    always has evidence either way."""
    deadline = time.time() + timeout
    last: ScreenCheckResult | None = None
    while True:
        last = screen_contains(text, qmp, artifacts_dir, region=region, lang=lang)
        if last.found or time.time() >= deadline:
            return last
        time.sleep(interval)


@dataclass
class LayerOnScreenResult:
    """`ok` is True only when the text was found AND its OCR-derived
    bounding box falls within `expect_region` (expanded by `tolerance_px`
    on every side). `check` distinguishes WHY it failed when it did:
    `"not_found"` (OCR never recognized the text at all — see
    `screen.evidence_text`) vs `"wrong_position"` (recognized, but not where
    expected — the geometry assertion this function exists for)."""

    ok: bool
    check: str  # "ok" | "not_found" | "wrong_position"
    screen: ScreenCheckResult
    expect_region: tuple[int, int, int, int]
    tolerance_px: int


def layer_on_screen(
    text: str,
    expect_region: tuple[int, int, int, int],
    qmp: QmpClient,
    artifacts_dir: str | Path,
    *,
    tolerance_px: int = 8,
    lang: str = DEFAULT_LANG,
) -> LayerOnScreenResult:
    """Assert `text` is on screen AND positioned inside `expect_region`
    (x, y, w, h in screen pixels), expanded by `tolerance_px` on each side
    to absorb OCR bounding-box jitter (glyph ascenders/descenders, anti-
    aliasing at the crop edge) without accepting a genuinely wrong panel.

    Searches the FULL screen for `text` (not pre-cropped to `expect_region`)
    so a widget that rendered in the wrong place is caught as
    `"wrong_position"` rather than silently reported `"not_found"` — that
    distinction is the entire point of this check versus plain
    `screen_contains`. See this module's doc for the honest limitation this
    is standing in for (no compositor-level layer-shell geometry query
    exists yet on either IPC socket)."""
    screen = screen_contains(text, qmp, artifacts_dir, lang=lang)
    if not screen.found or screen.matched_bbox is None:
        return LayerOnScreenResult(
            ok=False, check="not_found", screen=screen, expect_region=expect_region, tolerance_px=tolerance_px
        )
    mx, my, mw, mh = screen.matched_bbox
    ex, ey, ew, eh = expect_region
    lo_x, lo_y = ex - tolerance_px, ey - tolerance_px
    hi_x, hi_y = ex + ew + tolerance_px, ey + eh + tolerance_px
    within = (mx >= lo_x) and (my >= lo_y) and (mx + mw <= hi_x) and (my + mh <= hi_y)
    return LayerOnScreenResult(
        ok=within,
        check="ok" if within else "wrong_position",
        screen=screen,
        expect_region=expect_region,
        tolerance_px=tolerance_px,
    )


def wait_for_layer_on_screen(
    text: str,
    expect_region: tuple[int, int, int, int],
    qmp: QmpClient,
    artifacts_dir: str | Path,
    *,
    timeout: float = 90.0,
    interval: float = 2.0,
    tolerance_px: int = 8,
    lang: str = DEFAULT_LANG,
) -> LayerOnScreenResult:
    """`layer_on_screen`'s `wait_for_screen_contains` twin — poll until the
    text is both found AND correctly positioned, or `timeout` elapses.
    Bounded, returns the last attempt either way.

    Real-world motivation (found live, 2026-08-24, this library's own
    boot-accept flow): a plain `screen_contains("DuDuClaw", ...)` polled
    during boot can match while the framebuffer is still showing the
    kernel/systemd TEXT CONSOLE, not the graphical desktop — because a
    systemd unit's own description string
    (`duduclaw-firstboot-repart.service — DuDuClaw OS first-boot: grow
    /data...`) legitimately contains the substring "DuDuClaw" and gets
    OCR'd off the scrolling boot log. That is a true text match and a
    false assertion in one: the caller wanted "the desktop chrome
    rendered", and got "the string appeared somewhere, including in a log
    line". `wait_for_layer_on_screen` closes that gap by requiring the
    match to also sit inside the real widget's expected screen region — a
    boot-log line scrolling near the top of an 80-column text console does
    not land inside a 1280x800 desktop's actual top-left menu-bar
    coordinates."""
    deadline = time.time() + timeout
    last: LayerOnScreenResult | None = None
    while True:
        last = layer_on_screen(text, expect_region, qmp, artifacts_dir, tolerance_px=tolerance_px, lang=lang)
        if last.ok or time.time() >= deadline:
            return last
        time.sleep(interval)


@dataclass
class WindowGeometryQueryResult:
    """Cross-check result from `query_window_geometry` — the comp
    `codrive` socket's `window_geometry` op, reached over serial (see
    module doc: this covers xdg-toplevel windows only, never a real
    layer-shell surface)."""

    ok: bool
    raw: dict
    error: str | None = field(default=None)


def query_window_geometry(
    console: SerialConsole,
    *,
    pid: int | None = None,
    app_id: str | None = None,
    codrive_socket: str = "/run/user/0/duduclaw-codrive.sock",
    password: str = DEFAULT_ROOT_PASSWORD,
) -> WindowGeometryQueryResult:
    """Best-effort ground-truth cross-check for an xdg-toplevel window's
    geometry, straight from the compositor's own `codrive` socket — a
    stronger signal than OCR when a pid/app_id is known, but it does NOT
    cover real layer-shell surfaces (see module doc). Requires a working
    root shell on `console` (`ensure_shell` is called if not already there).

    Implementation detail: rather than adding a new host<->guest bridge,
    this shells a one-line Python snippet into the guest over the existing
    serial console (same "run a command, capture stdout between markers"
    mechanism `SerialConsole.run` already provides) — python3 already ships
    in the appliance image (`tcp_unix_bridge.py`'s own doc note), so no
    guest-side setup is required beyond a live shell."""
    if not ensure_shell(console, password):
        return WindowGeometryQueryResult(ok=False, raw={}, error="serial_login_failed")
    req = {"op": "window_geometry"}
    if pid is not None:
        req["pid"] = pid
    if app_id is not None:
        req["app_id"] = app_id
    req_json = _py_json_dumps_shell_safe(req)
    snippet = (
        "python3 -c \""
        "import socket,json,sys;"
        f"s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(3);"
        f"s.connect('{codrive_socket}');"
        f"s.sendall((json.dumps({req_json})+chr(10)).encode());"
        "print(s.recv(4096).decode(errors='replace'))\""
    )
    out = console.run(snippet, timeout=10.0)
    return _parse_geometry_reply(out)


def _parse_geometry_reply(out: str) -> WindowGeometryQueryResult:
    """Pure parsing step split out of `query_window_geometry` so it is
    unit-testable without a live serial console (see `test_pure.py`):
    `SerialConsole.run`'s output may include trailing shell noise (a
    `[serial_console: TIMEOUT ...]` marker, stray prompt characters), so
    this takes the LAST line that looks like a JSON object rather than
    assuming the whole string is clean JSON."""
    import json as _json

    try:
        for line in reversed(out.splitlines()):
            line = line.strip()
            if line.startswith("{"):
                return WindowGeometryQueryResult(ok=True, raw=_json.loads(line))
        return WindowGeometryQueryResult(ok=False, raw={}, error=f"no JSON reply in output: {out!r}")
    except _json.JSONDecodeError as e:
        return WindowGeometryQueryResult(ok=False, raw={}, error=f"bad JSON: {e}: {out!r}")


def _py_json_dumps_shell_safe(obj: dict) -> str:
    """Render `obj` as a Python dict literal (not JSON — avoids a second
    layer of quote-escaping through the shell's double-quoted `-c` string)
    for embedding directly into the `python3 -c "..."` snippet above."""
    return repr(obj)
