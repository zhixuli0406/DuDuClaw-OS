/* DuDuClaw origami cat — walk / stalk / pounce / catch lab.
 *
 * mountCatWalk(container, options) draws a side-view paper cat that chases
 * a folded-paper mouse along a floor line. Returns false when it must not
 * run (reduced-motion, no WebGL). See README.md beside this file.
 */

import { Renderer, Camera, Transform, Geometry, Program, Mesh } from '../../vendor/ogl.mjs';
import {
  createCat, createMouse, createFloor,
  applyPose, overlayLife, overlayTailShake,
  overlayProudTail, overlayHipTwist, holdNamedPose,
  plantFeet, gaitFromPhase,
  POSE_IDLE, POSE_STAND, POSE_STALK, POSE_POUNCE, POSE_CATCH,
  METRICS,
} from './cat-model.mjs';

const DEG = Math.PI / 180;
const TURN_SPEED = 240 * DEG;     // rad / s
const ARRIVE = 0.35;
const STALK_NEAR = 0.35;
const STALK_FAR = 1.20;
const STILL_S = 1.20;
const POUNCE_S = 0.45;
const CATCH_S = 1.00;
const ESCAPE_MOVE = 0.20;
const SPRING_W = 16;              // ~200 ms settle, critically damped
const MOUSE_LAG = 0.12;
const FLOOR_HALF = 1.40;          // default walkable half-width, see `floorHalf`
const SPEED_MIN = 0.60;
const SPEED_MAX = 1.60;
const HZ_MIN = 1.40;
const HZ_MAX = 2.40;

const THEMES = {
  light: { clear: [0.953, 0.953, 0.953, 1], fog: [0.953, 0.953, 0.953] },
  dark:  { clear: [0.047, 0.047, 0.055, 1], fog: [0.047, 0.047, 0.055] },
};

const vertex = /* glsl */ `
precision highp float;
attribute vec3 position;
attribute vec3 color;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
varying vec3 vColor;
void main() {
  vColor = color;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const fragment = /* glsl */ `
precision highp float;
varying vec3 vColor;
uniform float uTint;
uniform float uOpacity;
void main() {
  gl_FragColor = vec4(vColor * uTint, uOpacity);
}`;

const shadowVertex = /* glsl */ `
precision highp float;
attribute vec3 position;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
void main() {
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const shadowFragment = /* glsl */ `
precision highp float;
uniform vec4 uColor;
void main() {
  gl_FragColor = uColor;
}`;

const flag = (name) => {
  try { return new URLSearchParams(location.search).get(name); }
  catch { return null; }
};

function hasWebGL() {
  if (flag('nowebgl') === '1') return false;
  try {
    const c = document.createElement('canvas');
    // Do not set failIfMajorPerformanceCaveat: the lab is screenshotted
    // under SwiftShader, which that flag would reject.
    return !!(c.getContext('webgl2') || c.getContext('webgl'));
  } catch { return false; }
}

function wrapAngle(a) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}

function lerp(a, b, t) { return a + (b - a) * t; }
function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

function spring1(state, target, dt, w = SPRING_W) {
  dt = Math.min(dt, 0.05);
  const x = state.v - target;
  const a = -2 * w * state.dv - w * w * x;
  state.dv += a * dt;
  state.v = target + x + state.dv * dt;
  return state.v;
}

function poseCopy(src) {
  return JSON.parse(JSON.stringify(src));
}

function poseLerp(out, a, b, t) {
  const mix = (p, q) => [lerp(p[0], q[0], t), lerp(p[1], q[1], t), lerp(p[2], q[2], t)];
  const zed = [0, 0, 0];
  out.hipsY = lerp(a.hipsY, b.hipsY, t);
  out.hips = mix(a.hips, b.hips);
  out.spine = mix(a.spine, b.spine);
  out.chest = mix(a.chest, b.chest);
  out.neck = mix(a.neck, b.neck);
  out.head = mix(a.head, b.head);
  out.shoulderL = mix(a.shoulderL || zed, b.shoulderL || zed);
  out.shoulderR = mix(a.shoulderR || zed, b.shoulderR || zed);
  for (const k of ['fl', 'fr', 'hl', 'hr']) {
    out.legs[k].upper = mix(a.legs[k].upper, b.legs[k].upper);
    out.legs[k].lower = mix(a.legs[k].lower, b.legs[k].lower);
    out.legs[k].paw   = mix(a.legs[k].paw,   b.legs[k].paw);
  }
  out.tail.base = mix(a.tail.base, b.tail.base);
  out.tail.mid  = mix(a.tail.mid,  b.tail.mid);
  out.tail.tip  = mix(a.tail.tip,  b.tail.tip);
  return out;
}

/**
 * @param {HTMLElement} container
 * @param {{floorY?: number, theme?: 'light'|'dark', targetMode?: 'pointer'|'tap'|'external',
 *          speedScale?: number, homeX?: number, floorHalf?: number, stillSeconds?: number,
 *          transparent?: boolean,
 *          showFloor?: boolean, startPaused?: boolean, startHidden?: boolean,
 *          camera?: {frameWidth?: number, frameHeight?: number, floorAnchor?: number,
 *                    azimuthDeg?: number, elevationDeg?: number, lookX?: number}}} options
 * @returns {false|{ready: Promise<boolean>, setTheme: Function, destroy: Function, onState: Function, enterFrom: Function, leaveTo: Function, setTarget: Function, pause: Function, resume: Function, pxPerUnit: number}}
 */
export function mountCatWalk(container, options = {}) {
  const reduced = flag('reducedmotion') === '1' ||
    (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  if (!container || reduced || !hasWebGL()) return false;

  let readyResolve;
  const ready = new Promise((r) => { readyResolve = r; });

  try {
  return mountInner();
  } catch (err) {
    console.warn('[catwalk] mount failed:', err);
    if (readyResolve) readyResolve(false);
    return false;
  }

  function mountInner() {
  const speedScale = options.speedScale == null ? 1 : options.speedScale;
  let targetMode = options.targetMode || 'pointer';
  let themeName = options.theme ||
    (document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light');
  if (!options.theme && window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches
      && document.documentElement.getAttribute('data-theme') !== 'light') {
    themeName = 'dark';
  }
  const floorY = options.floorY == null ? 0 : options.floorY;
  const frozenPose = flag('pose');           // idle|enter|walk|stalk|pounce|catch
  const homeX = options.homeX == null ? 0.35 : options.homeX;
  const autoplay = flag('autoplay') === '1';
  const themeFlag = flag('theme');
  if (themeFlag === 'light' || themeFlag === 'dark') themeName = themeFlag;

  /* Half-width of the walkable floor line. Everything that clamps the cat,
     the mouse or the pounce reads this, so a small stage can keep the whole
     cat inside the frame instead of walking it out of shot. */
  const floorHalf = options.floorHalf > 0 ? +options.floorHalf : FLOOR_HALF;
  /* The state machine's distances were tuned against the default floor. On a
     shorter floor they have to shrink with it, or the cat counts a mouse two
     thirds of the stage away as "arrived" and never walks. Gait speed is NOT
     scaled: stride length is a property of the legs, and scaling it would
     slide the feet along the ground. */
  const world = floorHalf / FLOOR_HALF;
  const arrive = ARRIVE * world;
  const stalkNear = STALK_NEAR * world;
  const stalkFar = STALK_FAR * world;
  const escapeMove = ESCAPE_MOVE * world;
  const settled = 0.12 * world;         // "close enough to home" epsilon
  /* How long the mouse must hold still before the cat commits to a stalk.
     On a short floor the cat reaches the mouse in well under the default
     1.2 s, and a stalk that can only start while it is still approaching
     would never fire at all. */
  const stillNeeded = options.stillSeconds > 0 ? +options.stillSeconds : STILL_S;
  /* Transparent stages (the home page hero) composite over whatever is behind
     them: no clear colour, and no floor slab to paint over the background. */
  const transparent = options.transparent === true;
  const showFloor = options.showFloor == null ? !transparent : options.showFloor !== false;
  /* Explicit camera framing. Absent, the original heuristic below runs
     unchanged — that is what the lab page is tuned against. */
  const cam = options.camera || null;
  let paused = options.startPaused === true;

  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  Object.assign(canvas.style, {
    position: 'absolute', inset: '0', width: '100%', height: '100%',
    display: 'block', touchAction: 'none',
  });
  if (getComputedStyle(container).position === 'static') container.style.position = 'relative';

  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const renderer = new Renderer({
    canvas, alpha: transparent, antialias: true, dpr,
    preserveDrawingBuffer: true, powerPreference: 'low-power',
  });
  const gl = renderer.gl;

  const camera = new Camera(gl, { fov: 30, near: 0.05, far: 20 });
  camera.position.set(-1.05, 0.82, 1.95);
  camera.lookAt([0.05, 0.28, 0]);

  const scene = new Transform();
  const program = new Program(gl, {
    vertex, fragment, cullFace: false, transparent: true,
    uniforms: { uTint: { value: 1 }, uOpacity: { value: 1 } },
  });
  const shadowProg = new Program(gl, {
    vertex: shadowVertex, fragment: shadowFragment,
    transparent: true, depthWrite: false, cullFace: false,
    uniforms: { uColor: { value: [0.05, 0.04, 0.04, 0.22] } },
  });
  /* Without a floor slab under it the contact patch is a hard-edged quad on
     the page background, so a transparent stage gets a much fainter one. */
  const shadowAlpha = transparent
    ? { light: 0.10, dark: 0.22 }
    : { light: 0.20, dark: 0.45 };

  const cat = createCat(gl, program);
  cat.root.setParent(scene);
  cat.root.position.y = floorY;

  const mouse = createMouse(gl, program);
  mouse.root.setParent(scene);
  mouse.root.position.set(0.55, floorY, 0);

  const floor = showFloor ? createFloor(gl, program, floorHalf) : null;
  if (floor) {
    floor.position.y = floorY;
    floor.setParent(scene);
  }

  const hw = 0.28, hd = 0.11;
  const shadowMesh = new Mesh(gl, {
    geometry: new Geometry(gl, {
      position: { size: 3, data: new Float32Array([
        -hw, 0, -hd,  hw, 0, -hd,  hw, 0,  hd,
        -hw, 0, -hd,  hw, 0,  hd, -hw, 0,  hd,
      ]) },
    }),
    program: shadowProg,
    frustumCulled: false,
  });
  const shadow = new Transform();
  shadowMesh.setParent(shadow);
  shadow.position.y = floorY + 0.008;
  shadow.setParent(scene);

  applyTheme(themeName);

  function eachMesh(node, fn) {
    if (node && typeof node.draw === 'function' && node.geometry) fn(node);
    const kids = node && node.children;
    if (kids) for (let i = 0; i < kids.length; i++) eachMesh(kids[i], fn);
  }
  let catOpacity = 1;
  eachMesh(cat.root, (m) => {
    m.onBeforeRender(() => { program.uniforms.uOpacity.value = catOpacity; });
  });
  eachMesh(mouse.root, (m) => {
    m.onBeforeRender(() => { program.uniforms.uOpacity.value = mouse.root.visible ? 1 : 0; });
  });
  if (floor) eachMesh(floor, (m) => {
    m.onBeforeRender(() => { program.uniforms.uOpacity.value = 1; });
  });

  // ---- runtime state ----
  let raf = null, visible = true, destroyed = false;
  let pxPerUnit = 0;              // rendered CSS px per floor unit (0 before layout)
  let lastT = 0, clock = 0;
  let state = frozenPose === 'walk' ? 'follow'
            : frozenPose === 'stalk' ? 'stalk'
            : frozenPose === 'pounce' ? 'pounce'
            : frozenPose === 'catch' ? 'catch'
            : frozenPose === 'enter' ? 'enter'
            : 'idle';
  let speed = 0, dist = 0;
  let yaw = Math.PI;
  const yawSpring = { v: Math.PI, dv: 0 };
  let walkPhase = 0.85;
  let catX = frozenPose === 'enter' ? homeX
           : frozenPose ? 0
           : (autoplay ? -0.25 : homeX);
  let mouseX = frozenPose === 'catch' ? -0.12
             : frozenPose === 'pounce' ? -0.35
             : frozenPose === 'idle' ? 0.22
             : autoplay ? -0.08
             : 0.55;
  let mouseVX = 0;
  let pointerX = mouseX;
  let pointerIn = false;
  let pointerMovedAt = -999;
  let lastPointerX = mouseX;
  let stillS = 0;
  let pounceT = 0, pounceFrom = 0, pounceTo = 0;
  let catchT = 0, catchOrigin = 0;
  let stalkT = 0;
  let fidgetIn = 3 + Math.random() * 3;
  let fidgetKind = 'none';
  let fidgetT = 0;
  let autoTimer = 2 + Math.random() * 2;
  let autoStill = false;
  let mouseCaught = false;
  let mouseScale = { v: 1, dv: 0 };
  let demoPhase = autoplay ? 'idlehold' : 'off';
  let demoT = 0;
  let hasTarget = targetMode !== 'external';
  let fade = null; // { t, dur, fromS, toS, fromO, toO, after }
  let leaveCb = null;
  let leaveX = null;
  const blended = poseCopy(POSE_IDLE);
  let poseTarget = poseCopy(POSE_IDLE);
  const listeners = [];
  let coarse = window.matchMedia ? matchMedia('(pointer: coarse)').matches : false;
  if (coarse && !options.targetMode) targetMode = 'tap';

  cat.root.position.x = catX;
  mouse.root.position.x = mouseX;

  cat.root.rotation.y = yaw;
  if (frozenPose) {
    holdNamedPose(cat, frozenPose === 'enter' ? 'idle' : frozenPose);
    if (frozenPose === 'pounce') {
      cat.root.position.y = floorY + 0.20;
      cat.root.position.x = 0;
      mouse.root.position.x = -0.42;
    }
    if (frozenPose === 'walk' || frozenPose === 'stalk') cat.root.position.x = 0;
    if (frozenPose === 'catch') {
      cat.root.position.x = 0;
      mouse.root.position.set(-0.20, floorY, 0.08);
      mouse.root.scale.set(0.7, 0.7, 0.7);
      plantFeet(cat, { frontTarget: [-0.18, METRICS.pawY + 0.02, 0.05] });
    }
    if (frozenPose === 'idle') {
      cat.root.position.x = 0;
      mouse.root.position.x = 0.28;
      plantFeet(cat, { sit: true });
    }
    if (frozenPose === 'enter') {
      cat.root.position.x = homeX;
      cat.root.scale.set(0.78, 0.78, 0.78);
      catOpacity = 0.55;
      mouse.root.visible = false;
      plantFeet(cat, { sit: true });
    }
    cat.root.rotation.y = yaw;
  }

  function applyTheme(name) {
    themeName = name === 'dark' ? 'dark' : 'light';
    const t = THEMES[themeName];
    if (transparent) gl.clearColor(0, 0, 0, 0);
    else gl.clearColor(t.clear[0], t.clear[1], t.clear[2], 1);
    shadowProg.uniforms.uColor.value = themeName === 'dark'
      ? [0.02, 0.02, 0.03, shadowAlpha.dark]
      : [0.05, 0.04, 0.04, shadowAlpha.light];
    program.uniforms.uTint.value = themeName === 'dark' ? 0.92 : 1.0;
  }

  function emit() {
    const payload = { state, speed, dist, catX, mouseX };
    for (const cb of listeners) cb(payload);
  }

  function resize() {
    const w = container.clientWidth || 1;
    const h = container.clientHeight || 1;
    renderer.setSize(w, h);
    const aspect = w / h;
    camera.perspective({ aspect });
    const tan = Math.tan((30 * Math.PI) / 360);
    if (cam) {
      /* Explicit framing. `frameWidth` / `frameHeight` are the floor units
         that must stay visible, `floorAnchor` is where the floor line sits as
         a fraction of the canvas height measured from the bottom, and the two
         angles orbit the camera around the look point at that distance. */
      const frameW = cam.frameWidth || 2.2;
      const frameH = cam.frameHeight || 0.9;
      const anchor = cam.floorAnchor == null ? 0.10 : cam.floorAnchor;
      const az = (cam.azimuthDeg == null ? -28 : cam.azimuthDeg) * DEG;
      const el = (cam.elevationDeg == null ? 12 : cam.elevationDeg) * DEG;
      const lookX = cam.lookX || 0;
      const d = Math.max(frameH / (2 * tan), frameW / (2 * tan * aspect));
      const halfH = d * tan;
      const lookY = halfH * (1 - 2 * anchor);
      pxPerUnit = h / (2 * halfH);
      camera.position.set(
        lookX + Math.sin(az) * Math.cos(el) * d,
        lookY + Math.sin(el) * d,
        Math.cos(az) * Math.cos(el) * d
      );
      camera.lookAt([lookX, lookY, 0]);
    } else {
      // Keep the floor line framed; slight extra headroom for the pounce arc.
      const needH = 0.78;
      const needW = 1.05;
      const dist = Math.max(needH / tan, needW / (tan * aspect));
      pxPerUnit = h / (2 * dist * 0.70 * tan);
      camera.position.set(-1.15, 0.78, dist * 0.70);
      camera.lookAt([0.02, 0.30, 0]);
    }
    draw();
  }

  function draw() {
    if (destroyed) return;
    shadow.position.x = cat.root.position.x;
    const airborne = Math.max(0, cat.root.position.y - floorY);
    const s = clamp(1 - airborne * 1.6, 0.35, 1) * (0.85 + 0.15 * (cat.joints.hips.position.y / METRICS.hipStand));
    shadow.scale.set(s * (0.4 + 0.6 * catOpacity), 1, s);
    shadowProg.uniforms.uColor.value[3] =
      (themeName === 'dark' ? shadowAlpha.dark : shadowAlpha.light) * catOpacity;
    renderer.render({ scene, camera, sort: false, frustumCull: false });
  }

  function mapPointer(clientX, rect) {
    const u = (clientX - rect.left) / Math.max(rect.width, 1);
    return clamp((u - 0.5) * floorHalf * 2.05, -floorHalf + 0.08, floorHalf - 0.08);
  }

  function setPointer(x, inside) {
    if (inside) {
      if (Math.abs(x - lastPointerX) > 0.012) {
        pointerMovedAt = clock;
        stillS = 0;
        autoStill = false;
      }
      lastPointerX = x;
      pointerX = x;
      pointerIn = true;
    } else {
      pointerIn = false;
    }
  }

  function pickAutoTarget() {
    if (Math.random() < 0.35) {
      autoStill = true;
      autoTimer = 1.4 + Math.random() * 0.8;
      return;
    }
    autoStill = false;
    pointerX = (Math.random() * 2 - 1) * (floorHalf - 0.2);
    autoTimer = 1.6 + Math.random() * 2.4;
  }

  function goalX() {
    if (leaveX != null) return leaveX;
    if (hasTarget) return mouseX;
    return homeX;
  }

  function desiredYaw() {
    const dx = goalX() - catX;
    if (Math.abs(dx) < 0.04) return yawSpring.v;
    return dx >= 0 ? 0 : Math.PI;
  }

  function springYaw(want, dt) {
    const err = wrapAngle(yawSpring.v - want);
    const st = { v: err, dv: yawSpring.dv };
    spring1(st, 0, dt, 9);
    yawSpring.v = want + st.v;
    yawSpring.dv = st.dv;
    yaw = yawSpring.v;
    return Math.abs(wrapAngle(yaw - want));
  }

  function startFade(fromS, toS, fromO, toO, after) {
    fade = { t: 0, dur: 0.30, fromS, toS, fromO, toO, after: after || null };
  }

  function tickFade(dt) {
    if (!fade) return;
    fade.t += dt;
    const u = clamp(fade.t / fade.dur, 0, 1);
    const e = 1 - Math.pow(1 - u, 3);
    const s = lerp(fade.fromS, fade.toS, e);
    catOpacity = lerp(fade.fromO, fade.toO, e);
    cat.root.scale.set(s, s, s);
    if (u >= 1) {
      const cb = fade.after;
      fade = null;
      if (cb) cb();
    }
  }

  function enter(next) {
    if (state === next) return;
    state = next;
    if (next === 'idle' || next === 'enter') poseTarget = poseCopy(POSE_IDLE);
    else if (next === 'follow') poseTarget = poseCopy(POSE_STAND);
    else if (next === 'stalk') { poseTarget = poseCopy(POSE_STALK); stalkT = 0; }
    else if (next === 'pounce') {
      poseTarget = poseCopy(POSE_POUNCE);
      pounceT = 0;
      pounceFrom = catX;
      pounceTo = clamp(mouseX, -floorHalf + 0.15, floorHalf - 0.15);
    }
    else if (next === 'catch') {
      poseTarget = poseCopy(POSE_CATCH);
      catchT = 0;
      catchOrigin = mouseX;
      mouseCaught = true;
    }
    emit();
  }

  function tickMouse(dt) {
    if (frozenPose) {
      mouse.tail.rotation.y = 0.4 * Math.sin(clock * 6);
      return;
    }
    if (!hasTarget) {
      mouse.root.visible = false;
      return;
    }
    mouse.root.visible = true;
    if (mouseCaught) {
      mouseX = catX + Math.cos(yaw) * 0.16;
      mouseScale.v = spring1(mouseScale, 0.7, dt, 18);
      mouse.root.position.x = mouseX;
      mouse.root.position.y = floorY;
      mouse.root.scale.set(mouseScale.v, mouseScale.v, mouseScale.v);
      mouse.root.rotation.y = yaw;
      return;
    }
    mouseScale.v = spring1(mouseScale, 1, dt, 14);

    let goal = pointerX;
    if (!pointerIn && !autoplay && targetMode === 'pointer') {
      goal = pointerX >= 0 ? floorHalf - 0.06 : -floorHalf + 0.06;
    }
    if (autoplay && autoStill) {
      goal = mouseX;
    }

    const flee = (pointerIn || autoplay) && (clock - pointerMovedAt) < 0.25;
    const maxV = flee ? SPEED_MAX * speedScale * 1.15 : SPEED_MAX * speedScale * 1.05;
    const k = 1 - Math.exp(-dt / MOUSE_LAG);
    const want = mouseX + (goal - mouseX) * k;
    const dx = clamp(want - mouseX, -maxV * dt, maxV * dt);
    mouseX = clamp(mouseX + dx, -floorHalf + 0.05, floorHalf - 0.05);
    mouseVX = dt > 0 ? dx / dt : 0;

    mouse.root.position.x = mouseX;
    mouse.root.position.y = floorY;
    mouse.root.scale.set(mouseScale.v, mouseScale.v, mouseScale.v);
    const face = Math.abs(mouseVX) > 0.05 ? (mouseVX >= 0 ? 0 : Math.PI) : mouse.root.rotation.y;
    mouse.root.rotation.y += wrapAngle(face - mouse.root.rotation.y) * Math.min(1, dt * 8);
    mouse.tail.rotation.y = 0.55 * Math.sin(clock * 9);
    mouse.tail.rotation.z = 0.18 * Math.sin(clock * 7);
  }

  function tickFidget(dt) {
    fidgetIn -= dt;
    if (fidgetKind === 'none' && fidgetIn <= 0 && state === 'idle') {
      fidgetKind = 'look';
      fidgetT = 1.4;
      fidgetIn = 5 + Math.random() * 3;
    }
    if (fidgetKind === 'none') return;
    fidgetT -= dt;
    const u = Math.sin((1 - Math.max(fidgetT, 0) / 1.4) * Math.PI);
    cat.joints.neck.rotation.y += 0.4 * u * (Math.sin(clock) > 0 ? 1 : -1);
    cat.joints.head.rotation.y += 0.14 * u;
    if (fidgetT <= 0) fidgetKind = 'none';
  }

  function tickDemo(dt) {
    if (!autoplay || frozenPose) return;
    hasTarget = true;
    demoT += dt;
    const t = demoT % 11;
    const face = Math.cos(yaw) >= 0 ? 1 : -1;
    pointerIn = true;
    if (t < 1.0) {
      pointerX = catX + 0.14 * face;
      autoStill = true;
      pointerMovedAt = clock - 3;
    } else if (t < 3.2) {
      autoStill = false;
      pointerX = clamp(catX + 1.15 * face, -floorHalf + 0.12, floorHalf - 0.12);
      mouseX = pointerX;
      pointerMovedAt = clock;
      if (state === 'idle') enter('follow');
    } else if (t < 4.4) {
      const mid = catX + 0.7 * face;
      pointerX = mid;
      mouseX = mid;
      autoStill = true;
      pointerMovedAt = clock - 3;
      stillS = 2;
      if (state === 'follow' || state === 'idle') enter('stalk');
    } else if (t < 4.95) {
      if (state === 'stalk') enter('pounce');
    } else if (t < 6.1) {
      if (state === 'pounce') {
        cat.root.position.y = floorY;
        catX = pounceTo || catX;
        enter('catch');
      }
    } else if (state === 'catch') {
      mouseCaught = false;
      mouseX = catX + 0.14 * face;
      pointerX = mouseX;
      enter('idle');
    }
  }

  function tickBrain(dt) {
    const gx = goalX();
    dist = Math.abs(gx - catX);
    const mouseStill = hasTarget && ((clock - pointerMovedAt) >= stillNeeded || (autoplay && autoStill));
    stillS = mouseStill ? stillS + dt : 0;

    if (state === 'enter') {
      speed = 0;
    } else if (state === 'idle') {
      speed = 0;
      if (leaveX != null && dist > settled) enter('follow');
      else if (hasTarget && dist > arrive) enter('follow');
      else if (!hasTarget && leaveX == null && dist > settled) enter('follow');
      else if (hasTarget && dist >= stalkNear && dist <= stalkFar && stillS >= stillNeeded) enter('stalk');
    } else if (state === 'follow') {
      const want = desiredYaw();
      const yawErr = springYaw(want, dt);
      const turning = yawErr > 18 * DEG;
      const t = clamp((dist - arrive) / (1.1 * world), 0, 1);
      const baseSpeed = lerp(SPEED_MIN, SPEED_MAX, t) * speedScale;
      speed = turning ? baseSpeed * 0.4 : baseSpeed;
      let hz = lerp(HZ_MIN, HZ_MAX, clamp((speed - SPEED_MIN) / (SPEED_MAX - SPEED_MIN + 1e-6), 0, 1));
      if (turning) hz *= 0.5;
      const dir = Math.cos(yaw) >= 0 ? 1 : -1;
      catX = clamp(catX + dir * speed * dt, -floorHalf + 0.2, floorHalf - 0.2);
      walkPhase += hz * Math.PI * 2 * dt;
      const arrived = dist <= (leaveX != null || !hasTarget ? settled : arrive);
      if (arrived && (!hasTarget || leaveX != null)) {
        enter('idle');
        if (leaveX != null) {
          startFade(cat.root.scale.x, 0.6, catOpacity, 0, () => {
            const cb = leaveCb;
            leaveCb = null;
            leaveX = null;
            if (cb) cb();
          });
        }
      } else if (hasTarget && dist <= arrive && !mouseStill && !autoplay) enter('idle');
      else if (hasTarget && dist >= stalkNear && dist <= stalkFar && stillS >= stillNeeded) enter('stalk');
      else if (hasTarget && dist <= arrive && mouseStill && dist <= stalkFar) enter('stalk');
    } else if (state === 'stalk') {
      speed = 0;
      stalkT += dt;
      if (!mouseStill || dist > stalkFar) enter('follow');
      else if (stalkT >= 0.80) enter('pounce');
    } else if (state === 'pounce') {
      speed = 0;
      pounceT += dt;
      const u = clamp(pounceT / POUNCE_S, 0, 1);
      catX = lerp(pounceFrom, pounceTo, u);
      cat.root.position.y = floorY + 4 * 0.32 * u * (1 - u);
      springYaw(desiredYaw(), dt);
      if (u >= 1) {
        cat.root.position.y = floorY;
        enter('catch');
      }
    } else if (state === 'catch') {
      speed = 0;
      catchT += dt;
      cat.root.position.y = floorY;
      const moved = Math.abs(pointerX - catchOrigin);
      if (catchT < CATCH_S && moved > escapeMove && (pointerIn || autoplay) && (clock - pointerMovedAt) < 0.3) {
        mouseCaught = false;
        mouseX = clamp(catX + (Math.cos(yaw) >= 0 ? 0.55 : -0.55), -floorHalf + 0.1, floorHalf - 0.1);
        enter('follow');
      } else if (catchT >= CATCH_S) {
        mouseCaught = false;
        // Stay close so the cat sits (idle) instead of chasing immediately.
        const side = Math.cos(yaw) >= 0 ? 1 : -1;
        mouseX = clamp(catX + 0.16 * side, -floorHalf + 0.1, floorHalf - 0.1);
        pointerX = mouseX;
        enter('idle');
      }
    }

    cat.root.position.x = catX;
    if (state !== 'pounce') cat.root.position.y = floorY;
    cat.root.rotation.y = yaw;
  }

  function tickPose(dt) {
    if (frozenPose) {
      holdNamedPose(cat, frozenPose);
      overlayLife(cat, clock, (frozenPose === 'idle' || frozenPose === 'enter') ? 1 : 0.35, 1);
      if (frozenPose === 'stalk') overlayTailShake(cat, clock, 1);
      if (frozenPose === 'catch') {
        overlayProudTail(cat, (Math.sin(clock * 2) * 0.5 + 0.5));
        plantFeet(cat, { frontTarget: [mouse.root.position.x, METRICS.pawY + 0.025, mouse.root.position.z] });
      }
      cat.applyLimits();
      return;
    }

    poseLerp(blended, blended, poseTarget, 1 - Math.exp(-dt / 0.18));
    // -cos(yaw): the pose's yaws are mirrored when the cat walks the other
    // way, so the head keeps looking towards the camera rather than away.
    applyPose(cat, blended, -Math.cos(yaw));

    const tailGain = state === 'pounce' ? 0.12
      : state === 'stalk' ? 0.4
      : state === 'catch' ? 0.2
      : 1;
    overlayLife(cat, clock, tailGain, 1);
    if (state === 'idle' || state === 'enter') tickFidget(dt);
    if (state === 'stalk') {
      overlayHipTwist(cat, clamp(stalkT / 0.80, 0, 1));
      overlayTailShake(cat, clock, 1);
    }
    if (state === 'catch') overlayProudTail(cat, clamp(catchT / CATCH_S, 0, 1));

    const airborne = state === 'pounce';
    const facing = Math.cos(yaw) >= 0 ? 1 : -1;
    const gait = (state === 'follow' && speed > 0.05)
      ? gaitFromPhase(walkPhase, clamp(speed / SPEED_MAX, 0.45, 1), facing)
      : null;
    plantFeet(cat, {
      floorY,
      sit: state === 'idle' || state === 'enter',
      gait: gait || {},
      airborne,
      frontTarget: state === 'catch'
        ? [mouse.root.position.x, METRICS.pawY + 0.02, mouse.root.position.z]
        : null,
    });
    cat.applyLimits();
  }

  function frame(now) {
    raf = null;
    if (destroyed || paused || document.hidden || !visible) return;
    const t = now / 1000;
    const dt = lastT ? clamp(t - lastT, 0, 0.05) : 1 / 60;
    lastT = t;
    clock += dt;

    if (autoplay && !frozenPose) tickDemo(dt);

    tickFade(dt);
    tickMouse(dt);
    if (!frozenPose) tickBrain(dt);
    else {
      dist = Math.abs(mouse.root.position.x - cat.root.position.x);
      speed = frozenPose === 'walk' ? 1.1 : 0;
    }
    tickPose(dt);
    emit();
    draw();
    raf = requestAnimationFrame(frame);
  }

  function wake() {
    if (destroyed || paused || raf || document.hidden || !visible) return;
    lastT = 0;
    raf = requestAnimationFrame(frame);
  }

  const onPointerMove = (e) => {
    if (targetMode !== 'pointer') return;
    const r = container.getBoundingClientRect();
    const inside = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
    setPointer(mapPointer(e.clientX, r), inside);
  };
  const onPointerLeave = () => { pointerIn = false; };
  const onPointerDown = (e) => {
    const r = container.getBoundingClientRect();
    const x = mapPointer(e.clientX, r);
    setPointer(x, true);
    if (targetMode === 'tap') {
      pointerX = x;
      pointerMovedAt = clock;
      stillS = 0;
      autoStill = false;
    }
  };
  const onVisibility = () => { if (!document.hidden) wake(); };

  const io = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (!visible) {
      if (raf) cancelAnimationFrame(raf);
      raf = null;
      return;
    }
    wake();
  }, { threshold: 0.05 });

  const ro = new ResizeObserver(() => resize());

  container.appendChild(canvas);
  resize();
  /* A stage that starts hidden shows nothing at all until enterFrom() runs:
     the cat is already scaled and faded out, and the mouse is off. Paired
     with startPaused this costs one frame and then no rAF at all. */
  if (options.startHidden === true && !frozenPose) {
    catOpacity = 0;
    cat.root.scale.set(0.6, 0.6, 0.6);
    mouse.root.visible = false;
    hasTarget = false;
  }
  ro.observe(container);
  io.observe(container);
  if (targetMode !== 'external') {
    addEventListener('pointermove', onPointerMove, { passive: true });
    container.addEventListener('pointerdown', onPointerDown);
    container.addEventListener('pointerleave', onPointerLeave);
  }
  document.addEventListener('visibilitychange', onVisibility);
  draw();
  wake();

  const ready = Promise.resolve(true);

  function destroy() {
    if (destroyed) return;
    destroyed = true;
    if (raf) cancelAnimationFrame(raf);
    raf = null;
    io.disconnect();
    ro.disconnect();
    if (targetMode !== 'external') {
      removeEventListener('pointermove', onPointerMove);
      container.removeEventListener('pointerdown', onPointerDown);
      container.removeEventListener('pointerleave', onPointerLeave);
    }
    document.removeEventListener('visibilitychange', onVisibility);
    canvas.remove();
    const lose = gl.getExtension('WEBGL_lose_context');
    if (lose) lose.loseContext();
  }

  return {
    ready,
    canvas,
    /** Rendered CSS px per floor unit at the current size (0 before layout). */
    get pxPerUnit() { return pxPerUnit; },
    /** Stop the rAF loop. preserveDrawingBuffer keeps the last frame on screen. */
    pause() {
      paused = true;
      if (raf) cancelAnimationFrame(raf);
      raf = null;
    },
    resume() {
      if (!paused) return;
      paused = false;
      wake();
    },
    setTheme(name) { applyTheme(name); draw(); },
    setTargetMode(mode) {
      targetMode = mode === 'tap' ? 'tap' : mode === 'external' ? 'external' : 'pointer';
    },
    setTarget(x) {
      if (x == null || x === false) {
        hasTarget = false;
        mouse.root.visible = false;
        leaveX = null;
        if (Math.abs(catX - homeX) > settled) enter('follow');
        else enter('idle');
        return;
      }
      hasTarget = true;
      mouse.root.visible = true;
      mouseX = clamp(+x, -floorHalf + 0.05, floorHalf - 0.05);
      pointerX = mouseX;
      pointerMovedAt = clock;
      stillS = 0;
      autoStill = false;
    },
    enterFrom(x) {
      leaveCb = null;
      leaveX = null;
      fade = null;
      catX = clamp(+x, -floorHalf + 0.2, floorHalf - 0.2);
      cat.root.position.x = catX;
      cat.root.position.y = floorY;
      cat.root.scale.set(0.6, 0.6, 0.6);
      catOpacity = 0;
      poseTarget = poseCopy(POSE_IDLE);
      Object.assign(blended, poseCopy(POSE_IDLE));
      applyPose(cat, POSE_IDLE);
      plantFeet(cat, { sit: true, floorY });
      enter('enter');
      startFade(0.6, 1, 0, 1, () => { if (state === 'enter') enter('idle'); });
      draw();
    },
    leaveTo(x, cb) {
      leaveX = clamp(+x, -floorHalf + 0.2, floorHalf - 0.2);
      leaveCb = typeof cb === 'function' ? cb : null;
      hasTarget = false;
      mouse.root.visible = false;
      if (Math.abs(catX - leaveX) <= settled) {
        enter('idle');
        startFade(cat.root.scale.x || 1, 0.6, catOpacity, 0, () => {
          const fn = leaveCb;
          leaveCb = null;
          leaveX = null;
          if (fn) fn();
        });
      } else {
        enter('follow');
      }
    },
    reset() {
      state = 'idle';
      poseTarget = poseCopy(POSE_IDLE);
      Object.assign(blended, poseCopy(POSE_IDLE));
      catX = homeX;
      mouseX = 0.55;
      pointerX = 0.55;
      speed = 0;
      mouseCaught = false;
      mouseScale.v = 1;
      hasTarget = targetMode !== 'external';
      leaveX = null;
      leaveCb = null;
      fade = null;
      catOpacity = 1;
      cat.root.scale.set(1, 1, 1);
      cat.root.position.set(catX, floorY, 0);
      yaw = Math.PI;
      yawSpring.v = yaw;
      yawSpring.dv = 0;
      cat.root.rotation.y = yaw;
      applyPose(cat, POSE_IDLE);
      plantFeet(cat, { sit: true, floorY });
      cat.applyLimits();
      emit();
      draw();
    },
    destroy,
    onState(cb) {
      listeners.push(cb);
      cb({ state, speed, dist, catX, mouseX });
      return () => {
        const i = listeners.indexOf(cb);
        if (i >= 0) listeners.splice(i, 1);
      };
    },
  };
  }
}
