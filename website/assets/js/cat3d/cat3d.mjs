/* DuDuClaw origami cat — low-poly 3D mascot.
 *
 * mountCat3D(container, options) mounts a transparent WebGL canvas that plays a
 * one-time paper-unfold, then leans a few degrees toward the pointer. It returns
 * `false` — leaving the container untouched — whenever it must not run, so the
 * caller can simply keep the inline SVG. See README.md next to this file.
 *
 * Geometry comes from assets/data/cat-panels.json, generated offline by
 * tools/build-panels.py out of assets/brand/duduclaw-cat.svg. Nothing here
 * parses SVG or triangulates at runtime.
 */

import { Renderer, Camera, Transform, Geometry, Program, Mesh } from '../../vendor/ogl.mjs';

const DATA_URL = new URL('../../data/cat-panels.json', import.meta.url);

const UNFOLD_MS = 820;      // whole reveal, first panel to last
const PANEL_SPAN = 0.44;    // slice of the timeline one panel occupies
const SPRING = 11.0;        // rad/s, tilt spring
const DAMP = 0.72;          // damping ratio — under 1, so the lean overshoots
                            // once and settles rather than creeping in
const AMBIENT = 0.66;       // flat term — keeps the SVG crimsons recognisable
const KEY = 0.52;           // directional term — this is what makes folds read
const LIGHT = [-0.42, 0.58, 0.70];

/* Idle: the mascot is never a still picture while it is on screen. One 6s
   cycle carries all three: breathe (scale), float (CSS px, converted through
   pxPerUnit) and a slow yaw sway. Amplitudes are deliberately small enough
   that they read as life, not as a loop. */
const IDLE_PERIOD_S = 6.0;
const IDLE_BREATHE = 0.015;                 // +/- 1.5% scale
const IDLE_FLOAT_PX = 6;                    // +/- 6 CSS px
const IDLE_SWAY_RAD = (1.5 * Math.PI) / 180; // +/- 1.5 degrees of yaw

const vertex = /* glsl */ `
precision highp float;
attribute vec3 position;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat3 normalMatrix;
uniform vec4 uHinge;   // xy: a point on the hinge, zw: unit direction along it
uniform float uAngle;  // radians, signed
varying vec2 vLocal;
varying vec3 vNormal;
void main() {
  vLocal = position.xy;                       // flat coords -> gradient lookup
  float c = cos(uAngle), s = sin(uAngle);
  vec3 k = vec3(uHinge.zw, 0.0);
  vec3 v = vec3(position.xy - uHinge.xy, 0.0);
  vec3 r = v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);  // Rodrigues
  vec3 p = vec3(uHinge.xy + r.xy, position.z + r.z);
  vNormal = normalMatrix * vec3(uHinge.w * s, -uHinge.z * s, c);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
}`;

const fragment = /* glsl */ `
precision highp float;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec4 uGrad;    // xy: gradient start, zw: gradient vector
uniform vec3 uLight;
varying vec2 vLocal;
varying vec3 vNormal;
void main() {
  vec2 d = uGrad.zw;
  float t = clamp(dot(vLocal - uGrad.xy, d) / max(dot(d, d), 1e-6), 0.0, 1.0);
  vec3 base = mix(uC0, uC1, t);
  vec3 n = normalize(vNormal);
  if (!gl_FrontFacing) n = -n;
  float lambert = ${AMBIENT.toFixed(2)} + ${KEY.toFixed(2)} * max(dot(n, uLight), 0.0);
  gl_FragColor = vec4(base * lambert, 1.0);
}`;

const flag = (name) => {
  try {
    return new URLSearchParams(location.search).get(name) === '1';
  } catch { return false; }
};

const hexToRgb = (h) => {
  const v = parseInt(h.slice(1), 16);
  return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
};

const easeOut = (t) => 1 - Math.pow(1 - t, 3);

/** WebGL support probe. Rejects software/blacklisted drivers too (research D.3). */
function hasWebGL() {
  if (flag('nowebgl')) return false;
  try {
    const c = document.createElement('canvas');
    const opts = { failIfMajorPerformanceCaveat: true };
    return !!(c.getContext('webgl2', opts) || c.getContext('webgl', opts));
  } catch { return false; }
}

/**
 * @param {HTMLElement} container
 * @param {{scale?:number, tiltDegrees?:number, autoplay?:boolean, src?:string}} options
 * @returns {false|{ready:Promise<boolean>, play:()=>void, destroy:()=>void, canvas:HTMLCanvasElement}}
 */
export function mountCat3D(container, options = {}) {
  const { scale = 1, tiltDegrees = 10, autoplay = true, src = DATA_URL } = options;

  const reduced = flag('reducedmotion') ||
    (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  if (!container || reduced || !hasWebGL()) return false;

  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  Object.assign(canvas.style, {
    position: 'absolute', inset: '0', width: '100%', height: '100%',
    display: 'block', pointerEvents: 'none',
    filter: 'drop-shadow(0 2px 3px rgba(0,0,0,.18))',
  });
  if (getComputedStyle(container).position === 'static') container.style.position = 'relative';

  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  /* preserveDrawingBuffer so pause() can stop the loop and leave the last
     frame on screen — the hero cross-fades this canvas out while it is
     paused, and an implicitly cleared buffer would blank mid-fade. */
  const renderer = new Renderer({
    canvas, alpha: true, antialias: true, dpr,
    preserveDrawingBuffer: true, powerPreference: 'low-power',
  });
  const gl = renderer.gl;
  gl.clearColor(0, 0, 0, 0);

  /* 35deg, not 24: a longer lens flattened the folds into the SVG it is
     standing in for. The wider angle is what makes the panels read as
     separate planes at this size. */
  const camera = new Camera(gl, { fov: 35, near: 1, far: 4000 });
  const scene = new Transform();
  const program = new Program(gl, {
    vertex, fragment, cullFace: false,
    uniforms: {
      uHinge: { value: new Float32Array([0, 0, 1, 0]) },
      uAngle: { value: 0 },
      uGrad: { value: new Float32Array([0, 0, 1, 0]) },
      uC0: { value: new Float32Array(3) },
      uC1: { value: new Float32Array(3) },
      uLight: { value: new Float32Array(LIGHT) },
    },
  });

  let panels = [];
  let size = [109, 242];
  let pxPerUnit = 0;      // rendered CSS px per SVG unit — lets a caller line
                          // the original SVG up underneath the canvas
  let raf = null, visible = false, destroyed = false, paused = false;
  let unfoldStart = -1, unfolding = false, played = false;
  const tilt = { x: 0, y: 0, vx: 0, vy: 0, tx: 0, ty: 0 };
  const canTilt = window.matchMedia
    ? matchMedia('(hover: hover) and (pointer: fine)').matches : false;
  const coarse = window.matchMedia ? matchMedia('(pointer: coarse)').matches : false;
  const minFrame = coarse ? 1000 / 30 : 0;   // mobile/battery cap (research D.3 item 5)
  let lastFrame = 0;

  function resize() {
    const w = container.clientWidth || 1;
    const h = container.clientHeight || 1;
    renderer.setSize(w, h);
    camera.perspective({ aspect: w / h });
    // Frame the cat's bbox with a small margin, honouring `scale`.
    const tan = Math.tan((camera.fov * Math.PI) / 360);
    const need = 1.06 / Math.max(scale, 0.05);
    camera.position.z = Math.max(
      (size[1] * need) / (2 * tan),
      (size[0] * need) / (2 * tan * (w / h))
    );
    camera.near = camera.position.z * 0.1;
    camera.far = camera.position.z * 3;
    camera.perspective({ aspect: w / h });
    pxPerUnit = h / (2 * camera.position.z * tan);
    draw();   // paint synchronously: a backgrounded tab gets no rAF at all
    wake();
  }

  // One shared program for all eight panels; each mesh pushes its own uniforms
  // in onBeforeRender (Mesh.draw runs the callbacks before program.use()).
  function bindPanel(p) {
    const u = program.uniforms;
    u.uHinge.value = p.hinge;
    u.uAngle.value = p.angle;
    u.uGrad.value = p.grad;
    u.uC0.value = p.c0;
    u.uC1.value = p.c1;
  }

  function draw() {
    if (destroyed || !panels.length) return;
    renderer.render({ scene, camera, sort: false, frustumCull: false });
  }

  function frame(now) {
    raf = null;
    if (destroyed || paused || document.hidden || !visible) return;
    if (minFrame && now - lastFrame < minFrame) { raf = requestAnimationFrame(frame); return; }
    const dt = Math.min((now - (lastFrame || now)) / 1000, 1 / 30);
    lastFrame = now;

    if (unfolding) {
      const tn = Math.min((now - unfoldStart) / UNFOLD_MS, 1);
      for (const p of panels) {
        const local = (tn - p.delay) / PANEL_SPAN;
        const e = easeOut(Math.min(Math.max(local, 0), 1));
        p.angle = p.foldRad * (1 - e);
      }
      if (tn >= 1) { unfolding = false; for (const p of panels) p.angle = 0; }
    }

    if (canTilt) {
      // x'' = -2*zeta*w x' - w^2 (x - target); zeta < 1 leaves one overshoot
      for (const a of ['x', 'y']) {
        const v = 'v' + a, t = 't' + a;
        tilt[v] += (-2 * DAMP * SPRING * tilt[v] - SPRING * SPRING * (tilt[a] - tilt[t])) * dt;
        tilt[a] += tilt[v] * dt;
      }
    }

    // Idle. One phase drives all three channels; the sway is a quarter-cycle
    // behind the breath so the two never peak together and read as one pump.
    const phase = (now / 1000) * ((2 * Math.PI) / IDLE_PERIOD_S);
    const breathe = 1 + IDLE_BREATHE * Math.sin(phase);
    scene.scale.set(breathe, breathe, breathe);
    scene.position.y = pxPerUnit > 0
      ? (IDLE_FLOAT_PX / pxPerUnit) * Math.sin(phase + Math.PI / 3)
      : 0;
    scene.rotation.x = tilt.x;
    scene.rotation.y = tilt.y + IDLE_SWAY_RAD * Math.sin(phase - Math.PI / 2);

    draw();
    // The idle never settles, so the loop only ever stops on hidden/offscreen
    // (the guards at the top of this function and in the observers below).
    raf = requestAnimationFrame(frame);
  }

  function wake() {
    if (destroyed || paused || raf || document.hidden || !visible) return;
    lastFrame = 0;
    raf = requestAnimationFrame(frame);
  }

  function play() {
    if (destroyed || !panels.length) return;
    // Panels rest flat until the reveal actually starts. A tab that is hidden,
    // or a browser that starves rAF, therefore shows the finished cat rather
    // than a frozen half-folded one — and the reveal still plays in full the
    // moment the tab becomes visible.
    for (const p of panels) p.angle = p.foldRad;
    unfoldStart = performance.now();
    unfolding = true;
    played = true;
    draw();
    wake();
  }

  const onPointer = (e) => {
    if (!canTilt) return;
    const r = container.getBoundingClientRect();
    // Reach is measured out from the mascot, not from the middle of the
    // viewport. Normalising by innerWidth/2 made the lean asymmetric wherever
    // the mascot is off-centre — parked in the right-hand hero column it had
    // less than half a viewport of screen to its right and could never reach
    // full tilt on that side. These radii saturate on both sides at any width.
    const reachX = Math.max(r.width, innerWidth * 0.24);
    const reachY = Math.max(r.height * 0.5, innerHeight * 0.24);
    const nx = (e.clientX - (r.left + r.width / 2)) / reachX;
    const ny = (e.clientY - (r.top + r.height / 2)) / reachY;
    const lim = (tiltDegrees * Math.PI) / 180;
    tilt.ty = Math.max(-1, Math.min(1, nx)) * lim;
    tilt.tx = Math.max(-1, Math.min(1, ny)) * lim;
    wake();
  };
  const onLeave = () => { tilt.tx = tilt.ty = 0; wake(); };
  const armed = () => autoplay && !played && visible && panels.length && !document.hidden;
  const onVisibility = () => { if (document.hidden) return; if (armed()) play(); else wake(); };

  const io = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (!visible) { if (raf) cancelAnimationFrame(raf); raf = null; return; }
    if (armed()) play(); else wake();
  }, { threshold: 0.2 });

  const ro = new ResizeObserver(() => resize());

  const ready = fetch(src)
    .then((r) => { if (!r.ok) throw new Error('cat-panels ' + r.status); return r.json(); })
    .then((doc) => {
      if (destroyed) return false;
      size = doc.meta.size;
      for (const p of doc.panels) {
        const n = p.vertices.length / 2;
        const pos = new Float32Array(n * 3);
        for (let i = 0; i < n; i++) {
          pos[i * 3] = p.vertices[i * 2];
          pos[i * 3 + 1] = p.vertices[i * 2 + 1];
        }
        const mesh = new Mesh(gl, {
          geometry: new Geometry(gl, { position: { size: 3, data: pos } }),
          program,
        });
        mesh.position.z = p.z;
        mesh.setParent(scene);
        const h = p.hinge || { a: [0, 0], b: [1, 0] };
        let rec;
        const dx = h.b[0] - h.a[0], dy = h.b[1] - h.a[1];
        const len = Math.hypot(dx, dy) || 1;
        const foldRad = ((p.fold.angle * p.fold.sign) * Math.PI) / 180;
        panels.push(rec = {
          mesh,
          hinge: new Float32Array([h.a[0], h.a[1], dx / len, dy / len]),
          grad: new Float32Array([
            p.gradient.p0[0], p.gradient.p0[1],
            p.gradient.p1[0] - p.gradient.p0[0], p.gradient.p1[1] - p.gradient.p0[1],
          ]),
          c0: new Float32Array(hexToRgb(p.gradient.c0)),
          c1: new Float32Array(hexToRgb(p.gradient.c1)),
          delay: p.fold.delay * (1 - PANEL_SPAN),
          foldRad,
          angle: 0,
        });
        mesh.onBeforeRender(() => bindPanel(rec));
      }
      container.appendChild(canvas);
      resize();
      ro.observe(container);
      io.observe(container);
      addEventListener('pointermove', onPointer, { passive: true });
      document.addEventListener('pointerleave', onLeave);
      document.addEventListener('visibilitychange', onVisibility);
      return true;
    })
    .catch((err) => {
      console.warn('[cat3d] geometry unavailable, keeping the SVG:', err.message);
      destroy();
      return false;
    });

  function destroy() {
    if (destroyed) return;
    destroyed = true;
    if (raf) cancelAnimationFrame(raf);
    raf = null;
    io.disconnect();
    ro.disconnect();
    removeEventListener('pointermove', onPointer);
    document.removeEventListener('pointerleave', onLeave);
    document.removeEventListener('visibilitychange', onVisibility);
    canvas.remove();
    panels = [];
    const lose = gl.getExtension('WEBGL_lose_context');
    if (lose) lose.loseContext();
  }

  return {
    ready, play, destroy, canvas,
    /** Stop the rAF loop and hold the last frame (preserveDrawingBuffer). */
    pause() {
      paused = true;
      if (raf) cancelAnimationFrame(raf);
      raf = null;
    },
    /** Restart the loop, painting one frame synchronously so a cross-fade
        never reveals a stale or empty canvas. */
    resume() {
      if (!paused) return;
      paused = false;
      draw();
      wake();
    },
    /** CSS px per SVG unit at the current size (0 before the first layout). */
    get pxPerUnit() { return pxPerUnit; },
  };
}

export default mountCat3D;
