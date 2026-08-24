#!/usr/bin/env python3
"""OCR engine for appliance screenshot acceptance checks.

Wraps the `tesseract` CLI (never `pytesseract` — kept dependency-light: the
only third-party package this whole library needs is Pillow, for image
preprocessing; see `requirements.txt`) with a small multi-pass pipeline
tuned empirically against REAL screendumps already sitting in
`appliance/.vm/` from other 2026-08 wave sessions (not synthetic test
images) — `s2-evidence/a4-firstboot-oobe-on-comp-2026-08-22.png` (a real
OOBE language-picker screen) and `d9lock/10-home.png` (a real post-OOBE
DuDuClaw desktop) drove the parameter choices below. See
`appliance/tests/README.md`'s "OCR tuning notes" section for the exact
before/after transcripts.

## Why `--psm 3` is the primary pass, not `--psm 11`

The work order's starting point was `--psm 11` (sparse text, no layout
assumed). Empirically, on full-screen 1280x800 appliance captures, `--psm 3`
(fully automatic page segmentation — tesseract's own default) produced
cleaner, more complete text than `--psm 11` on both real screenshots above —
`--psm 11` tends to over-fragment lines that `--psm 3` reads correctly as
one block. `--psm 11` is kept as the SECOND pass (better at picking up
isolated short strings — badges, single buttons — that a full-page layout
pass sometimes merges into a neighbouring block or drops), not the first.

## Why there is an invert pass at all

A light-colored button with white/light text on a saturated fill (found in
`e1a-01-policy.png`'s "繼續" button) OCRs to nothing under normal
grayscale — tesseract's binarization assumes dark-text-on-light by default.
Grayscale + `ImageOps.invert` + a hard threshold recovers it completely
(verified: 8x upscale + invert + threshold + `--psm 7/8` on a tight crop of
that exact button reads back "繼續" with the CJK glyphs intact). The
multi-pass pipeline therefore always tries a normal pass first (cheap, and
correct for the large majority of UI text, which is dark-on-light per this
project's Calm Glass warm-stone light theme — see the root `CLAUDE.md`'s
Aesthetic Direction section) and only pays for an inverted pass when the
normal passes did not find the target text.
"""
from __future__ import annotations

import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator

try:
    from PIL import Image, ImageOps
except ImportError as e:  # pragma: no cover - guidance, not logic
    raise ImportError(
        "Pillow is required. Run this script with the project venv:\n"
        "  appliance/tests/lib/.venv/bin/python3 ...\n"
        "(set up once via: python3 -m venv appliance/tests/lib/.venv && "
        "appliance/tests/lib/.venv/bin/pip install -r appliance/tests/lib/requirements.txt)"
    ) from e

DEFAULT_LANG = "chi_tra+eng"

# Each entry: (label, invert, scale, psm, threshold, trim_inward)
# Applied in order; `iter_ocr_passes` is a generator so callers can stop at
# the first pass that finds their target text without paying for the rest.
_FULLSCREEN_PASS_MATRIX: tuple[tuple[str, bool, float, int, bool, bool], ...] = (
    ("gray-2x-psm3", False, 2.0, 3, True, False),
    ("gray-2x-psm11", False, 2.0, 11, True, False),
    ("inv-2x-psm11", True, 2.0, 11, True, False),
)

# Used only when the caller passes a `region=(x, y, w, h)` crop — small
# regions (a single button/badge/panel) need much higher upscale and a
# tighter page-segmentation mode than a full 1280x800 screen does.
#
# Honest limitation (found tuning against a real light-on-color-fill button,
# `e1a-01-policy.png`'s "繼續" CTA): region OCR is noticeably more sensitive
# to how tightly the region is cropped than full-screen OCR is. A
# pixel-tight crop around just the glyphs reads back cleanly on the first
# pass; a loose region padded with background (the shape a caller is more
# likely to hand in, since they usually know a widget's approximate bounds,
# not its exact glyph bounds) sometimes still fails all of the passes
# below, or returns a stray extra character. `_INWARD_TRIM_FRAC` and the
# extra no-manual-threshold pass both exist specifically to close some of
# that gap; neither eliminates it. Callers of `layer_on_screen` should pass
# as tight a region as practical and always inspect the fail-artifact's OCR
# dump on a miss — see `appliance/tests/README.md`'s OCR tuning notes.
_REGION_PASS_MATRIX: tuple[tuple[str, bool, float, int, bool, bool], ...] = (
    ("region-gray-4x-psm7-trim", False, 4.0, 7, True, True),
    ("region-inv-8x-psm7", True, 8.0, 7, True, False),
    ("region-inv-8x-psm8", True, 8.0, 8, True, False),
    ("region-invnothresh-6x-psm8", True, 6.0, 8, False, False),
)

# Shrink a caller-supplied `region` inward by this fraction of its own
# width/height before the FIRST region pass — cheap noise reduction for the
# common case where the caller's region includes some background margin
# around the actual widget. Only applied to one pass (not the whole
# matrix): trimming too aggressively risks cutting into the real glyphs on
# a region that was already tight, so later passes fall back to the
# untrimmed region.
_INWARD_TRIM_FRAC = 0.12


@dataclass(frozen=True)
class Word:
    """One OCR'd word, with its bounding box already converted back to the
    ORIGINAL screenshot's pixel coordinates (callers never see the internal
    upscale/crop math)."""

    text: str
    x: int
    y: int
    w: int
    h: int
    conf: float
    # (block_num, par_num, line_num) straight from tesseract's TSV — used by
    # `find_word_run_bbox` to refuse to concatenate words that only share a
    # PAGE, not a LINE (see that function's own doc for the false-positive
    # this prevents: an earlier bug let the run-matcher glue words across
    # unrelated blocks into a spurious multi-hundred-pixel bounding box).
    line_key: tuple[int, int, int] = (0, 0, 0)

    @property
    def bbox(self) -> tuple[int, int, int, int]:
        return (self.x, self.y, self.x + self.w, self.y + self.h)


@dataclass
class OcrPass:
    label: str
    full_text: str
    lines: list[str]
    words: list[Word] = field(default_factory=list)


def normalize_text(s: str) -> str:
    """NFKC (full-width/half-width + compatibility form folding) + casefold
    + collapsed whitespace. The baseline normalization both the haystack
    (OCR output) and the needle (caller's expected text) go through before
    comparison."""
    s = unicodedata.normalize("NFKC", s)
    s = s.casefold()
    return " ".join(s.split())


def normalize_nospace(s: str) -> str:
    """`normalize_text` with ALL whitespace removed. Tesseract's CJK word
    segmentation is inconsistent about inserting spaces between characters
    that a human would read as one run (see this module's TSV examples in
    the README) — comparing the whitespace-free form is what makes
    `screen_contains("已選擇")` robust to the OCR engine returning
    "已 選擇" or "已選 擇" for the exact same glyphs."""
    return "".join(normalize_text(s).split())


def text_found(haystack_full_text: str, needle: str) -> bool:
    """True iff `needle` (after normalization) appears in `haystack_full_text`
    (after the same normalization) — tried both space-preserving and
    whitespace-free, since either form of false negative has been observed
    empirically (see module doc)."""
    n_norm = normalize_text(needle)
    h_norm = normalize_text(haystack_full_text)
    if n_norm and n_norm in h_norm:
        return True
    n_ns = normalize_nospace(needle)
    h_ns = normalize_nospace(haystack_full_text)
    return bool(n_ns) and n_ns in h_ns


def _trim_inward(region: tuple[int, int, int, int], frac: float) -> tuple[int, int, int, int]:
    x, y, w, h = region
    dx, dy = round(w * frac), round(h * frac)
    nw, nh = max(1, w - 2 * dx), max(1, h - 2 * dy)
    return (x + dx, y + dy, nw, nh)


def _preprocess(
    src_path: str,
    out_path: str,
    *,
    region: tuple[int, int, int, int] | None,
    invert: bool,
    scale: float,
    threshold: bool = True,
    trim_inward: bool = False,
) -> None:
    im = Image.open(src_path).convert("RGB")
    if region is not None:
        if trim_inward:
            region = _trim_inward(region, _INWARD_TRIM_FRAC)
        x, y, w, h = region
        im = im.crop((x, y, x + w, y + h))
    gray = ImageOps.grayscale(im)
    if invert:
        gray = ImageOps.invert(gray)
        if threshold:
            # Hard threshold after invert: recovers clean black-glyphs-on-
            # white from what was originally light-glyphs-on-saturated-fill.
            # A no-op for already-high-contrast images (everything already
            # near 0/255). Skippable (see `threshold=False` passes in
            # `_REGION_PASS_MATRIX`) because on some real crops tesseract's
            # own Otsu binarization does better with the original
            # anti-aliased edges than with ours — found empirically, kept
            # as an alternate pass rather than replacing the default.
            gray = gray.point(lambda p: 255 if p > 110 else 0)
    if scale != 1.0:
        gray = gray.resize((max(1, int(gray.width * scale)), max(1, int(gray.height * scale))), Image.LANCZOS)
    gray.save(out_path)


def _run_tesseract_tsv(image_path: str, lang: str, psm: int) -> list[tuple]:
    """Returns raw TSV data rows (level==5, i.e. word-level) as tuples
    `(block_num, par_num, line_num, left, top, width, height, conf, text)`.
    Shells out to the `tesseract` CLI in TSV mode rather than using
    `pytesseract` — one less dependency, and the TSV format is simple
    enough that parsing it directly is a handful of lines (see
    `--list-langs`/`-c tessedit_create_tsv=1` semantics: `tesseract <img> -
    <config> tsv` prints TSV to stdout). Column order (12 columns):
    level, page_num, block_num, par_num, line_num, word_num, left, top,
    width, height, conf, text."""
    proc = subprocess.run(
        ["tesseract", image_path, "-", "--psm", str(psm), "-l", lang, "tsv"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"tesseract failed (exit {proc.returncode}): {proc.stderr.strip()}")
    rows: list[tuple] = []
    for line in proc.stdout.splitlines():
        if not line or line.startswith("level\t"):
            continue
        cols = line.split("\t")
        if len(cols) != 12:
            continue
        level = cols[0]
        if level != "5":  # 5 = word level (1=page,2=block,3=par,4=line,5=word)
            continue
        try:
            block_num, par_num, line_num = (int(cols[2]), int(cols[3]), int(cols[4]))
            left, top, width, height = (int(cols[6]), int(cols[7]), int(cols[8]), int(cols[9]))
            conf = float(cols[10])
        except ValueError:
            continue
        text = cols[11]
        if not text.strip():
            continue
        rows.append((block_num, par_num, line_num, left, top, width, height, conf, text))
    return rows


def _pass_to_words(rows: list[tuple], *, region: tuple[int, int, int, int] | None, scale: float) -> list[Word]:
    ox, oy = (region[0], region[1]) if region is not None else (0, 0)
    words = []
    for block_num, par_num, line_num, left, top, width, height, conf, text in rows:
        words.append(
            Word(
                text=text,
                x=ox + round(left / scale),
                y=oy + round(top / scale),
                w=round(width / scale),
                h=round(height / scale),
                conf=conf,
                line_key=(block_num, par_num, line_num),
            )
        )
    return words


def iter_ocr_passes(
    screenshot_path: str,
    *,
    work_dir: str | Path,
    lang: str = DEFAULT_LANG,
    region: tuple[int, int, int, int] | None = None,
) -> Iterator[OcrPass]:
    """Yield one `OcrPass` per preprocessing/psm combination, cheapest and
    most-likely-correct first (module doc). A generator so a caller
    (`screen_contains`) can `break` the moment one pass satisfies its check
    instead of always paying for every pass.

    `work_dir` is required and should be a real directory, NOT `/tmp`
    directly — macOS's `/tmp` is a symlink to `/private/tmp`, and reading a
    freshly-written file back through that symlink has been observed to
    fail inside this project's sandboxed tooling (leptonica reports a
    garbled "failed to open locally with tail ..." error, and the CLI's
    stderr can even contain raw image bytes that break UTF-8 decoding).
    Pass an explicit artifacts/scratch directory instead."""
    matrix = _REGION_PASS_MATRIX if region is not None else _FULLSCREEN_PASS_MATRIX
    work_dir = Path(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)
    stem = Path(screenshot_path).stem
    for label, invert, scale, psm, threshold, trim_inward in matrix:
        pre_path = str(work_dir / f"{stem}-{label}.png")
        used_region = _trim_inward(region, _INWARD_TRIM_FRAC) if (region is not None and trim_inward) else region
        _preprocess(
            screenshot_path, pre_path, region=region, invert=invert, scale=scale, threshold=threshold, trim_inward=trim_inward
        )
        rows = _run_tesseract_tsv(pre_path, lang, psm)
        words = _pass_to_words(rows, region=used_region, scale=scale)
        full_text = "\n".join(w.text for w in words)
        # Also build a line-grouped text (useful for eyeballing evidence
        # dumps) — recompute directly from TSV block/par/line, but since we
        # already discarded that grouping in `_pass_to_words` for
        # simplicity, approximate lines by preserving word order (good
        # enough for evidence text; geometry lookups use `words` directly).
        lines = [w.text for w in words]
        yield OcrPass(label=label, full_text=full_text, lines=lines, words=words)


def ocr_evidence_text(passes: list[OcrPass]) -> str:
    """Human-readable dump of every attempted pass's recognized text, for a
    `fail()` artifact — see `test_run.py`."""
    chunks = []
    for p in passes:
        chunks.append(f"--- pass: {p.label} ---\n{p.full_text}")
    return "\n\n".join(chunks) if chunks else "(no OCR passes ran)"


def find_word_run_bbox(words: list[Word], needle: str) -> tuple[int, int, int, int] | None:
    """Find the shortest contiguous run of `words` — restricted to words
    sharing the SAME `line_key` (block_num, par_num, line_num), in
    tesseract's own within-line order — whose concatenated, whitespace-free
    normalized text contains `needle`, and return the union bounding box of
    that run. Returns None if no run matches.

    This is the geometry primitive `layer_on_screen` builds on: CJK words
    are frequently split one-character-per-TSV-row, so the caller's needle
    almost never equals a single `Word.text` — it has to be reassembled
    from a run. Two false-positive classes were found and fixed empirically
    against a real OOBE screenshot (kept here as the record of why both
    guards exist, not just the first one that looks sufficient):

    1. Matching across ANY words in flat document order let a run glue
       together characters from an unrelated paragraph and a caption into a
       several-hundred-pixel-wide bounding box that happened to contain the
       needle as a substring purely by coincidence of concatenation. Fixed
       by restricting a run to one `line_key` (block_num, par_num,
       line_num) — a run can never cross into text a human would read as a
       different line/label.
    2. Even within one line, returning the FIRST (start, end) pair found
       (scanning `start` from the line's beginning) picked a needle that
       only matched as a SUFFIX of a longer concatenation — e.g. line text
       "繁體中文已選擇" for needle "已選擇" returned the bbox of the whole
       "繁體中文已選擇" run instead of just the "已選擇" tag at its tail.
       Fixed by scoring every valid (start, end) pair by how many words it
       spans and keeping the SHORTEST span across the whole image — the
       tightest match is the one whose words are actually the label, not
       an accidental superset of it."""
    n_ns = normalize_nospace(needle)
    if not n_ns:
        return None
    best: tuple[int, tuple[int, int, int, int]] | None = None  # (span_len, bbox)
    n = len(words)
    for start in range(n):
        acc = ""
        x0 = y0 = None
        x1 = y1 = None
        line_key = words[start].line_key
        for end in range(start, n):
            w = words[end]
            if w.line_key != line_key:
                break
            acc += normalize_nospace(w.text)
            bx0, by0, bx1, by1 = w.bbox
            x0 = bx0 if x0 is None else min(x0, bx0)
            y0 = by0 if y0 is None else min(y0, by0)
            x1 = bx1 if x1 is None else max(x1, bx1)
            y1 = by1 if y1 is None else max(y1, by1)
            if n_ns in acc:
                span_len = end - start
                bbox = (x0, y0, x1 - x0, y1 - y0)
                if best is None or span_len < best[0]:
                    best = (span_len, bbox)
                break  # longer `end` for this `start` only widens the box
    return best[1] if best is not None else None


def _self_check() -> None:
    """`python3 ocr.py --self-check <png>` — quick manual smoke test against
    a real screenshot, prints every pass's recognized text. Not a unit test
    (needs `tesseract` + a real image); `test_pure.py` covers the
    dependency-free logic (normalization, run-matching) with `unittest`."""
    if len(sys.argv) < 3:
        print("usage: ocr.py --self-check <screenshot.png> [needle] [work_dir]", file=sys.stderr)
        sys.exit(2)
    path = sys.argv[2]
    needle = sys.argv[3] if len(sys.argv) > 3 else None
    work_dir = sys.argv[4] if len(sys.argv) > 4 else str(Path(path).resolve().parent / "_ocr_self_check")
    passes = []
    for p in iter_ocr_passes(path, work_dir=work_dir):
        print(f"=== {p.label} ===")
        print(p.full_text)
        passes.append(p)
        if needle and text_found(p.full_text, needle):
            print(f"\n[MATCH] {needle!r} found in pass {p.label}")
            bbox = find_word_run_bbox(p.words, needle)
            print("bbox:", bbox)
            return
    if needle:
        print(f"\n[NO MATCH] {needle!r} not found in any pass")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-check":
        _self_check()
    else:
        print(__doc__)
