/* DuDuClaw OS shadow workspace freeze demo.
   The agent's pointer becomes a six-particle trail touring the form wireframe
   on the shadow output, and freezes in place the moment your pointer enters
   your own screen. Handing control back is deliberately late (600 ms) so the
   gesture reads as a handover rather than a hover effect.

   The diagram is complete without this: the static .shadow-cursor-agent SVG
   stays in the markup and is hidden only once the canvas is running. No-JS,
   reduced-motion and every failure path keep it. Test switches: ?nodemo=1
   keeps the static cursor, ?nohover=1 forces the tap fallback. */
(function () {
  'use strict';

  var section = document.getElementById('shadow');
  if (!section) return;

  function flag(name) {
    try { return new URLSearchParams(window.location.search).get(name) === '1'; }
    catch (err) { return false; }
  }
  function mq(q) { return window.matchMedia ? window.matchMedia(q) : { matches: false }; }

  if (flag('nodemo') || mq('(prefers-reduced-motion: reduce)').matches) return;

  var youScreen = section.querySelector('[data-screen="you"]');
  var agentScreen = section.querySelector('[data-screen="agent"]');
  var stage = agentScreen && agentScreen.querySelector('.shadow-stage');
  var youStage = youScreen && youScreen.querySelector('.shadow-stage');
  var staticCursor = agentScreen && agentScreen.querySelector('.shadow-cursor-agent');
  var youCursor = youScreen && youScreen.querySelector('.shadow-cursor-you');
  if (!youStage || !stage) return;

  var TRAIL = 7;          /* plus the head: eight particles in total */
  var SEG_MS = 1500;      /* travel between two stops */
  var DWELL_MS = 520;     /* pause on a stop, so it reads as filling a field */
  var RELEASE_MS = 600;   /* the handover delay */
  var HEAD_R = 9.1;       /* head crosshair half-size, 1.4x the trail-era 6.5 */
  var WHIP_MS = 260;      /* clock jump on release, so the trail visibly whips
                             out of the frozen position instead of creeping */

  var canvas = document.createElement('canvas');
  canvas.className = 'shadow-agent-canvas';
  canvas.setAttribute('aria-hidden', 'true');
  var ctx = canvas.getContext && canvas.getContext('2d');
  if (!ctx) return;

  var tag = document.createElement('span');
  tag.className = 'shadow-freeze-tag';
  tag.setAttribute('aria-hidden', 'true');
  tag.textContent = '已凍結 · 3 至 4 ms';
  tag.hidden = true;

  var stops = [], trail = [], head = { x: 0, y: 0 };
  var amber = [138, 102, 0];
  var hintChip = null, hintSeen = false;
  var clock = 0;          /* only advances while the agent is running */
  var lastNow = 0, raf = null, releaseTimer = 0;
  var frozen = false, visible = true, width = 0, height = 0;
  var toggle = null;

  function readAmber() {
    var t = window.getComputedStyle(stage).getPropertyValue('--warning').trim();
    var n = t.charAt(0) === '#' && t.length === 7 ? parseInt(t.slice(1), 16) : NaN;
    if (!isNaN(n)) amber = [n >> 16 & 255, n >> 8 & 255, n & 255];
  }
  function rgba(a) { return 'rgba(' + amber[0] + ',' + amber[1] + ',' + amber[2] + ',' + a + ')'; }

  /* Stops are measured off the live wireframe, so the tour follows the layout
     at every width instead of a table of hard-coded percentages. */
  function measure() {
    var box = stage.getBoundingClientRect();
    width = box.width;
    height = box.height;
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.max(1, Math.round(width * dpr));
    canvas.height = Math.max(1, Math.round(height * dpr));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    var nodes = Array.prototype.slice.call(stage.querySelectorAll('.shadow-field'));
    var button = stage.querySelector('.shadow-button');
    if (button) nodes.push(button);
    stops = nodes.map(function (el, i) {
      var r = el.getBoundingClientRect();
      var along = i < nodes.length - 1 ? 0.34 : 0.5;
      return { x: r.left - box.left + r.width * along, y: r.top - box.top + r.height * 0.5 };
    });
  }

  function headAt(ms) {
    var n = stops.length;
    if (!n) return { x: width / 2, y: height / 2 };
    if (n === 1) return { x: stops[0].x, y: stops[0].y };
    var span = SEG_MS + DWELL_MS;
    var i = Math.floor(ms / span) % n;
    var local = ms % span;
    var a = stops[i];
    var b = stops[(i + 1) % n];
    if (local < DWELL_MS) return { x: a.x, y: a.y };
    var r = (local - DWELL_MS) / SEG_MS;
    var t = r < 0.5 ? 4 * r * r * r : 1 - Math.pow(2 - 2 * r, 3) / 2;
    /* Quadratic arc: the control point is pushed off the chord so the path
       curves the way a hand moves, alternating side per leg. */
    var bow = (i % 2 ? -1 : 1) * 0.22;
    var cx = (a.x + b.x) / 2 - (b.y - a.y) * bow;
    var cy = (a.y + b.y) / 2 + (b.x - a.x) * bow;
    var m = 1 - t;
    return {
      x: m * m * a.x + 2 * m * t * cx + t * t * b.x,
      y: m * m * a.y + 2 * m * t * cy + t * t * b.y
    };
  }

  function seed() {
    var p = headAt(0);
    head.x = p.x;
    head.y = p.y;
    trail.length = 0;
    for (var i = 0; i < TRAIL; i += 1) trail.push({ x: p.x, y: p.y });
  }

  function step(dt) {
    var p = headAt(clock);
    head.x = p.x;
    head.y = p.y;
    var prev = head;
    for (var i = 0; i < trail.length; i += 1) {
      var k = 1 - Math.exp(-(17 - i * 2.4) * dt);
      trail[i].x += (prev.x - trail[i].x) * k;
      trail[i].y += (prev.y - trail[i].y) * k;
      prev = trail[i];
    }
  }

  function paint() {
    ctx.clearRect(0, 0, width, height);
    /* The amber halo is what makes the trail readable across a light and a
       dark theme without changing its colour in either. */
    ctx.save();
    ctx.shadowColor = rgba('0.75');
    ctx.shadowBlur = 10;
    for (var i = trail.length - 1; i >= 0; i -= 1) {
      var f = 1 - i / trail.length;
      ctx.beginPath();
      ctx.arc(trail[i].x, trail[i].y, 2.0 + f * 3.4, 0, Math.PI * 2);
      ctx.fillStyle = rgba((0.12 + f * 0.36).toFixed(3));
      ctx.fill();
    }
    ctx.restore();
    /* Same shape vocabulary as the static cursor: a boxed crosshair. */
    var s = HEAD_R;
    ctx.save();
    ctx.shadowColor = rgba('0.85');
    ctx.shadowBlur = frozen ? 16 : 12;
    ctx.strokeStyle = rgba(frozen ? '1' : '0.92');
    ctx.lineWidth = 2.4;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(head.x - s, head.y - s, s * 2, s * 2, 3);
    else ctx.rect(head.x - s, head.y - s, s * 2, s * 2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(head.x, head.y - s * 0.52);
    ctx.lineTo(head.x, head.y + s * 0.52);
    ctx.moveTo(head.x - s * 0.52, head.y);
    ctx.lineTo(head.x + s * 0.52, head.y);
    ctx.stroke();
    ctx.restore();
  }

  function frame(now) {
    raf = null;
    if (document.hidden || !visible || frozen) return;
    var dt = lastNow ? Math.min((now - lastNow) / 1000, 1 / 20) : 1 / 60;
    lastNow = now;
    clock += dt * 1000;
    step(dt);
    paint();
    raf = requestAnimationFrame(frame);
  }
  function wake() {
    if (raf === null && !frozen && visible && !document.hidden) {
      lastNow = 0;
      raf = requestAnimationFrame(frame);
    }
  }
  function sleep() {
    if (raf !== null) { cancelAnimationFrame(raf); raf = null; }
  }

  function retireHint() {
    if (hintSeen || !hintChip) return;
    hintSeen = true;
    hintChip.setAttribute('data-seen', 'true');
  }

  function setFrozen(on) {
    if (frozen === on) return;
    frozen = on;
    agentScreen.setAttribute('data-frozen', on ? 'true' : 'false');
    tag.hidden = !on;
    if (toggle) toggle.setAttribute('aria-pressed', on ? 'true' : 'false');
    if (on) {
      retireHint();
      sleep();
      paint();                 /* held in place, not hidden or reset */
    } else {
      /* Handing the seat back: nudge the tour forward so the trail snaps out
         of the frozen point rather than easing away from it. */
      clock += WHIP_MS;
      wake();
    }
  }

  /* Your cursor follows the real mouse inside your frame. It is clamped to
     its own parent, not to the stage: the parent window clips its overflow,
     so a stage-wide clamp would let the pointer scroll it out of sight.
     Transform only; the rest position is recovered from the live rect minus
     the offset in force, so the hover lift and page scrolling cannot make it
     drift. */
  function trackYou(evt) {
    if (!youCursor) return;
    var r = (youCursor.parentNode || youStage).getBoundingClientRect();
    var c = youCursor.getBoundingClientRect();
    var ox = parseFloat(youCursor.style.getPropertyValue('--you-x')) || 0;
    var oy = parseFloat(youCursor.style.getPropertyValue('--you-y')) || 0;
    var w = c.width || 16;
    var x = Math.max(r.left + 2, Math.min(r.right - w - 2, evt.clientX - w * 0.25));
    var y = Math.max(r.top + 2, Math.min(r.bottom - w - 2, evt.clientY - w * 0.15));
    youCursor.style.setProperty('--you-x', (x - c.left + ox).toFixed(1) + 'px');
    youCursor.style.setProperty('--you-y', (y - c.top + oy).toFixed(1) + 'px');
  }
  function releaseYou() {
    if (!youCursor) return;
    youCursor.removeAttribute('data-tracking');
    youCursor.style.setProperty('--you-x', '0px');
    youCursor.style.setProperty('--you-y', '0px');
  }

  /* A standing invitation on your own frame. Without it the demo looks like a
     static diagram until somebody happens to sweep the pointer through it. It
     is aria-hidden because the interactive affordance it advertises is
     announced properly either by the frame's own role=button label (no-hover
     route) or by nothing at all (hover route, where there is no control to
     announce — moving a mouse is not an operable widget). */
  var isHover = !flag('nohover') && mq('(hover: hover) and (pointer: fine)').matches;
  hintChip = document.createElement('span');
  hintChip.className = 'shadow-hint-chip';
  hintChip.setAttribute('aria-hidden', 'true');
  var hintDot = document.createElement('i');
  hintDot.className = 'dot';
  hintChip.appendChild(hintDot);
  hintChip.appendChild(document.createTextNode(isHover ? '把滑鼠移進來試試' : '點一下試試'));
  youScreen.appendChild(hintChip);

  if (isHover) {
    youScreen.addEventListener('pointerenter', function () {
      window.clearTimeout(releaseTimer);
      if (youCursor) youCursor.setAttribute('data-tracking', 'true');
      setFrozen(true);
    });
    youScreen.addEventListener('pointermove', trackYou, { passive: true });
    youScreen.addEventListener('pointerleave', function () {
      releaseYou();
      window.clearTimeout(releaseTimer);
      releaseTimer = window.setTimeout(function () { setFrozen(false); }, RELEASE_MS);
    });
  } else {
    /* No hover to work with, so the frame becomes a switch instead. */
    toggle = youScreen;
    toggle.setAttribute('role', 'button');
    toggle.setAttribute('tabindex', '0');
    toggle.setAttribute('aria-pressed', 'false');
    toggle.setAttribute('aria-label', '點一下模擬你碰到鍵盤滑鼠，讓 agent 的 seat 凍結');
    toggle.setAttribute('data-freeze-toggle', '');
    /* The pulsing chip above already carries this instruction, and the frame's
       aria-label carries the full sentence, so the old static corner hint
       would be the same message a third time. */
    toggle.addEventListener('click', function () { setFrozen(!frozen); });
    toggle.addEventListener('keydown', function (evt) {
      if (evt.key !== 'Enter' && evt.key !== ' ') return;
      evt.preventDefault();
      setFrozen(!frozen);
    });
  }

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) sleep(); else wake();
  });

  if ('IntersectionObserver' in window) {
    visible = false;
    new IntersectionObserver(function (e) {
      visible = e[0].isIntersecting;
      if (visible) wake(); else sleep();
    }, { threshold: 0 }).observe(section.querySelector('.shadow-fig') || section);
  }

  function relayout() {
    measure();
    if (frozen) paint();
    wake();
  }
  if ('ResizeObserver' in window) new ResizeObserver(relayout).observe(stage);
  else window.addEventListener('resize', relayout, { passive: true });

  function repaintTheme() { readAmber(); if (frozen) paint(); }
  if ('MutationObserver' in window) {
    new MutationObserver(repaintTheme).observe(document.documentElement, {
      attributes: true, attributeFilter: ['data-theme']
    });
  }
  var dark = mq('(prefers-color-scheme: dark)');
  if (dark.addEventListener) dark.addEventListener('change', repaintTheme);
  else if (dark.addListener) dark.addListener(repaintTheme);

  stage.appendChild(canvas);
  stage.appendChild(tag);
  readAmber();
  measure();
  seed();
  paint();
  /* setAttribute, not .hidden: the cursor is an SVGSVGElement, which has no
     reflected hidden IDL attribute, and Chrome's UA [hidden] rule does not
     reach SVG either. site.css carries the matching .shadow-cursor[hidden]. */
  if (staticCursor) staticCursor.setAttribute('hidden', '');
  wake();
}());
