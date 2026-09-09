#!/usr/bin/env python3
"""Build low-poly panel geometry for the DuDuClaw origami cat from the brand SVG.

Input : website/assets/brand/duduclaw-cat.svg
Output: website/assets/data/cat-panels.json

Everything here is offline and dependency-free (Python stdlib only). The runtime
module `assets/js/cat3d/cat3d.mjs` only ever reads the generated JSON.

Pipeline
--------
1. Parse the SVG. We need the clip path `#cut` (the cat silhouette, three
   subpaths of cubic Beziers) and the seven flat `<polygon>` panels drawn
   inside `<g clip-path="url(#cut)">`, plus the three linearGradients.
2. Flatten every cubic adaptively (recursive subdivision on a flatness test),
   then simplify each ring with Douglas-Peucker.
3. Decompose "silhouette", and "silhouette AND panel", into trapezoids with a
   scanline sweep using the SVG nonzero winding rule, then merge vertically
   adjacent trapezoids that are bounded by the same pair of edges, then split
   each trapezoid into two triangles.

   Why a scanline sweep instead of ear clipping: the silhouette contains two
   near-zero-width slits (the white paw stroke is drawn as a filled sliver,
   `... 80.37 123.53 L 80.32 123.63 ...` is 0.11 units wide). Ear clipping on a
   ring with a slit is degenerate, and any simplification tolerance larger than
   the slit width makes the two sides of the slit cross, producing a
   self-intersecting ring. A scanline sweep evaluates the same winding rule the
   SVG renderer uses, so slits and self-intersections are handled by
   construction and the simplification tolerance can be chosen for triangle
   count rather than for topological safety.

   Why clip the panels at all (rather than relying on depth order): the base
   plate covers the whole silhouette opaquely, so putting it in front would
   hide the panels entirely, and putting it behind lets the panels spill past
   the cat's outline. Only a real clip gives both a visible panel and a clean
   silhouette, and doing the clip offline costs nothing at runtime.
4. Emit, per panel: triangles (centred, y-up), a flat colour, the source
   gradient as two points + two colours (so the shader can reproduce the SVG's
   gradient exactly), a resting z offset, a hinge edge and a folded angle.

Run: python3 assets/js/cat3d/tools/build-panels.py [--svg PATH] [--out PATH]
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

SVG_NS = "{http://www.w3.org/2000/svg}"

# ---------------------------------------------------------------------------
# tunables
# ---------------------------------------------------------------------------

FLATTEN_TOL = 0.08      # max deviation (svg units) when flattening a cubic
SIMPLIFY_TOL = 0.40     # Douglas-Peucker tolerance (svg units); ~0.5 px at 300px tall
Z_STEP = 0.6            # resting z gap between stacked panels (svg units)
EPS = 1e-9

# Per-panel authoring table. `hinge` picks which edge of the *source* polygon
# the panel rotates about; -1 means "use the longest edge" (the default rule).
# The overrides are the cases where the artwork's own fold line is not the
# longest edge: the body fold hinges on its diagonal, the tail on the edge that
# meets the body.
PANEL_SPEC = {
    #  id                    hinge  angle  sign  delay
    "arm":              dict(hinge=-1, angle=62, sign=+1, delay=0.00),
    "arm-highlight":    dict(hinge=-1, angle=55, sign=-1, delay=0.10),
    "head":             dict(hinge=-1, angle=48, sign=+1, delay=0.18),
    "ear-highlight":    dict(hinge=-1, angle=58, sign=-1, delay=0.28),
    "paw":              dict(hinge=-1, angle=66, sign=+1, delay=0.36),
    "body-fold":        dict(hinge=0,  angle=44, sign=+1, delay=0.46),
    "tail":             dict(hinge=1,  angle=70, sign=-1, delay=0.56),
}

# Order in the SVG's paint order; also the label shown in the lab page.
PANEL_ORDER = [
    ("arm", "raised arm"),
    ("arm-highlight", "arm highlight"),
    ("head", "head"),
    ("ear-highlight", "ear highlight"),
    ("paw", "folded paw"),
    ("body-fold", "diagonal body fold"),
    ("tail", "tail"),
]


# ---------------------------------------------------------------------------
# svg path parsing + flattening
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(r"([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)")


def tokenize(d: str):
    for m in TOKEN_RE.finditer(d):
        if m.group(1):
            yield ("cmd", m.group(1))
        else:
            yield ("num", float(m.group(2)))


def flatten_cubic(p0, p1, p2, p3, out, depth=0):
    """Adaptive subdivision. Appends points after p0 (p0 assumed already there)."""
    # flatness: max distance of control points from the chord
    ax, ay = p3[0] - p0[0], p3[1] - p0[1]
    chord = math.hypot(ax, ay)
    if chord < EPS:
        d1 = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        d2 = math.hypot(p2[0] - p0[0], p2[1] - p0[1])
        dev = max(d1, d2)
    else:
        d1 = abs((p1[0] - p0[0]) * ay - (p1[1] - p0[1]) * ax) / chord
        d2 = abs((p2[0] - p0[0]) * ay - (p2[1] - p0[1]) * ax) / chord
        dev = max(d1, d2)
    if dev <= FLATTEN_TOL or depth >= 18:
        out.append(p3)
        return
    # de Casteljau split at t = 0.5
    def mid(a, b):
        return ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)

    p01, p12, p23 = mid(p0, p1), mid(p1, p2), mid(p2, p3)
    p012, p123 = mid(p01, p12), mid(p12, p23)
    m = mid(p012, p123)
    flatten_cubic(p0, p01, p012, m, out, depth + 1)
    flatten_cubic(m, p123, p23, p3, out, depth + 1)


def parse_path(d: str):
    """Return a list of rings (each a list of (x, y)). Supports M/L/H/V/C/S/Z."""
    rings = []
    cur = []
    pos = (0.0, 0.0)
    start = (0.0, 0.0)
    prev_c2 = None
    cmd = None
    nums = []
    toks = list(tokenize(d))
    i = 0

    def flush_ring():
        nonlocal cur
        if len(cur) >= 3:
            rings.append(cur)
        cur = []

    while i < len(toks):
        kind, val = toks[i]
        if kind == "cmd":
            cmd = val
            i += 1
            if cmd in "Zz":
                flush_ring()
                pos = start
                prev_c2 = None
            continue
        # gather numbers for one instance of `cmd`
        arity = {"M": 2, "m": 2, "L": 2, "l": 2, "H": 1, "h": 1, "V": 1, "v": 1,
                 "C": 6, "c": 6, "S": 4, "s": 4}.get(cmd)
        if arity is None:
            raise ValueError(f"unsupported path command {cmd!r}")
        nums = []
        while len(nums) < arity:
            k, v = toks[i]
            if k != "num":
                raise ValueError("malformed path: not enough operands")
            nums.append(v)
            i += 1
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            x, y = nums
            if rel:
                x, y = pos[0] + x, pos[1] + y
            flush_ring()
            pos = start = (x, y)
            cur = [pos]
            prev_c2 = None
            cmd = "l" if rel else "L"   # subsequent pairs are implicit lineto
        elif c in ("L", "H", "V"):
            if c == "L":
                x, y = nums
                if rel:
                    x, y = pos[0] + x, pos[1] + y
            elif c == "H":
                x = pos[0] + nums[0] if rel else nums[0]
                y = pos[1]
            else:
                x = pos[0]
                y = pos[1] + nums[0] if rel else nums[0]
            pos = (x, y)
            cur.append(pos)
            prev_c2 = None
        elif c in ("C", "S"):
            if c == "C":
                x1, y1, x2, y2, x, y = nums
                if rel:
                    x1, y1 = pos[0] + x1, pos[1] + y1
                    x2, y2 = pos[0] + x2, pos[1] + y2
                    x, y = pos[0] + x, pos[1] + y
            else:
                x2, y2, x, y = nums
                if rel:
                    x2, y2 = pos[0] + x2, pos[1] + y2
                    x, y = pos[0] + x, pos[1] + y
                if prev_c2 is None:
                    x1, y1 = pos
                else:
                    x1, y1 = 2 * pos[0] - prev_c2[0], 2 * pos[1] - prev_c2[1]
            flatten_cubic(pos, (x1, y1), (x2, y2), (x, y), cur)
            prev_c2 = (x2, y2)
            pos = (x, y)
    flush_ring()
    return rings


def parse_points(s: str):
    vals = [float(v) for v in re.split(r"[,\s]+", s.strip()) if v]
    return [(vals[i], vals[i + 1]) for i in range(0, len(vals) - 1, 2)]


# ---------------------------------------------------------------------------
# polyline simplification
# ---------------------------------------------------------------------------

def dp_simplify(pts, tol):
    if len(pts) < 3:
        return pts[:]
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        norm = math.hypot(dx, dy)
        best, best_d = -1, tol
        for k in range(a + 1, b):
            px, py = pts[k]
            if norm < EPS:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs((px - ax) * dy - (py - ay) * dx) / norm
            if d > best_d:
                best, best_d = k, d
        if best >= 0:
            keep[best] = True
            stack.append((a, best))
            stack.append((best, b))
    return [p for p, k in zip(pts, keep) if k]


def simplify_ring(ring, tol):
    """Simplify a closed ring: rotate to an extreme point so the seam is stable."""
    pts = dedupe(ring)
    if len(pts) < 4:
        return pts
    # start at the lowest-then-leftmost point so DP anchors on a real corner
    k = min(range(len(pts)), key=lambda i: (pts[i][1], pts[i][0]))
    pts = pts[k:] + pts[:k]
    out = dp_simplify(pts + [pts[0]], tol)
    if out and out[0] == out[-1]:
        out = out[:-1]
    return out


def dedupe(pts):
    out = []
    for p in pts:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 1e-7:
            out.append(p)
    while len(out) > 1 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) <= 1e-7:
        out.pop()
    return out


# ---------------------------------------------------------------------------
# scanline trapezoid decomposition (nonzero winding, matches the SVG renderer)
# ---------------------------------------------------------------------------

class EdgeSet:
    """Non-horizontal edges of one or more rings, indexed for scanline queries."""

    def __init__(self, rings):
        self.edges = []          # (y_lo, y_hi, x_at_ylo, slope_dx_dy, winding_dir)
        self.ys = set()
        for ring in rings:
            n = len(ring)
            for i in range(n):
                x0, y0 = ring[i]
                x1, y1 = ring[(i + 1) % n]
                self.ys.add(y0)
                self.ys.add(y1)
                if abs(y1 - y0) < EPS:
                    continue
                direction = 1 if y1 > y0 else -1
                lo, hi = (y0, y1) if y1 > y0 else (y1, y0)
                xlo = x0 if y1 > y0 else x1
                slope = (x1 - x0) / (y1 - y0)
                self.edges.append((lo, hi, xlo, slope, direction, len(self.edges)))

    def x_at(self, e, y):
        return e[2] + (y - e[0]) * e[3]

    def spans(self, ym, y0, y1):
        """Inside spans at scan y=ym, each as (xL0, xL1, xR0, xR1, idL, idR)
        where xL0/xL1 are the left boundary x at y0/y1 (likewise right)."""
        hits = []
        for e in self.edges:
            if e[0] <= ym < e[1]:
                hits.append((self.x_at(e, ym), e[4], e))
        hits.sort(key=lambda h: h[0])
        out = []
        wind = 0
        open_hit = None
        for x, d, e in hits:
            prev = wind
            wind += d
            if prev == 0 and wind != 0:
                open_hit = (x, e)
            elif prev != 0 and wind == 0 and open_hit is not None:
                xl, el = open_hit
                out.append((self.x_at(el, y0), self.x_at(el, y1),
                            self.x_at(e, y0), self.x_at(e, y1), el[5], e[5]))
                open_hit = None
        return out


def crossing_ys(a: EdgeSet, b: EdgeSet):
    """y of every proper crossing between an edge of `a` and an edge of `b`.

    These must become band boundaries: inside a band each boundary is a single
    straight segment, and the whole decomposition relies on the left/right
    boundaries keeping their order across the band. If a silhouette edge and a
    panel edge cross mid-band, the boundary chosen at the mid-scan is the wrong
    one at the band's top or bottom and the trapezoid degenerates into a bowtie
    that shoots out sideways.
    """
    out = set()
    for ea in a.edges:
        ax0, ay0 = ea[2], ea[0]
        ax1, ay1 = a.x_at(ea, ea[1]), ea[1]
        for eb in b.edges:
            if ea[1] <= eb[0] or eb[1] <= ea[0]:
                continue
            bx0, by0 = eb[2], eb[0]
            bx1, by1 = b.x_at(eb, eb[1]), eb[1]
            rx, ry = ax1 - ax0, ay1 - ay0
            sx, sy = bx1 - bx0, by1 - by0
            den = rx * sy - ry * sx
            if abs(den) < 1e-12:
                continue
            t = ((bx0 - ax0) * sy - (by0 - ay0) * sx) / den
            u = ((bx0 - ax0) * ry - (by0 - ay0) * rx) / den
            if 0.0 < t < 1.0 and 0.0 < u < 1.0:
                out.add(ay0 + t * ry)
    return out


def trapezoids(sil: EdgeSet, panel: EdgeSet | None):
    """Trapezoid decomposition of sil (∩ panel when given)."""
    ys = set(sil.ys)
    if panel is not None:
        ys |= set(panel.ys)
        ys |= crossing_ys(sil, panel)
        ymin = min(e[0] for e in panel.edges)
        ymax = max(e[1] for e in panel.edges)
        ys = {y for y in ys if ymin - EPS <= y <= ymax + EPS}
        ys.add(ymin)
        ys.add(ymax)
    ys = sorted(ys)
    out = []
    for i in range(len(ys) - 1):
        y0, y1 = ys[i], ys[i + 1]
        if y1 - y0 < 1e-7:
            continue
        ym = 0.5 * (y0 + y1)
        a = sil.spans(ym, y0, y1)
        if not a:
            continue
        if panel is None:
            band = a
        else:
            b = panel.spans(ym, y0, y1)
            if not b:
                continue
            band = []
            for sa in a:
                for sb in b:
                    # Intersect the two spans. No boundary crossing exists inside
                    # the band (crossing_ys made every crossing a band edge), so
                    # the per-y max/min below always resolves to one same edge.
                    la = 0.5 * (sa[0] + sa[1]); ra = 0.5 * (sa[2] + sa[3])
                    lb = 0.5 * (sb[0] + sb[1]); rb = 0.5 * (sb[2] + sb[3])
                    if max(la, lb) >= min(ra, rb) - 1e-9:
                        continue
                    left = sa if la >= lb else sb
                    right = sa if ra <= rb else sb
                    band.append((max(sa[0], sb[0]), max(sa[1], sb[1]),
                                 min(sa[2], sb[2]), min(sa[3], sb[3]),
                                 ("s" if left is sa else "p", left[4]),
                                 ("s" if right is sa else "p", right[5])))
        for sp in band:
            out.append((y0, y1) + sp)
    return merge_bands(out)


def merge_bands(traps):
    """Merge vertically adjacent trapezoids bounded by the same edge pair."""
    merged = []
    for t in traps:
        if merged:
            p = merged[-1]
            same_edges = p[6] == t[6] and p[7] == t[7]
            contiguous = abs(p[1] - t[0]) < 1e-7
            joins = abs(p[3] - t[2]) < 1e-6 and abs(p[5] - t[4]) < 1e-6
            if same_edges and contiguous and joins:
                merged[-1] = (p[0], t[1], p[2], t[3], p[4], t[5], p[6], p[7])
                continue
        merged.append(t)
    return merged


def trapezoid_triangles(traps):
    """Two triangles per trapezoid, skipping degenerate corners."""
    tris = []
    for y0, y1, xl0, xl1, xr0, xr1, _a, _b in traps:
        tl, tr = (xl0, y0), (xr0, y0)
        bl, br = (xl1, y1), (xr1, y1)
        top_deg = abs(xr0 - xl0) < 1e-7
        bot_deg = abs(xr1 - xl1) < 1e-7
        if top_deg and bot_deg:
            continue
        if top_deg:
            tris.append((tl, br, bl))
        elif bot_deg:
            tris.append((tl, tr, bl))
        else:
            tris.append((tl, tr, br))
            tris.append((tl, br, bl))
    return tris


# ---------------------------------------------------------------------------
# colour / gradient helpers
# ---------------------------------------------------------------------------

def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hex(rgb):
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02x}" for c in rgb)


def pct(v):
    v = v.strip()
    return float(v[:-1]) / 100.0 if v.endswith("%") else float(v)


def gradient_points(grad, bbox):
    """SVG objectBoundingBox linearGradient -> two user-space points."""
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0, y1 - y0
    gx1 = pct(grad.get("x1", "0%")); gy1 = pct(grad.get("y1", "0%"))
    gx2 = pct(grad.get("x2", "100%")); gy2 = pct(grad.get("y2", "0%"))
    return ((x0 + gx1 * w, y0 + gy1 * h), (x0 + gx2 * w, y0 + gy2 * h))


def eval_gradient(p0, p1, c0, c1, pt):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    den = dx * dx + dy * dy
    t = 0.0 if den < EPS else ((pt[0] - p0[0]) * dx + (pt[1] - p0[1]) * dy) / den
    t = max(0.0, min(1.0, t))
    a, b = hex_to_rgb(c0), hex_to_rgb(c1)
    return rgb_to_hex(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))


def bbox_of(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def polygon_centroid(pts):
    a = cx = cy = 0.0
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        cr = x0 * y1 - x1 * y0
        a += cr
        cx += (x0 + x1) * cr
        cy += (y0 + y1) * cr
    if abs(a) < EPS:
        return (sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n)
    a *= 0.5
    return (cx / (6 * a), cy / (6 * a))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    web = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    ap = argparse.ArgumentParser()
    ap.add_argument("--svg", default=os.path.join(web, "assets", "brand", "duduclaw-cat.svg"))
    ap.add_argument("--out", default=os.path.join(web, "assets", "data", "cat-panels.json"))
    ap.add_argument("--debug-svg", default=None, help="also write a flat SVG of the triangles")
    args = ap.parse_args()

    tree = ET.parse(args.svg)
    root = tree.getroot()
    view = [float(v) for v in root.get("viewBox").split()]

    # --- gradients ------------------------------------------------------
    grads = {}
    for g in root.iter(f"{SVG_NS}linearGradient"):
        stops = [(pct(s.get("offset", "0")), s.get("stop-color"))
                 for s in g.findall(f"{SVG_NS}stop")]
        grads[g.get("id")] = {"attrs": g.attrib, "stops": stops}

    # --- silhouette -----------------------------------------------------
    clip = root.find(f".//{SVG_NS}clipPath[@id='cut']/{SVG_NS}path")
    raw_rings = parse_path(clip.get("d"))
    rings = [simplify_ring(r, SIMPLIFY_TOL) for r in raw_rings]
    rings = [r for r in rings if len(r) >= 3]
    raw_pts = sum(len(r) for r in raw_rings)
    sim_pts = sum(len(r) for r in rings)

    all_pts = [p for r in rings for p in r]
    sx0, sy0, sx1, sy1 = bbox_of(all_pts)
    cx, cy = (sx0 + sx1) / 2.0, (sy0 + sy1) / 2.0

    def T(p):
        """SVG user space -> centred, y-up model space."""
        return (round(p[0] - cx, 3), round(cy - p[1], 3))

    sil = EdgeSet(rings)

    # --- panels ---------------------------------------------------------
    polys = list(root.iter(f"{SVG_NS}polygon"))
    if len(polys) != len(PANEL_ORDER):
        raise SystemExit(f"expected {len(PANEL_ORDER)} polygons, found {len(polys)}")

    panels = []

    def make_panel(pid, label, order, tris, fill_attr, poly_pts, hinge, fold):
        # gradient / flat colour
        if fill_attr.startswith("url(#"):
            gid = fill_attr[5:-1]
            g = grads[gid]
            gb = bbox_of(poly_pts) if poly_pts else (view[0], view[1], view[2], view[3])
            p0, p1 = gradient_points(g["attrs"], gb)
            c0 = g["stops"][0][1]
            c1 = g["stops"][-1][1]
        else:
            p0 = p1 = (0.0, 0.0)
            c0 = c1 = fill_attr
        centre = polygon_centroid(poly_pts) if poly_pts else ((sx0 + sx1) / 2, (sy0 + sy1) / 2)
        flat = eval_gradient(p0, p1, c0, c1, centre)
        # Emit counter-clockwise in model space. T() flips y, which flips
        # handedness, so decide the winding *after* the transform rather than
        # reasoning about it in SVG coordinates. A clockwise triangle would be a
        # back face at rest and `gl_FrontFacing` in the shader would negate its
        # normal, turning the key light off for the whole panel.
        verts = []
        flipped = 0
        for tri in tris:
            a, b, c = (T(p) for p in tri)
            area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if area < 0:
                b, c = c, b
                flipped += 1
            for q in (a, b, c):
                verts.append(q[0])
                verts.append(q[1])
        panels.append({
            "id": pid,
            "label": label,
            "order": order,
            "z": round(order * Z_STEP, 3),
            "color": flat,
            "gradient": {"p0": list(T(p0)), "p1": list(T(p1)), "c0": c0, "c1": c1},
            "hinge": hinge,
            "fold": fold,
            "triangles": len(tris),
            "vertices": verts,
        })

    # base plate: whole silhouette, torso gradient over the <rect> bbox
    base_tris = trapezoid_triangles(trapezoids(sil, None))
    rect = root.find(f".//{SVG_NS}rect")
    rect_box = [(0.0, 0.0),
                (float(rect.get("width")), 0.0),
                (float(rect.get("width")), float(rect.get("height"))),
                (0.0, float(rect.get("height")))]
    make_panel("base", "silhouette base plate", 0, base_tris,
               rect.get("fill"), rect_box, None,
               {"angle": 0.0, "sign": 1, "delay": 0.0})

    for idx, (pid, label) in enumerate(PANEL_ORDER):
        el = polys[idx]
        pts = parse_points(el.get("points"))
        spec = PANEL_SPEC[pid]
        tris = trapezoid_triangles(trapezoids(sil, EdgeSet([pts])))
        # hinge edge on the *source* polygon: longest edge, or an override
        n = len(pts)
        if spec["hinge"] >= 0:
            hi = spec["hinge"]
        else:
            hi = max(range(n), key=lambda i: math.dist(pts[i], pts[(i + 1) % n]))
        a, b = pts[hi], pts[(hi + 1) % n]
        hinge = {"a": list(T(a)), "b": list(T(b))}
        fold = {"angle": float(spec["angle"]), "sign": int(spec["sign"]),
                "delay": float(spec["delay"])}
        make_panel(pid, label, idx + 1, tris, el.get("fill"), pts, hinge, fold)

    total_tris = sum(p["triangles"] for p in panels)
    doc = {
        "meta": {
            "source": "assets/brand/duduclaw-cat.svg",
            "generator": "assets/js/cat3d/tools/build-panels.py",
            "viewBox": view,
            "space": "svg user units, centred on the silhouette bbox, +y up",
            "size": [round(sx1 - sx0, 3), round(sy1 - sy0, 3)],
            "centre_svg": [round(cx, 3), round(cy, 3)],
            "flatten_tol": FLATTEN_TOL,
            "simplify_tol": SIMPLIFY_TOL,
            "z_step": Z_STEP,
            "silhouette_points": {"flattened": raw_pts, "simplified": sim_pts},
            "panels": len(panels),
            "triangles": total_tris,
        },
        "panels": panels,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(doc, f, separators=(",", ":"))
        f.write("\n")

    if args.debug_svg:
        write_debug_svg(args.debug_svg, doc, sx1 - sx0, sy1 - sy0)

    print(f"svg            : {args.svg}")
    print(f"silhouette pts : {raw_pts} flattened -> {sim_pts} simplified (tol {SIMPLIFY_TOL})")
    print(f"panels         : {len(panels)}")
    for p in panels:
        print(f"  {p['order']}  {p['id']:<14} tris={p['triangles']:<5} color={p['color']} z={p['z']}")
    print(f"triangles      : {total_tris}")
    print(f"out            : {args.out} ({os.path.getsize(args.out)} bytes)")


def write_debug_svg(path, doc, w, h):
    """Flat 2D render of the generated triangles — for eyeballing the geometry."""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-w/2} {-h/2} {w} {h}">']
    for p in doc["panels"]:
        g = p["gradient"]
        gid = f"g{p['order']}"
        out.append(
            f'<defs><linearGradient id="{gid}" gradientUnits="userSpaceOnUse" '
            f'x1="{g["p0"][0]}" y1="{-g["p0"][1]}" x2="{g["p1"][0]}" y2="{-g["p1"][1]}">'
            f'<stop offset="0" stop-color="{g["c0"]}"/>'
            f'<stop offset="1" stop-color="{g["c1"]}"/></linearGradient></defs>')
        v = p["vertices"]
        out.append(f'<g fill="url(#{gid})">')
        for i in range(0, len(v), 6):
            pts = " ".join(f"{v[i+k]},{-v[i+k+1]}" for k in (0, 2, 4))
            out.append(f'<polygon points="{pts}"/>')
        out.append("</g>")
    out.append("</svg>")
    with open(path, "w") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    sys.setrecursionlimit(10000)
    main()
