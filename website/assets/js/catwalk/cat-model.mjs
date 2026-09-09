/* Origami DuDuClaw cat: faceted paper prisms on a Transform hierarchy.
 *
 * Idle matches the brand mascot: rump on the floor, torso nearly vertical,
 * one forepaw raised, the other hanging, tail along the ground then up.
 * Feet are planted with two-bone IK so soles stay at y = 0.
 */

import { Transform, Geometry, Mesh, Mat4 } from '../../vendor/ogl.mjs';

export const CRIMSON = {
  lit:   [1.000, 0.478, 0.494], // #ff7a7e
  mid:   [0.949, 0.337, 0.357], // #f2565b
  body:  [0.910, 0.314, 0.333], // #e85055
  shade: [0.776, 0.208, 0.227], // #c6353a
  dark:  [0.690, 0.180, 0.200], // #b02e33
};

export const MOUSE_GRAY = {
  lit:   [0.831, 0.831, 0.847],
  mid:   [0.624, 0.624, 0.663],
  body:  [0.560, 0.560, 0.600],
  shade: [0.520, 0.520, 0.560],
  dark:  [0.482, 0.482, 0.522],
};

const DEG = Math.PI / 180;
const _inv = new Mat4();

/* ---------- geometry ---------- */

function colorFromNormal(nx, ny, nz, pal) {
  const ax = Math.abs(nx), ay = Math.abs(ny), az = Math.abs(nz);
  const shade = pal.shade || pal.dark;
  const body = pal.body || pal.mid;
  if (ay >= ax && ay >= az) return ny >= 0 ? pal.lit : pal.dark;
  if (az >= ax) return nz >= 0 ? pal.mid : shade;
  return nx >= 0 ? body : shade;
}

function pushTri(pos, col, a, b, c, rgb) {
  pos.push(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]);
  col.push(rgb[0], rgb[1], rgb[2], rgb[0], rgb[1], rgb[2], rgb[0], rgb[1], rgb[2]);
}

function pushQuad(pos, col, a, b, c, d, rgb) {
  pushTri(pos, col, a, b, c, rgb);
  pushTri(pos, col, a, c, d, rgb);
}

function faceNormal(a, b, c) {
  const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
  const vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
  const nx = uy * vz - uz * vy;
  const ny = uz * vx - ux * vz;
  const nz = ux * vy - uy * vx;
  const len = Math.hypot(nx, ny, nz) || 1;
  return [nx / len, ny / len, nz / len];
}

function coloredQuad(pos, col, a, b, c, d, pal, override) {
  const n = faceNormal(a, b, c);
  pushQuad(pos, col, a, b, c, d, override || colorFromNormal(n[0], n[1], n[2], pal));
}

function finishGeo(gl, pos, col) {
  return new Geometry(gl, {
    position: { size: 3, data: new Float32Array(pos) },
    color:    { size: 3, data: new Float32Array(col) },
  });
}

export function boxGeo(gl, w, h, d, pal, paint) {
  const x = w / 2, y = h / 2, z = d / 2;
  const pos = [], col = [];
  const P = (px, py, pz) => [px, py, pz];
  const face = (a, b, c, d, key) => coloredQuad(pos, col, a, b, c, d, pal, paint && paint[key]);
  face(P(-x, y, -z), P(-x, y, z), P(x, y, z), P(x, y, -z), 'top');
  face(P(-x, -y, z), P(-x, -y, -z), P(x, -y, -z), P(x, -y, z), 'bottom');
  face(P(-x, -y, z), P(x, -y, z), P(x, y, z), P(-x, y, z), 'front');
  face(P(x, -y, -z), P(-x, -y, -z), P(-x, y, -z), P(x, y, -z), 'back');
  face(P(x, -y, -z), P(x, y, -z), P(x, y, z), P(x, -y, z), 'right');
  face(P(-x, -y, z), P(-x, y, z), P(-x, y, -z), P(-x, -y, -z), 'left');
  return finishGeo(gl, pos, col);
}

/** Frustum along X: back (x=-L/2) is (h0, w0), front (x=+L/2) is (h1, w1). */
export function taperBoxGeo(gl, length, h0, w0, h1, w1, pal) {
  const x0 = -length / 2, x1 = length / 2;
  const hb = h0 / 2, wb = w0 / 2, hf = h1 / 2, wf = w1 / 2;
  const B = [[x0, hb, -wb], [x0, hb, wb], [x0, -hb, wb], [x0, -hb, -wb]];
  const F = [[x1, hf, -wf], [x1, hf, wf], [x1, -hf, wf], [x1, -hf, -wf]];
  const pos = [], col = [];
  coloredQuad(pos, col, B[0], B[1], F[1], F[0], pal); // top
  coloredQuad(pos, col, B[2], B[3], F[3], F[2], pal); // bottom
  coloredQuad(pos, col, B[1], B[2], F[2], F[1], pal); // +Z
  coloredQuad(pos, col, B[3], B[0], F[0], F[3], pal); // -Z
  coloredQuad(pos, col, B[0], B[3], B[2], B[1], pal); // back
  coloredQuad(pos, col, F[0], F[1], F[2], F[3], pal); // front
  return finishGeo(gl, pos, col);
}

export function triPrismGeo(gl, base, height, thick, pal) {
  const z = thick / 2;
  const tF = [0, height, z], tB = [0, height, -z];
  const lF = [-base / 2, 0, z], lB = [-base / 2, 0, -z];
  const rF = [ base / 2, 0, z], rB = [ base / 2, 0, -z];
  const pos = [], col = [];
  const nF = faceNormal(lF, rF, tF);
  pushTri(pos, col, lF, rF, tF, colorFromNormal(nF[0], nF[1], nF[2], pal));
  const nB = faceNormal(rB, lB, tB);
  pushTri(pos, col, rB, lB, tB, colorFromNormal(nB[0], nB[1], nB[2], pal));
  coloredQuad(pos, col, lB, lF, tF, tB, pal);
  coloredQuad(pos, col, rF, rB, tB, tF, pal);
  coloredQuad(pos, col, lB, rB, rF, lF, pal);
  return finishGeo(gl, pos, col);
}

function meshOf(gl, program, geo, parent, x, y, z) {
  const m = new Mesh(gl, { geometry: geo, program, frustumCulled: false });
  m.position.set(x, y, z);
  m.setParent(parent);
  return m;
}

function joint(parent, x, y, z, name) {
  const t = new Transform();
  t.position.set(x, y, z);
  t.setParent(parent);
  t.name = name;
  return t;
}

/* ---------- skeleton ---------- */

export const LEG = {
  upper: 0.132,
  lower: 0.128,
  paw:   0.034,
  thick: 0.045,
};
const BODY_LEN = 0.56;
const HEAD_W = BODY_LEN * 0.30; // 0.168, visual bump below
const TAIL = 0.62;

export const METRICS = {
  bodyLen: BODY_LEN,
  headW: 0.30,
  legLen: LEG.upper + LEG.lower + LEG.paw,
  tailLen: TAIL,
  standH: 0.50,
  hipStand: 0.300,
  hipSit: 0.128,
  pawY: 0.017,
};

const LIMITS = {
  hips:   { x: [-30, 30], y: [-45, 45], z: [-40, 90] },
  spine:  { x: [-25, 25], y: [-30, 30], z: [-40, 90] },
  chest:  { x: [-20, 20], y: [-25, 25], z: [-35, 50] },
  neck:   { x: [-30, 40], y: [-60, 60], z: [-40, 40] },
  head:   { x: [-25, 30], y: [-40, 40], z: [-30, 30] },
  shoulder:{ x: [-40, 50], y: [-30, 30], z: [-100, 130] },
  hip:    { x: [-35, 40], y: [-25, 25], z: [-90, 90] },
  upper:  { x: [-25, 25], y: [-20, 20], z: [-100, 130] },
  lower:  { x: [-15, 15], y: [-12, 12], z: [-160, 15] },
  paw:    { x: [-25, 25], y: [-20, 20], z: [-50, 50] },
  tail:   { x: [-40, 50], y: [-70, 70], z: [-95, 50] },
};

function clampJoint(node, spec) {
  if (!spec) return;
  const r = node.rotation;
  const cl = (v, a) => Math.max(a[0] * DEG, Math.min(a[1] * DEG, v));
  if (spec.x) r.x = cl(r.x, spec.x);
  if (spec.y) r.y = cl(r.y, spec.y);
  if (spec.z) r.z = cl(r.z, spec.z);
}

function addLeg(gl, program, pal, parent, name) {
  const hip = joint(parent, 0, 0, 0, name);
  const t = LEG.thick;
  const upper = joint(hip, 0, 0, 0, name + 'Upper');
  meshOf(gl, program, boxGeo(gl, t, LEG.upper, t * 0.78, pal), upper, 0, -LEG.upper / 2, 0);

  const lower = joint(upper, 0, -LEG.upper, 0, name + 'Lower');
  meshOf(gl, program, boxGeo(gl, t * 0.92, LEG.lower, t * 0.72, pal), lower, 0, -LEG.lower / 2, 0);

  const paw = joint(lower, 0, -LEG.lower, 0, name + 'Paw');
  meshOf(gl, program, boxGeo(gl, t * 1.45, LEG.paw, t * 1.7, pal, {
    top: pal.lit, bottom: pal.dark,
  }), paw, 0.01, -LEG.paw / 2, 0);

  return { hip, upper, lower, paw };
}

export function createCat(gl, program) {
  const pal = CRIMSON;
  const root = new Transform();
  root.name = 'root';

  const hips = joint(root, 0, METRICS.hipStand, 0, 'hips');

  // Flat paper loaf (width > height).
  meshOf(gl, program, boxGeo(gl, 0.16, 0.11, 0.16, pal), hips, -0.05, 0.02, 0);

  const crease = meshOf(gl, program, boxGeo(gl, 0.16, 0.10, 0.012, pal, {
    top: pal.mid, front: pal.shade, back: pal.shade,
    left: pal.dark, right: pal.body, bottom: pal.dark,
  }), hips, -0.02, 0.00, 0.102);
  crease.rotation.z = -24 * DEG;

  const spine = joint(hips, 0.07, 0.018, 0, 'spine');
  meshOf(gl, program, boxGeo(gl, 0.13, 0.10, 0.15, pal), spine, 0.05, 0.008, 0);

  const chest = joint(spine, 0.12, 0.012, 0, 'chest');
  meshOf(gl, program, boxGeo(gl, 0.14, 0.095, 0.14, pal), chest, 0.055, 0.01, 0);

  const neck = joint(chest, 0.12, 0.032, 0, 'neck');
  meshOf(gl, program, boxGeo(gl, 0.04, 0.07, 0.10, pal), neck, 0.016, 0.008, 0);

  const head = joint(neck, 0.03, 0.022, 0, 'head');
  // Short wedge: wide at the back, narrower in front. Height < width.
  meshOf(gl, program,
    taperBoxGeo(gl, 0.14, 0.20, 0.26, 0.16, 0.20, pal),
    head, 0.055, 0.018, 0);
  const snout = meshOf(gl, program, boxGeo(gl, 0.03, 0.05, 0.07, pal), head, 0.145, -0.02, 0);

  // Two upright paper triangles, spaced apart.
  const earL = joint(head, 0.00, 0.12,  0.10, 'earL');
  meshOf(gl, program, triPrismGeo(gl, 0.09, 0.12, 0.018, pal), earL, 0, 0, 0);
  earL.rotation.y = 8 * DEG;
  const earR = joint(head, 0.00, 0.12, -0.10, 'earR');
  meshOf(gl, program, triPrismGeo(gl, 0.09, 0.12, 0.018, pal), earR, 0, 0, 0);
  earR.rotation.y = -8 * DEG;

  const shoulderL = joint(chest, 0.02, -0.02,  0.078, 'shoulderL');
  const shoulderR = joint(chest, 0.02, -0.02, -0.078, 'shoulderR');
  const fl = addLeg(gl, program, pal, shoulderL, 'fl');
  const fr = addLeg(gl, program, pal, shoulderR, 'fr');

  const hipL = joint(hips, -0.05, -0.035,  0.072, 'hipL');
  const hipR = joint(hips, -0.05, -0.035, -0.072, 'hipR');
  const hl = addLeg(gl, program, pal, hipL, 'hl');
  const hr = addLeg(gl, program, pal, hipR, 'hr');

  // Thick rectangular tail, three segments.
  const tailBase = joint(hips, -0.12, 0.00, 0.04, 'tailBase');
  const tSeg = TAIL / 3;
  meshOf(gl, program, boxGeo(gl, tSeg, 0.055, 0.085, pal), tailBase, -tSeg / 2, 0, 0);
  const tailMid = joint(tailBase, -tSeg, 0, 0, 'tailMid');
  meshOf(gl, program, boxGeo(gl, tSeg, 0.050, 0.078, pal), tailMid, -tSeg / 2, 0, 0);
  const tailTip = joint(tailMid, -tSeg, 0, 0, 'tailTip');
  meshOf(gl, program, boxGeo(gl, tSeg * 0.88, 0.042, 0.068, pal), tailTip, -tSeg / 2, 0, 0);

  const joints = {
    root, hips, spine, chest, neck, head, earL, earR,
    shoulderL, shoulderR, hipL, hipR,
    flUpper: fl.upper, flLower: fl.lower, flPaw: fl.paw,
    frUpper: fr.upper, frLower: fr.lower, frPaw: fr.paw,
    hlUpper: hl.upper, hlLower: hl.lower, hlPaw: hl.paw,
    hrUpper: hr.upper, hrLower: hr.lower, hrPaw: hr.paw,
    tailBase, tailMid, tailTip, snout,
  };

  function applyLimits() {
    clampJoint(hips, LIMITS.hips);
    clampJoint(spine, LIMITS.spine);
    clampJoint(chest, LIMITS.chest);
    clampJoint(neck, LIMITS.neck);
    clampJoint(head, LIMITS.head);
    clampJoint(shoulderL, LIMITS.shoulder);
    clampJoint(shoulderR, LIMITS.shoulder);
    clampJoint(hipL, LIMITS.hip);
    clampJoint(hipR, LIMITS.hip);
    clampJoint(tailBase, LIMITS.tail);
    clampJoint(tailMid, LIMITS.tail);
    clampJoint(tailTip, LIMITS.tail);
  }

  return { root, joints, applyLimits };
}

export function createMouse(gl, program) {
  const pal = MOUSE_GRAY;
  const root = new Transform();
  const body = meshOf(gl, program, triPrismGeo(gl, 0.14, 0.08, 0.06, pal), root, 0.02, 0.042, 0);
  body.rotation.z = -90 * DEG;
  meshOf(gl, program, boxGeo(gl, 0.024, 0.038, 0.028, pal), root, -0.02, 0.082,  0.024);
  meshOf(gl, program, boxGeo(gl, 0.024, 0.038, 0.028, pal), root, -0.02, 0.082, -0.024);
  const tail = joint(root, -0.07, 0.024, 0, 'mouseTail');
  meshOf(gl, program, boxGeo(gl, 0.12, 0.01, 0.01, pal), tail, -0.06, 0, 0);
  return { root, tail };
}

export function createFloor(gl, program, half = 1.4) {
  const pal = {
    lit: [0.86, 0.86, 0.88], mid: [0.78, 0.78, 0.80], body: [0.74, 0.74, 0.76],
    shade: [0.68, 0.68, 0.70], dark: [0.58, 0.58, 0.60],
  };
  const root = new Transform();
  meshOf(gl, program, boxGeo(gl, half * 2, 0.012, 0.62, pal), root, 0, -0.006, 0);
  meshOf(gl, program, boxGeo(gl, half * 2, 0.003, 0.012, {
    lit: pal.dark, mid: pal.dark, body: pal.dark, shade: pal.dark, dark: pal.dark,
  }), root, 0, 0.002, 0);
  meshOf(gl, program, boxGeo(gl, 0.03, 0.04, 0.62, pal), root, -half, 0.014, 0);
  meshOf(gl, program, boxGeo(gl, 0.03, 0.04, 0.62, pal), root,  half, 0.014, 0);
  return root;
}

/* ---------- poses ---------- */

function legs(fl, fr, hl, hr) { return { fl, fr, hl, hr }; }

/** Natural cat sit: rump down, front legs planted, spine ~65° from the floor. */
export const POSE_IDLE = {
  hipsY: METRICS.hipSit,
  hips:  [4, 16, 22],
  spine: [0, 6, 36],
  chest: [0, 4, 8],
  neck:  [6, 18, 6],
  head:  [2, 12, 2],
  shoulderL: [0, 0, 0],
  shoulderR: [0, 0, 0],
  legs: legs(
    { upper: [0, 0, 8], lower: [0, 0, -18], paw: [0, 0, 6] },
    { upper: [0, 0, 8], lower: [0, 0, -18], paw: [0, 0, 6] },
    { upper: [0, 0, 28], lower: [0, 0, -70], paw: [0, 0, 12] },
    { upper: [0, 0, 28], lower: [0, 0, -70], paw: [0, 0, 12] },
  ),
  tail: { base: [8, 42, -16], mid: [6, 22, -24], tip: [4, 14, -38] },
};

export const POSE_STAND = {
  hipsY: METRICS.hipStand,
  hips:  [0, 0, 2],
  spine: [0, 0, 4],
  chest: [0, 0, 2],
  neck:  [2, 0, 2],
  head:  [0, 0, 0],
  legs: legs(
    { upper: [0, 0, 6], lower: [0, 0, -12], paw: [0, 0, 4] },
    { upper: [0, 0, 6], lower: [0, 0, -12], paw: [0, 0, 4] },
    { upper: [0, 0, 4], lower: [0, 0, -14], paw: [0, 0, 6] },
    { upper: [0, 0, 4], lower: [0, 0, -14], paw: [0, 0, 6] },
  ),
  tail: { base: [4, 8, -16], mid: [2, 6, -20], tip: [0, 4, -32] },
};

export const POSE_STALK = {
  hipsY: METRICS.hipStand * 0.60,
  hips:  [0, 0, -4],
  spine: [0, 0, 2],
  chest: [0, 0, 4],
  neck:  [10, 0, 8],
  head:  [4, 0, 4],
  legs: legs(
    { upper: [0, 0, 20], lower: [0, 0, -50], paw: [0, 0, 10] },
    { upper: [0, 0, 18], lower: [0, 0, -48], paw: [0, 0, 10] },
    { upper: [0, 0, 24], lower: [0, 0, -55], paw: [0, 0, 10] },
    { upper: [0, 0, 22], lower: [0, 0, -52], paw: [0, 0, 10] },
  ),
  tail: { base: [6, 8, -10], mid: [4, 6, -8], tip: [2, 4, -6] },
};

export const POSE_POUNCE = {
  hipsY: METRICS.hipStand,
  hips:  [0, 0, -6],
  spine: [0, 0, 0],
  chest: [0, 0, 4],
  neck:  [8, 0, 10],
  head:  [4, 0, 6],
  legs: legs(
    { upper: [0, 0, 70], lower: [0, 0, -8], paw: [0, 0, 4] },
    { upper: [0, 0, 66], lower: [0, 0, -8], paw: [0, 0, 4] },
    { upper: [0, 0, -55], lower: [0, 0, -4], paw: [0, 0, 2] },
    { upper: [0, 0, -58], lower: [0, 0, -4], paw: [0, 0, 2] },
  ),
  tail: { base: [0, 0, 8], mid: [0, 0, 6], tip: [0, 0, 4] },
};

export const POSE_CATCH = {
  hipsY: METRICS.hipSit + 0.04,
  hips:  [6, 0, 18],
  spine: [0, 0, 10],
  chest: [0, 0, 12],
  neck:  [12, 0, 8],
  head:  [8, 0, 4],
  legs: legs(
    { upper: [0, 0, 28], lower: [0, 0, -55], paw: [0, 0, 12] },
    { upper: [0, 0, 24], lower: [0, 0, -52], paw: [0, 0, 12] },
    { upper: [0, 0, 30], lower: [0, 0, -60], paw: [0, 0, 10] },
    { upper: [0, 0, 28], lower: [0, 0, -58], paw: [0, 0, 10] },
  ),
  tail: { base: [8, 30, -20], mid: [6, 26, -24], tip: [4, 20, -32] },
};

export const POSE_WALK = { ...POSE_STAND };
export const POSE_ENTER = JSON.parse(JSON.stringify(POSE_IDLE));

function setEuler(node, xyzDeg, mirrorY = 1) {
  node.rotation.x = xyzDeg[0] * DEG;
  node.rotation.y = xyzDeg[1] * DEG * mirrorY;
  node.rotation.z = xyzDeg[2] * DEG;
}

/**
 * `mirrorY` flips the yaw written into every joint. The sit and the catch
 * turn the head and the tail a little towards the camera, and those angles
 * are written in the cat's own frame: once it walks the other way they point
 * away instead, and the sit reads as the back of a box. Callers that know
 * which way the cat is facing pass -cos(yaw), which is +1 facing -X, -1
 * facing +X and slides smoothly through the turn. The default 1 keeps every
 * other caller (frozen poses, the lab) exactly as it was.
 */
export function applyPose(cat, pose, mirrorY = 1) {
  const j = cat.joints;
  const m = mirrorY;
  j.hips.position.y = pose.hipsY;
  setEuler(j.hips, pose.hips, m);
  setEuler(j.spine, pose.spine, m);
  setEuler(j.chest, pose.chest, m);
  setEuler(j.neck, pose.neck, m);
  setEuler(j.head, pose.head, m);
  if (pose.shoulderL) setEuler(j.shoulderL, pose.shoulderL, m);
  else setEuler(j.shoulderL, [0, 0, 0]);
  if (pose.shoulderR) setEuler(j.shoulderR, pose.shoulderR, m);
  else setEuler(j.shoulderR, [0, 0, 0]);
  const L = pose.legs;
  setEuler(j.flUpper, L.fl.upper, m); setEuler(j.flLower, L.fl.lower, m); setEuler(j.flPaw, L.fl.paw, m);
  setEuler(j.frUpper, L.fr.upper, m); setEuler(j.frLower, L.fr.lower, m); setEuler(j.frPaw, L.fr.paw, m);
  setEuler(j.hlUpper, L.hl.upper, m); setEuler(j.hlLower, L.hl.lower, m); setEuler(j.hlPaw, L.hl.paw, m);
  setEuler(j.hrUpper, L.hr.upper, m); setEuler(j.hrLower, L.hr.lower, m); setEuler(j.hrPaw, L.hr.paw, m);
  setEuler(j.tailBase, pose.tail.base, m);
  setEuler(j.tailMid, pose.tail.mid, m);
  setEuler(j.tailTip, pose.tail.tip, m);
}

function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

/**
 * Two-bone IK in the hip/shoulder sagittal plane. Plants the paw sole at
 * world (tx, ty, tz). Bones rest along local -Y; knee folds backward.
 */
function ikLeg(upper, lower, paw, L1, L2, tx, ty, tz) {
  const hip = upper.parent;
  hip.updateMatrixWorld(true);
  _inv.inverse(hip.worldMatrix);
  const m = _inv;
  const lx = m[0] * tx + m[4] * ty + m[8] * tz + m[12];
  const ly = m[1] * tx + m[5] * ty + m[9] * tz + m[13];

  let d = Math.hypot(lx, ly);
  const maxD = L1 + L2 - 0.004;
  const minD = Math.abs(L1 - L2) + 0.01;
  if (d < minD) d = minD;
  if (d > maxD) d = maxD;

  const ang = Math.atan2(lx, -ly);
  const cosK = (L1 * L1 + L2 * L2 - d * d) / (2 * L1 * L2);
  const knee = Math.acos(clamp(cosK, -1, 1));
  const cosA = (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d);
  const a = Math.acos(clamp(cosA, -1, 1));

  upper.rotation.x = 0;
  upper.rotation.y = 0;
  upper.rotation.z = ang + a;
  lower.rotation.x = 0;
  lower.rotation.y = 0;
  lower.rotation.z = knee - Math.PI;
  paw.rotation.x = 0;
  paw.rotation.y = 0;
  paw.rotation.z = -(upper.rotation.z + lower.rotation.z) * 0.35;
}

/**
 * Plant grounded feet at y = floorY.
 * `gait` is {id: {dx, lift}} in world X / Y.
 * `sit` tucks hind feet slightly forward so a sit does not splay.
 * `frontTarget` overrides both front paws (catch).
 * Airborne pounce skips planting.
 */
export function plantFeet(cat, opts = {}) {
  const floorY = opts.floorY || 0;
  const pawY = floorY + METRICS.pawY;
  const L1 = LEG.upper;
  const L2 = LEG.lower + LEG.paw;
  const gait = opts.gait || {};
  if (opts.airborne) return;

  cat.root.updateMatrixWorld(true);
  const facing = Math.cos(cat.root.rotation.y) >= 0 ? 1 : -1;
  const ids = ['fl', 'fr', 'hl', 'hr'];
  for (const id of ids) {
    const upper = cat.joints[id + 'Upper'];
    const lower = cat.joints[id + 'Lower'];
    const paw = cat.joints[id + 'Paw'];
    const hip = upper.parent;
    hip.updateMatrixWorld(true);
    const hx = hip.worldMatrix[12];
    const hz = hip.worldMatrix[14];
    const g = gait[id] || {};
    let tx, ty, tz;
    if (opts.frontTarget && (id === 'fl' || id === 'fr')) {
      const side = id === 'fl' ? 0.03 : -0.03;
      tx = opts.frontTarget[0];
      ty = Math.max(pawY, opts.frontTarget[1]);
      tz = opts.frontTarget[2] + side;
    } else {
      let dx = g.dx || 0;
      if (opts.sit && (id === 'hl' || id === 'hr')) dx += 0.05 * facing;
      tx = hx + dx;
      ty = pawY + (g.lift || 0);
      tz = hz;
    }
    ikLeg(upper, lower, paw, L1, L2, tx, ty, tz);
  }
}

export function gaitFromPhase(phase, amp = 1, facing = 1) {
  const stride = 0.09 * amp;
  const liftH = 0.055 * amp;
  function foot(ph) {
    const s = Math.sin(ph);
    const swing = s > 0;
    return {
      dx: stride * s * facing,
      lift: swing ? liftH * s : 0,
    };
  }
  return {
    fl: foot(phase),
    hr: foot(phase),
    fr: foot(phase + Math.PI),
    hl: foot(phase + Math.PI),
  };
}

export function overlayLife(cat, t, tailGain = 1, breathGain = 1) {
  const j = cat.joints;
  const wag = Math.sin(t * (Math.PI * 2) / 3);
  j.tailBase.rotation.y += 8 * tailGain * wag * DEG;
  j.tailMid.rotation.y  += 12 * tailGain * Math.sin(t * (Math.PI * 2) / 3 + 0.5) * DEG;
  j.tailTip.rotation.y  += 16 * tailGain * Math.sin(t * (Math.PI * 2) / 3 + 1.0) * DEG;
  const br = Math.sin(t * (Math.PI * 2) / 2.8);
  j.chest.scale.y = 1 + 0.03 * breathGain * br;
  j.chest.scale.z = 1 + 0.018 * breathGain * br;
}

export function overlayIdleWave(cat, t) {
  cat.joints.flUpper.rotation.z += 0.12 * Math.sin(t * 2.4);
  cat.joints.flLower.rotation.z += 0.06 * Math.sin(t * 2.4 + 0.4);
}

export function overlayTailShake(cat, t, gain = 1) {
  cat.joints.tailTip.rotation.y += 24 * gain * Math.sin(t * 22) * DEG;
  cat.joints.tailTip.rotation.z += 8 * gain * Math.sin(t * 18) * DEG;
}

export function overlayProudTail(cat, u) {
  const s = Math.sin(u * Math.PI);
  cat.joints.tailBase.rotation.y += 32 * s * DEG;
  cat.joints.tailMid.rotation.y  += 40 * s * DEG;
  cat.joints.tailTip.rotation.y  += 44 * s * DEG;
}

export function overlayHipTwist(cat, u) {
  cat.joints.hips.rotation.y += 14 * Math.sin(u * Math.PI * 3) * DEG;
}

export const NAMED_POSES = {
  idle: POSE_IDLE, enter: POSE_ENTER, walk: POSE_WALK, stand: POSE_STAND,
  stalk: POSE_STALK, pounce: POSE_POUNCE, catch: POSE_CATCH,
};

export function holdNamedPose(cat, name) {
  const key = name === 'walk' ? 'walk' : name;
  const pose = NAMED_POSES[key] || POSE_IDLE;
  applyPose(cat, pose);
  if (name === 'walk') {
    const facing = Math.cos(cat.root.rotation.y) >= 0 ? 1 : -1;
    plantFeet(cat, { gait: gaitFromPhase(0.85, 1, facing) });
  } else if (name === 'pounce') {
    /* airborne: keep stretch pose, no planting */
  } else if (name === 'idle' || name === 'enter') {
    plantFeet(cat, { sit: true });
  } else if (name === 'catch') {
    plantFeet(cat, { frontTarget: [cat.root.position.x - 0.12, METRICS.pawY + 0.02, 0] });
  } else {
    plantFeet(cat, {});
  }
  cat.applyLimits();
}
