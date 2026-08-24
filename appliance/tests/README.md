# appliance/tests/

VM-based acceptance tests for the DuDuClaw OS appliance image.

- `ab-update/` — A/B partition update acceptance probes (boot, health-check,
  negative-path injection).
- `wifi-hwsim/` — `mac80211_hwsim`-based Wi-Fi integration tests.
- `lib/` — **shared VM acceptance-testing helper library** (this document's
  subject). Promotes patterns that used to live only as ad-hoc, host-local,
  gitignored scripts under `appliance/.vm/inject/` (QMP screendump, serial
  expect-login) into a committed, reusable library, and adds OCR-based
  screen-content assertions on top.

## `lib/` — VM acceptance helper library

### Setup (one-time)

```bash
python3 -m venv appliance/tests/lib/.venv
appliance/tests/lib/.venv/bin/pip install -r appliance/tests/lib/requirements.txt

# Host OCR engine (not a pip package):
brew install tesseract tesseract-lang   # tesseract-lang installs chi_tra + ~160 other languages
tesseract --list-langs | grep chi_tra   # sanity check
```

Every script in `lib/` that touches images (`ocr.py`, `screen_check.py`,
`q3_ocr_boot_accept.py`) needs Pillow, so run them with the venv's
interpreter: `appliance/tests/lib/.venv/bin/python3 <script>`.

### The four pieces

| Module | Provides | Purpose |
|---|---|---|
| `qmp_client.py` | `QmpClient` | QMP connection: `screendump(path)`, `query_status()`, `system_reset()`. |
| `serial_console.py` | `SerialConsole`, `ensure_shell()` | Expect-style serial login/command runner (root pw `duduclaw` — the project-wide convention, see module doc). |
| `ocr.py` | `iter_ocr_passes`, `text_found`, `find_word_run_bbox` | Multi-pass OCR engine (chi_tra+eng) with NFKC/casefold/whitespace-tolerant matching and per-word geometry. |
| `screen_check.py` | `screen_contains`, `layer_on_screen`, `wait_for_screen_contains`, `query_window_geometry` | The four-piece work order's screen-content + geometry assertions. |
| `test_run.py` | `TestRun` | `success(step)` / `fail(step, reason)` artifact convention + `assert_no_failed_units`. |
| `vm_budget.py` | `ensure_vm_budget`, `wait_for_vm_budget` | Host VM-count guard (the "≤2 concurrent VMs" convention, made scriptable). |
| `inject-root-password.sh` | shell script, not Python | Injects a known root password into an already-cloned test disk (Docker + losetup + `chroot chpasswd`, no binaries required) so `assert_no_failed_units` can actually log in — see below. |

Minimal example:

```python
from qmp_client import QmpClient
from screen_check import screen_contains
from test_run import TestRun

run = TestRun(name="my-check")
with QmpClient("127.0.0.1", 47046) as qmp:
    result = screen_contains("已選擇", qmp, run.run_dir)
    if not result.found:
        run.fail("language-picked", "OOBE language selection not visible", qmp=qmp, ocr_evidence=result.evidence_text)
    run.success("oobe-language", qmp)
```

### `screen_contains(text, qmp, artifacts_dir, region=None)`

Does `text` appear anywhere on the current screen (or within `region =
(x, y, w, h)` if given)? Case-insensitive, full-width/half-width–insensitive
(NFKC), and tolerant of tesseract inserting/dropping spaces between CJK
glyphs. Tries a fixed pass matrix (grayscale, sparse-text, color-inverted —
see `ocr.py`'s module doc for why each exists) and stops at the first pass
that finds the text; returns every attempted pass's OCR text as evidence
when none do.

### `layer_on_screen(text, expect_region, qmp, artifacts_dir, tolerance_px=8)`

Asserts `text` is on screen **and** its OCR-derived bounding box falls
inside `expect_region` (± `tolerance_px`). See `screen_check.py`'s module
doc for the full investigation of comp's existing query surfaces
(`codrive`'s `window_geometry`, `shell_control`'s `list_windows`) and why
neither exposes real layer-shell geometry today — summary below.

This is not a nice-to-have on top of `screen_contains` — a real live boot
(below) showed it catches a genuine class of false positive plain text
matching cannot: `wait_for_layer_on_screen` is the `wait_for_screen_
contains` twin that also enforces the region.

### `TestRun` / `fail()` / `assert_no_failed_units`

```python
run = TestRun(name="boot-accept")             # -> appliance/.vm/test-artifacts/<ts>-boot-accept/
run.success("desktop", qmp)                    # -> success-desktop.png
run.fail("desktop", "reason", qmp=qmp, ocr_evidence=text)  # -> fail-desktop.png + fail-desktop.txt, then raises TestFailure
run.assert_no_failed_units(console, exempt=[r"some-known-unit\.service"])
```

Repeated `success()`/`fail()` calls for the same `step` name are
de-duplicated (`-2`, `-3`, ...) rather than overwritten, so a retried
boot-wait poll keeps every screenshot it took along the way.

### Real end-to-end flow: `q3_ocr_boot_accept.py` — LIVE-VERIFIED 2026-08-24

```bash
appliance/tests/lib/.venv/bin/python3 appliance/tests/lib/q3_ocr_boot_accept.py --max-other-vms=2
```

Clones the shared `appliance/.vm/duduclaw-os-vm.raw` working disk (`cp -c`,
same APFS-clone pattern `boot-cd4.sh` already uses), boots it standalone on
dedicated ports (serial 47045 / QMP 47046 / VNC :6 / dashboard 18798),
waits for either the `DuDuClaw` desktop brand mark (geometry-checked via
`layer_on_screen`) or the OOBE `選擇語言` heading to OCR-recognize, then
attempts the no-failed-systemd-units check, then tears the clone down.
Refuses to start (`vm_budget.ensure_vm_budget`) if too many other
`qemu-system-aarch64` are already running (`--max-other-vms`, default 1
other; the work order's own env note phrases the precondition as "≤2
already running", i.e. `--max-other-vms=2`).

**Actually run against a real VM four times on 2026-08-24** (not just
designed/compiled) — two real bugs found and fixed, one real assumption
corrected, in the process:

1. **`screendump` needs an explicit `format: "png"` argument.** Without it,
   this exact QEMU build (11.1.0, homebrew, libpng linked) silently wrote a
   raw PPM (`P6` magic) to a path ending in `.png`. `ocr.py`'s Pillow
   preprocessing sniffs actual file content, not the extension, so OCR
   itself was never affected — but every `fail()`/`success()` artifact was
   lying about its own format to anything else that trusted the `.png`
   extension. Fixed in `qmp_client.py`'s `screendump()`; see its own doc
   comment.
2. **A bare `screen_contains("DuDuClaw", ...)` can true-positive against
   the boot-time TEXT CONSOLE, not the graphical desktop.** A systemd unit
   description (`duduclaw-firstboot-repart.service — DuDuClaw OS
   first-boot: grow /data...`) legitimately contains the substring
   "DuDuClaw" and got OCR'd straight off the scrolling kernel/systemd log,
   producing a technically-correct-but-semantically-wrong PASS before the
   compositor had even started. Fixed by switching the desktop check to
   `wait_for_layer_on_screen` (new in `screen_check.py`), which additionally
   requires the match to sit inside the real menu-bar's expected screen
   region — a boot-log line does not. This is the concrete, live-found case
   `layer_on_screen` exists to guard against, not a hypothetical one.
3. **The master disk's OOBE-completion state is NOT stable.** Two `cp -c`
   clones of the same `duduclaw-os-vm.raw`, taken minutes apart, landed in
   different states — one at the desktop, one at OOBE — because (as every
   other session's own comments already say) the master file is somebody
   else's long-running working disk and gets rebuilt/reset unpredictably.
   The script now accepts either real state rather than assuming one.

**What passed live**: the boot-text check (desktop OR OOBE, geometry-safe)
PASSED on every one of the four runs once the two bugs above were fixed —
genuine OCR recognition against a screen nobody staged or hand-picked,
including a run that correctly recognized real OOBE text
("選擇語言"/"繁體中文"/"已選擇"/"English"/"日本語", bbox-consistent with
the fixture-tuned parameters) on an independently-booted clone.

**What did NOT run live (as of the original 2026-08-24 run)**: the
`assert_no_failed_units` step. A stock (non-`APPLIANCE_DEBUG`) clone of
`duduclaw-os-vm.raw` ships with **no root password at all** — confirmed live
via PAM's own `res=failed` audit line over serial, matching `commercial/
docs/DESIGN-ab-update-rollback-2026-08.md` §11.6's same-day, independent
finding ("出貨 image 沒有設任何 root 密碼"). The script detects this and
reports a clearly labeled SKIP (exit code `2`, distinct from pass `0` and
fail `1`) rather than a false pass or a misleading fail — `assert_no_failed_
units` ITSELF is fully covered by `test_pure.py`'s `TestAssertNoFailedUnits`
(including the real `●`-column parsing bug found there), just not exercised
against a live `systemctl` on this particular disk. Pass `--root-password`
if testing a disk that had one injected — e.g. via `ab-update/inject-
binaries.sh`'s `AB_ROOT_PASSWORD` (needs Docker + built `duduclaw`/
`duduclaw-sysd` binaries; that script's real job is swapping binaries, the
password is a side effect), or via this library's own
**`inject-root-password.sh`** (M1, 2026-08-24 — closes the gap this
paragraph used to describe as "out of this library's own scope to
duplicate"): the same Docker + losetup + `chroot chpasswd` convention,
extracted into a standalone script that needs no built binaries at all —
password injection only, on an already-cloned test disk, never the master
disk (hard-refuses a target literally named `duduclaw-os-vm.raw`).

```bash
# Stop the clone's VM first (mount races a running QEMU), then:
appliance/tests/lib/inject-root-password.sh appliance/.vm/duduclaw-os-w53.raw duduclaw
# then boot it and pass --root-password duduclaw (or whatever you chose)
```

### Tests

```bash
# Pure logic — no tesseract, no QEMU (23 cases):
appliance/tests/lib/.venv/bin/python3 -m unittest test_pure -v

# screen_contains / wait_for_screen_contains against real screenshots via a
# FakeQmp — needs tesseract, does NOT need a VM (5 cases, ~20s):
appliance/tests/lib/.venv/bin/python3 -m unittest test_screen_check_integration -v
```

`test_pure.py` covers text normalization, substring matching, and — most
importantly — two geometry bugs found and fixed while tuning
`find_word_run_bbox` against real screenshots (see `ocr.py`'s doc comment
on that function for the full story): a run must never cross a line
boundary, and among several valid matches the TIGHTEST one must win, not
the first one found. `test_screen_check_integration.py` replays two real
fixture screenshots (`s2-evidence/a4-firstboot-oobe-on-comp-2026-08-22.png`,
`d9lock/10-home.png`) through a `FakeQmp` that just copies a fixed PNG on
`screendump()`, exercising the full `screen_contains`/`wait_for_
screen_contains` pipeline — including the boot-wait poll-until-found path
and the bounded-timeout path — with real OCR calls but no QEMU process.

## OCR tuning notes (empirical, against real screenshots)

Tuned against two real screendumps already produced by other 2026-08
wave-5 sessions (not synthetic test images):
`appliance/.vm/s2-evidence/a4-firstboot-oobe-on-comp-2026-08-22.png` (a
real OOBE language-picker) and `appliance/.vm/d9lock/10-home.png` (a real
post-OOBE DuDuClaw desktop).

- **`--psm 3` (tesseract's own full-page auto-segmentation), not the work
  order's suggested starting point `--psm 11` (sparse text).** On both real
  1280x800 screenshots, `--psm 3` read complete, correct strings
  ("繁體中文", "已選擇", "English", "客服月報", "已完成", ...) while
  `--psm 11` fragmented lines more. `--psm 3` is the first pass tried;
  `--psm 11` is kept as a fallback (better at isolated short strings a
  full-page layout sometimes drops).
- **2x LANCZOS upscale before OCR, always.** Appliance UI text at native
  1280x800 is legible to a human but small enough that tesseract's
  accuracy visibly improves after upscaling — sips's default resize filter
  produced visible blur/aliasing bad enough to make a button's text
  unreadable even to a human; Pillow's `Image.LANCZOS` does not have that
  problem.
- **Light-text-on-saturated-fill needs grayscale + invert + a hard
  threshold.** Found on `e1a-01-policy.png`'s "繼續" CTA button (white text
  on a blue pill): completely unrecognized under normal grayscale OCR at
  any `--psm`, fully recovered (`繼續`, exact) after
  `ImageOps.invert` + `point(lambda p: 255 if p>110 else 0)` + 8x upscale +
  `--psm 7`/`8`.
- **Region/crop OCR is more sensitive to crop tightness than full-screen
  OCR is.** A pixel-tight crop around a small widget's glyphs reads
  cleanly; a loosely-padded region (more realistic — callers usually know
  a widget's approximate bounds, not its exact glyph bounds) sometimes
  fails every pass in the region matrix. `ocr.py`'s `_REGION_PASS_MATRIX`
  includes an inward-trim pass and a no-manual-threshold pass to close
  part of this gap, but it is not fully closed — pass as tight a `region`
  as practical, and always inspect the `fail()` artifact's OCR dump on a
  region-check miss.
- **Geometry (`find_word_run_bbox`) must be scoped to one OCR line.** CJK
  text is frequently split one character per TSV row, so a caller's needle
  almost never equals one `Word.text` — it has to be reassembled from a
  run of adjacent words. Two false-positive classes were found and fixed
  (see `test_pure.py`'s regression tests): concatenating across an
  unrelated line/block by coincidence, and returning an oversized run when
  a shorter, tighter match also existed on the same line.

## `layer_on_screen` and comp's query-surface gap

The work order asked for `layer_on_screen` to cross-check against comp's
existing debug/`shell_control` query surface, not just pixel OCR.
Investigated (read, not modified — `crates/duduclaw-comp/` is another
2026-08 wave-5 session's territory this round):

- `codrive`'s `window_geometry` op
  (`crates/duduclaw-comp/src/codrive/window_geometry.rs`) — read-only,
  returns one xdg-toplevel window's real global origin/size, matched by
  pid/app_id. Reachable from a test host over the existing serial console
  (`screen_check.query_window_geometry` wraps this — implemented, **not
  yet live-verified against a running VM** as of this report; see the
  hand-off notes for why).
- `shell_control`'s `list_windows` op
  (`crates/duduclaw-comp/src/shell_control/protocol.rs`,
  `ShellWindowInfo`) — app_id/title/focused/minimized only, **no position
  or size fields at all**.
- **No op on either socket answers real `zwlr_layer_shell_v1` surface
  geometry.** The data exists internally
  (`crates/duduclaw-comp/src/layer_shell/mod.rs`'s
  `layer_map_for_output(&output).layer_geometry(surface)`, used today only
  for pointer hit-testing) but is `pub(crate)`, never wired to a socket.
  Also, per that module's own 2026-08-23 doc comment, `duduclaw-shell`
  itself has not migrated its dock/menu bar onto real layer-shell surfaces
  yet — they are still one ordinary `xdg_toplevel` — so even a
  hypothetical new op would answer nothing for today's shell chrome.

**Minimal proposed addition** (not implemented here — out of this round's
directory boundary), for whoever next touches
`duduclaw-comp/src/shell_control/`:

```rust
ShellControlRequest::ListLayers  // {"op":"list_layers"}, read-only, no params
-> Vec<ShellLayerInfo { namespace, layer, x, y, width, height, exclusive_zone }>
```

implemented by iterating `LAYERS_FRONT_TO_BACK` and reading
`layer_map_for_output(&output).layers()` + `.layer_geometry(surface)` —
the exact walk `layer_shell::DuduclawComp::layer_under_pointer` already
does internally, answered over the socket instead of consumed in-process
— same reply-enum shape precedent `codrive_window_geometry` already
established.

Until that lands, `layer_on_screen` verifies geometry the one way that
works unconditionally today, for toplevels and any future layer-shell
surface alike: OCR word bounding boxes on the actual rendered pixels —
arguably a stronger acceptance signal than compositor-internal state
in the first place, since it validates what a human or AI-vision consumer
would actually perceive.
