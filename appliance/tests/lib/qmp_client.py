#!/usr/bin/env python3
"""Minimal QMP client for appliance VM acceptance testing.

Adapted from the ad-hoc, host-local (gitignored, per `appliance/.gitignore`'s
`.vm/` rule) `appliance/.vm/inject/qmp.py` and `screendump.py` scripts that
earlier wave sessions wrote and re-wrote per probe. Those two scripts proved
the pattern (raw newline-delimited JSON over the `-qmp tcp:...` socket,
`screendump`'s `filename` argument is resolved by QEMU on the HOST
filesystem, not inside the guest) but never existed anywhere git tracks, so
every fresh checkout had to reinvent them. This module is that pattern,
promoted to a committed, reusable library — see `screendump()`'s own doc
comment for a real-PNG-vs-PPM format gotcha found live 2026-08-24 that the
scripts this was adapted from did not handle either.

Usage as a library:
    from qmp_client import QmpClient
    with QmpClient("127.0.0.1", 47046) as qmp:
        qmp.screendump("/path/to/out.png")
        status = qmp.query_status()

Usage as a CLI (kept for parity with the old qmp.py, e.g. quick manual
probing from a shell):
    qmp_client.py <host> <port> screendump <out.png>
    qmp_client.py <host> <port> query-status
    qmp_client.py <host> <port> system_reset
"""
from __future__ import annotations

import json
import socket
import sys
import time
from dataclasses import dataclass


class QmpError(RuntimeError):
    """A QMP command returned an `"error"` object instead of `"return"`."""


@dataclass(frozen=True)
class QmpGreeting:
    raw: dict


class QmpClient:
    """One QMP connection: connect, negotiate capabilities, issue commands.

    Deliberately synchronous/blocking (same as the scripts this replaces) —
    acceptance tests issue one command, wait for the reply, move on. No
    event-stream handling; if a future helper needs QMP events it should
    extend this class rather than grow a second parallel client.
    """

    def __init__(self, host: str, port: int, connect_timeout: float = 10.0):
        self.host = host
        self.port = port
        self.connect_timeout = connect_timeout
        self.sock: socket.socket | None = None
        self.greeting: QmpGreeting | None = None

    def __enter__(self) -> "QmpClient":
        self.connect()
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def connect(self) -> None:
        self.sock = socket.create_connection((self.host, self.port), timeout=self.connect_timeout)
        self.greeting = QmpGreeting(self._recv_one(timeout=5.0))
        self._send_raw({"execute": "qmp_capabilities"})
        ack = self._recv_one(timeout=5.0)
        if "error" in ack:
            raise QmpError(f"qmp_capabilities negotiation failed: {ack['error']}")

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            finally:
                self.sock = None

    def _send_raw(self, obj: dict) -> None:
        assert self.sock is not None, "QmpClient used before connect()"
        self.sock.sendall((json.dumps(obj) + "\n").encode())

    def _recv_one(self, timeout: float = 8.0) -> dict:
        """Read exactly one newline-terminated JSON object. QMP is one
        object per line, so this is simpler than the old qmp.py's
        MSG_PEEK-based "keep reading until quiet" heuristic — that
        heuristic existed only because that script read many replies in a
        loop without knowing how many to expect. Here every call site
        knows exactly one object is coming next."""
        assert self.sock is not None, "QmpClient used before connect()"
        self.sock.settimeout(timeout)
        buf = b""
        while b"\n" not in buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                break
            buf += chunk
        line, _, _rest = buf.partition(b"\n")
        if not line.strip():
            raise QmpError("QMP connection closed before a reply arrived")
        return json.loads(line)

    def command(self, execute: str, arguments: dict | None = None, timeout: float = 8.0) -> dict:
        """Issue one QMP command, return its `"return"` payload. Raises
        QmpError if QEMU answered with `"error"` instead."""
        cmd: dict = {"execute": execute}
        if arguments:
            cmd["arguments"] = arguments
        self._send_raw(cmd)
        # QMP may interleave an unrelated event before the command's own
        # reply; skip any object that isn't return/error (mirrors the old
        # qmp.py's loop-until-return-or-error, but for a single command).
        deadline = time.time() + timeout
        while time.time() < deadline:
            obj = self._recv_one(timeout=max(0.1, deadline - time.time()))
            if "return" in obj:
                return obj["return"]
            if "error" in obj:
                raise QmpError(f"{execute} failed: {obj['error']}")
        raise QmpError(f"{execute}: no return/error within {timeout}s")

    def screendump(self, out_path: str, settle: float = 0.3) -> None:
        """Dump the current framebuffer straight to a PNG on THIS host.
        `settle` gives QEMU a moment after issuing the command before the
        caller starts reading the file — matches the old screendump.py's
        `time.sleep(0.5)` (found necessary in practice: the QMP reply can
        race the file actually being flushed to disk on a busy host).

        Explicitly passes `format: "png"` — found live (2026-08-24, this
        library's first real VM boot) that `screendump` does NOT infer the
        format from `out_path`'s extension: with no `format` argument this
        exact QEMU build (11.1.0, homebrew, libpng linked and everything)
        silently wrote a raw PPM (`P6` magic) to a path ending in `.png`.
        `query-qmp-schema` confirms `screendump`'s `format` field is a real
        enum (`ppm` | `png`), default null == ppm. Omitting it doesn't
        break THIS library (`ocr.py`'s Pillow preprocessing sniffs actual
        file content, not the extension, so OCR was unaffected) but it
        does produce artifact files that lie about their own format to any
        other tool/human that trusts the `.png` extension — see
        `test_run.py`'s `fail()`/`success()` artifacts, which is exactly
        where this was first noticed."""
        self.command("screendump", {"filename": out_path, "format": "png"})
        time.sleep(settle)

    def query_status(self) -> dict:
        return self.command("query-status")

    def system_reset(self) -> None:
        self.command("system_reset")

    # ── Input (M1, 2026-08-24) ───────────────────────────────────────────
    # `input-send-event` — added for the M1 VM live-test sweep (D4b's seven
    # settings pages, D9's keyboard nav, D2's dark mode), which all need to
    # actually click/type against a running VM, not just screendump it.
    # Earlier wave sessions did this too (D9-bug5's own evidence log says
    # "QMP 送鍵滑鼠＋截圖") but only from ad-hoc, gitignored `.vm/inject/`
    # scripts (same fate `qmp_client.py`'s own module doc says `qmp.py`/
    # `screendump.py` had) — promoted here into the one committed client
    # instead of writing a fourth throwaway copy.

    def send_key_chord(self, qcodes: list[str], hold_s: float = 0.05) -> None:
        """Presses `qcodes` together (e.g. `["tab"]`, `["shift", "tab"]`,
        `["ret"]`) and releases them in reverse order, via QMP's
        `input-send-event`. These are QEMU's own `QKeyCode` names
        (`qapi/ui.json`) — NOT web `KeyboardEvent` names: `"ret"` not
        `"enter"`, `"esc"` not `"escape"`. Getting this wrong is a silent
        no-op (QEMU just ignores an unrecognized qcode), not an error, so a
        caller whose key never seems to register should check this list
        first."""
        down = [{"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": k}}} for k in qcodes]
        self.command("input-send-event", {"events": down})
        time.sleep(hold_s)
        up = [{"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": k}}} for k in reversed(qcodes)]
        self.command("input-send-event", {"events": up})

    def send_text(self, text: str, char_delay_s: float = 0.04) -> None:
        """Types `text` one character at a time via `send_key_chord`. ASCII
        letters/digits/space only (`QKeyCode` has no generic "type this
        Unicode codepoint" event — CJK input goes through the IME candidate
        window, which is a click/selection flow, not typed text, and is out
        of this helper's scope). Raises `ValueError` up front — not
        mid-sequence — on any character this mapping does not cover, so a
        caller never ends up with a half-typed field on screen."""
        chord_for = _ascii_qcode_chords(text)
        for chord in chord_for:
            self.send_key_chord(chord, hold_s=0.02)
            time.sleep(char_delay_s)

    def send_abs_click(self, x: int, y: int, screen_w: int, screen_h: int, button: str = "left", settle_s: float = 0.15) -> None:
        """Moves the absolute pointer to pixel `(x, y)` (on a `screen_w` x
        `screen_h` framebuffer — i.e. the SAME image a `screendump()` you
        just took would report, e.g. via `PIL.Image.open(path).size`) and
        clicks `button`. Requires the guest to have a `usb-tablet` device
        (absolute positioning; `q3_ocr_boot_accept.py`'s own `boot_qemu`
        already includes one) — a plain `usb-mouse` is relative-only and
        this method would walk the cursor to the wrong place.

        QEMU's `abs` axis range is a fixed 0..32767 regardless of the
        guest's actual resolution (`qapi/ui.json`'s `InputMoveEvent`), so the
        pixel coordinate is rescaled here rather than passed through — a
        caller must supply the screenshot's actual pixel size, not assume
        1280x800."""
        qx = round(x * 32767 / max(1, screen_w))
        qy = round(y * 32767 / max(1, screen_h))
        move = [{"type": "abs", "data": {"axis": "x", "value": qx}}, {"type": "abs", "data": {"axis": "y", "value": qy}}]
        self.command("input-send-event", {"events": move})
        time.sleep(settle_s)
        self.command("input-send-event", {"events": [{"type": "btn", "data": {"down": True, "button": button}}]})
        time.sleep(0.06)
        self.command("input-send-event", {"events": [{"type": "btn", "data": {"down": False, "button": button}}]})
        time.sleep(settle_s)

    def send_abs_click_bbox(self, bbox: tuple[int, int, int, int], screen_w: int, screen_h: int, button: str = "left") -> None:
        """Convenience wrapper: clicks the CENTER of an OCR-matched bounding
        box (`screen_check.ScreenCheckResult.matched_bbox`'s own `(x, y, w,
        h)` shape) — the click-by-recognized-text pattern the M1 settings
        sweep uses instead of hand-measured pixel coordinates, which drift
        the moment a board's layout changes."""
        x, y, w, h = bbox
        self.send_abs_click(x + w // 2, y + h // 2, screen_w, screen_h, button=button)


# QEMU `QKeyCode` names for the ASCII characters this crate's UI actually
# needs to type (Wi-Fi SSIDs/passphrases in `screen_contains`-driven tests,
# static-IP forms, timezone free text, password fields). Deliberately a
# closed table, not a computed mapping: `QKeyCode` has entries with no
# obvious ASCII-arithmetic relationship (`"minus"`, `"equal"`, `"comma"`),
# so guessing one from `chr()`/`ord()` would be wrong for exactly the
# characters most likely to appear in a password.
_ASCII_QCODES: dict[str, list[str]] = {
    **{c: [c] for c in "abcdefghijklmnopqrstuvwxyz"},
    **{c.upper(): ["shift", c] for c in "abcdefghijklmnopqrstuvwxyz"},
    "0": ["0"], "1": ["1"], "2": ["2"], "3": ["3"], "4": ["4"],
    "5": ["5"], "6": ["6"], "7": ["7"], "8": ["8"], "9": ["9"],
    " ": ["spc"], ".": ["dot"], ",": ["comma"], "-": ["minus"], "_": ["shift", "minus"],
    "/": ["slash"], ":": ["shift", "semicolon"], "@": ["shift", "2"], "!": ["shift", "1"],
}  # fmt: skip


def _ascii_qcode_chords(text: str) -> list[list[str]]:
    chords = []
    for ch in text:
        chord = _ASCII_QCODES.get(ch)
        if chord is None:
            raise ValueError(f"send_text: no QKeyCode mapping for character {ch!r} — extend _ASCII_QCODES rather than guess one")
        chords.append(chord)
    return chords


def _main() -> None:
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    host, port, op = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    with QmpClient(host, port) as qmp:
        print("GREETING:", qmp.greeting.raw)
        if op == "screendump":
            out = sys.argv[4]
            qmp.screendump(out)
            print("screendump ->", out)
        elif op == "query-status":
            print(qmp.query_status())
        elif op == "system_reset":
            qmp.system_reset()
            print("reset issued")
        else:
            print(f"unknown op {op}", file=sys.stderr)
            sys.exit(2)


if __name__ == "__main__":
    _main()
