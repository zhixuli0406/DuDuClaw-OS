/* Hero mascot orchestration: brand silhouette <-> walking cat.
 *
 * Two WebGL modules share the one mascot box. cat3d draws the brand
 * silhouette (the SVG in 3D, breathing and leaning). catwalk draws the
 * four-legged cat that chases a folded-paper mouse along a floor line.
 * Only one of them is ever animating: the other is paused with its last
 * frame still on screen, and the cross-fade runs over those frozen frames.
 *
 * At rest only the silhouette shows. A pointer entering the hero swaps in
 * the quadruped at the same spot on the same ground line; two seconds after
 * the pointer leaves, it walks home, sits and hands the box back.
 *
 * The inline SVG underneath is the no-JS / reduced-motion / no-WebGL
 * picture and is never removed. Query switches: ?nocat=1 mounts nothing,
 * ?nowalk=1 keeps the silhouette only.
 */

import { mountCat3D } from './cat3d/cat3d.mjs';
import { mountCatWalk } from './catwalk/catwalk.mjs';

var LEAVE_MS = 2000;        // pointer must stay outside the hero this long
var TAP_IDLE_MS = 20000;    // touch: this long without a tap goes back to the silhouette
var FLOOR_HALF = 0.72;      // walkable half-width in floor units, sized so no
                            // pose (tail behind, nose ahead) leaves the stage
var FRAME_W = 2.25;         // floor units kept visible across the stage
var FRAME_H = 0.95;         // floor units kept visible up the stage (pounce arc)
var FLOOR_ANCHOR = 0.045;   // floor line height as a fraction of the stage, from its foot

function flag(name) {
  try { return new URLSearchParams(location.search).get(name) === '1'; }
  catch (err) { return false; }
}

function currentTheme() {
  var set = document.documentElement.getAttribute('data-theme');
  if (set === 'light' || set === 'dark') return set;
  return window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches
    ? 'dark' : 'light';
}

var host = document.querySelector('.hero-cat');
var box = document.querySelector('.hero-cat-float');
var hero = document.querySelector('.hero');

if (host && box && hero && !flag('nocat')) boot();

function boot() {
  var cat = mountCat3D(box, { tiltDegrees: 10 });
  if (!cat) return;                 // reduced motion or no WebGL: the SVG stays

  cat.ready.then(function (ok) {
    if (!ok) return;                // geometry unavailable: the SVG stays
    cat.canvas.classList.add('hero-cat-3d');
    host.setAttribute('data-cat3d', 'on');

    if (flag('nowalk')) { wireReplay(cat); return; }

    /* The quadruped gets its own stage: it is longer than it is tall, so it
       needs more width than the silhouette, and it only ever uses the band
       of the box where the silhouette's feet already stand. */
    var stage = document.createElement('div');
    stage.className = 'hero-cat-stage';
    stage.setAttribute('aria-hidden', 'true');
    box.appendChild(stage);

    var walk = mountCatWalk(stage, {
      theme: currentTheme(),
      targetMode: 'external',
      transparent: true,
      startPaused: true,
      startHidden: true,
      floorHalf: FLOOR_HALF,
      speedScale: 0.6,
      stillSeconds: 0.6,
      homeX: 0,
      camera: {
        frameWidth: FRAME_W,
        frameHeight: FRAME_H,
        floorAnchor: FLOOR_ANCHOR,
        /* Near side-on. The diagonal gait is built to read from the side;
           swing further round and the legs cross into mush. */
        azimuthDeg: 0,
        elevationDeg: 12,
      },
    });

    if (!walk) { stage.remove(); wireReplay(cat); return; }
    walk.canvas.classList.add('hero-cat-walk');

    walk.ready.then(function (up) {
      if (!up) {                    // silently keep the silhouette mode
        walk.destroy();
        stage.remove();
        wireReplay(cat);
        return;
      }
      hybrid(cat, walk, stage);
    });
  });
}

/* The unfold is replayable only where the silhouette owns the box. In tap
   mode the stage is a "drop a paper mouse" control instead, and wiring both
   would put two overlapping controls on the same 44px of screen. */
var replayWired = false;
function wireReplay(cat) {
  if (replayWired) return;
  replayWired = true;
  box.setAttribute('role', 'button');
  box.setAttribute('tabindex', '0');
  box.setAttribute('aria-label', '重播摺紙展開');
  box.addEventListener('click', onReplayClick);
  box.addEventListener('keydown', onReplayKey);
  function onReplayClick() { cat.play(); }
  function onReplayKey(evt) {
    if (evt.key !== 'Enter' && evt.key !== ' ') return;
    evt.preventDefault();
    cat.play();
  }
  wireReplay.off = function () {
    replayWired = false;
    wireReplay.off = null;
    box.removeAttribute('role');
    box.removeAttribute('tabindex');
    box.removeAttribute('aria-label');
    box.removeEventListener('click', onReplayClick);
    box.removeEventListener('keydown', onReplayKey);
  };
}

function hybrid(cat, walk, stage) {
  var mode = 'silhouette';          // 'silhouette' | 'walk'
  var shown = false;                // the quadruped is on screen (fading counts)
  var catX = 0;                     // latest position, so an interrupted walk
                                    // home does not teleport on the way back
  var lastTarget = null;
  var leaveTimer = 0;
  var idleTimer = 0;
  var tapBtn = null;
  var tapQuery = matchMedia('(max-width: 780px), (pointer: coarse)');

  walk.onState(function (s) { catX = s.catX; });

  /* Where the silhouette stands, in floor units. The stage is wider than the
     mascot box and is not always centred on it, so the two "the cat is here"
     coordinates have to be reconciled or the swap would jump sideways. */
  function homeX() {
    var per = walk.pxPerUnit;
    if (!per) return 0;
    var s = stage.getBoundingClientRect();
    var b = box.getBoundingClientRect();
    var dx = (b.left + b.width / 2) - (s.left + s.width / 2);
    return clampFloor(dx / per);
  }

  function clampFloor(x) {
    var lim = FLOOR_HALF - 0.16;
    return Math.max(-lim, Math.min(lim, x));
  }

  /* The whole hero is the trackpad: the pointer's horizontal position across
     the section maps onto the floor line, clamped at both ends. */
  function targetFor(clientX) {
    var r = hero.getBoundingClientRect();
    var u = (clientX - r.left) / Math.max(r.width, 1);
    var lim = FLOOR_HALF - 0.06;
    return Math.max(-lim, Math.min(lim, (u - 0.5) * 2 * lim));
  }

  function toWalk() {
    clearTimeout(leaveTimer);
    leaveTimer = 0;
    if (mode === 'walk') return;
    mode = 'walk';
    lastTarget = null;
    cat.pause();                    // frozen frame, then the CSS fades it out
    walk.resume();
    // Interrupting a walk home resumes from where the cat actually is.
    walk.enterFrom(shown ? catX : homeX());
    shown = true;
    host.setAttribute('data-catwalk', 'on');
  }

  function toSilhouette() {
    if (mode !== 'walk') return;
    mode = 'silhouette';
    walk.setTarget(null);
    walk.leaveTo(homeX(), function () {
      if (mode !== 'silhouette') return;   // the pointer came back on the way home
      shown = false;
      walk.pause();                        // already fully faded out
      cat.resume();                        // paints one frame before it fades in
      host.removeAttribute('data-catwalk');
    });
  }

  function aim(x) {
    if (lastTarget !== null && Math.abs(x - lastTarget) < 0.005) return;
    lastTarget = x;
    walk.setTarget(x);
  }

  /* ---------- hover devices ---------- */

  function onEnter(evt) {
    if (evt.pointerType === 'touch') return;
    toWalk();
  }

  function onMove(evt) {
    if (evt.pointerType === 'touch') return;
    if (mode !== 'walk') toWalk();
    aim(targetFor(evt.clientX));
  }

  function onLeave(evt) {
    if (evt.pointerType === 'touch') return;
    clearTimeout(leaveTimer);
    leaveTimer = setTimeout(toSilhouette, LEAVE_MS);
  }

  /* ---------- touch and narrow viewports ---------- */

  function onTap(evt) {
    toWalk();
    var r = stage.getBoundingClientRect();
    var per = walk.pxPerUnit;
    var x = 0;
    if (per && evt.clientX) {
      x = (evt.clientX - (r.left + r.width / 2)) / per;
    }
    var lim = FLOOR_HALF - 0.06;
    aim(Math.max(-lim, Math.min(lim, x)));
    clearTimeout(idleTimer);
    idleTimer = setTimeout(toSilhouette, TAP_IDLE_MS);
  }

  function makeTap() {
    if (tapBtn) return;
    tapBtn = document.createElement('button');
    tapBtn.type = 'button';
    tapBtn.className = 'hero-cat-tap';
    tapBtn.setAttribute('aria-label', '放一隻紙老鼠');
    tapBtn.addEventListener('click', onTap);
    host.appendChild(tapBtn);
  }

  function dropTap() {
    if (!tapBtn) return;
    tapBtn.remove();
    tapBtn = null;
    clearTimeout(idleTimer);
    idleTimer = 0;
  }

  /* ---------- mode wiring ---------- */

  function applyInput() {
    hero.removeEventListener('pointerenter', onEnter);
    hero.removeEventListener('pointerleave', onLeave);
    hero.removeEventListener('pointermove', onMove);
    if (tapQuery.matches) {
      if (wireReplay.off) wireReplay.off();
      makeTap();
    } else {
      dropTap();
      wireReplay(cat);
      hero.addEventListener('pointerenter', onEnter);
      hero.addEventListener('pointerleave', onLeave);
      hero.addEventListener('pointermove', onMove, { passive: true });
    }
  }

  applyInput();
  if (tapQuery.addEventListener) {
    tapQuery.addEventListener('change', function () {
      toSilhouette();
      applyInput();
    });
  }

  /* Theme follows the site toggle, and the system preference while no
     explicit choice is stored. cat3d has no theme: it renders the brand
     gradients, which are the same in both. */
  function pushTheme() { walk.setTheme(currentTheme()); }
  new MutationObserver(pushTheme).observe(document.documentElement, {
    attributes: true, attributeFilter: ['data-theme'],
  });
  if (window.matchMedia) {
    var dark = matchMedia('(prefers-color-scheme: dark)');
    if (dark.addEventListener) dark.addEventListener('change', pushTheme);
  }
}
