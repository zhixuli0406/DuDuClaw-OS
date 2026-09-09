/* DuDuClaw OS hero background shader: two soft blobs drifting on a
   value-noise field, in a full-bleed WebGL2 quad.

   An enhancement, never the background itself. The two CSS circles in
   .hero-bg stay in the markup and are what no-JS, no-WebGL2 and
   reduced-motion visitors see; this canvas fades in over them only after it
   compiles and links, and every failure path (context loss included) removes
   it and hands the circles back. Colours come from the same custom
   properties the circles use, so the palette has one source of truth and
   follows the theme toggle. Test switch: ?nogl=1 stays on CSS. */
(function () {
  'use strict';

  var hero = document.querySelector('.hero');
  var bg = hero && hero.querySelector('.hero-bg');
  if (!bg) return;

  function flag(name) {
    try { return new URLSearchParams(window.location.search).get(name) === '1'; }
    catch (err) { return false; }
  }
  function mq(q) { return window.matchMedia ? window.matchMedia(q) : { matches: false }; }

  if (flag('nogl') || mq('(prefers-reduced-motion: reduce)').matches) return;

  var VARS = ['--hero-circle-a', '--hero-circle-b', '--hero-ground', '--hero-glow'];
  var GREY = [0.93, 0.94, 0.96];

  /* #rgb and #rrggbb only: every hero token in site.css is written that way. */
  function readColors() {
    var cs = window.getComputedStyle(hero);
    return VARS.map(function (name) {
      var hex = cs.getPropertyValue(name).trim();
      if (hex.length === 4) hex = '#' + hex[1] + hex[1] + hex[2] + hex[2] + hex[3] + hex[3];
      var n = hex.charAt(0) === '#' && hex.length === 7 ? parseInt(hex.slice(1), 16) : NaN;
      if (isNaN(n)) return GREY;
      return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
    });
  }

  var VERT = '#version 300 es\nin vec2 aPos;\nvoid main(){gl_Position=vec4(aPos,0.,1.);}';

  /* Two octaves of value noise warp the whole plane (0.13 + 0.05 = 0.18 UV at
     full amplitude, up from 0.11), and all three blob centres ride their own
     slow circular orbit — 11s, 8.5s and 13s, deliberately coprime enough that
     the field never visibly repeats. The pointer term is already eased in JS,
     so uPtr is a settled position, not a raw cursor: it moves the centres by
     up to 6% of the hero width. Scroll slides them at 0.25 parallax. uAmp is
     0.5 on coarse pointers, which halves warp and orbit in one place.

     The final dither is not decoration: these tokens are two steps apart and
     an 8-bit ramp across 1000px bands hard without it. */
  var FRAG = `#version 300 es
precision highp float;
uniform vec2 uRes;uniform float uTime;uniform vec2 uPtr;uniform float uScroll;
uniform vec3 uA;uniform vec3 uB;uniform vec3 uG;uniform vec3 uH;uniform float uAmp;
out vec4 oCol;
const float TAU=6.2831853;
float hash(vec2 p){return fract(sin(dot(p,vec2(41.31,289.07)))*43758.5453);}
float vnoise(vec2 p){
  vec2 i=floor(p),f=fract(p),u=f*f*(3.-2.*f);
  return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),
             mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x),u.y);
}
vec2 orbit(float period,float phase,float r){
  float a=uTime*TAU/period+phase;
  return vec2(cos(a),sin(a))*r*uAmp;
}
void main(){
  vec2 uv=gl_FragCoord.xy/uRes;
  float aspect=uRes.x/max(uRes.y,1.);
  vec2 p=vec2(uv.x*aspect,uv.y);
  vec2 w1=vec2(vnoise(p*1.05+vec2(uTime*.110,0.)),
               vnoise(p*1.05+vec2(7.31,uTime*.090)))-.5;
  vec2 w2=vec2(vnoise(p*2.30+vec2(0.,uTime*.150)),
               vnoise(p*2.30+vec2(3.17,uTime*.125)))-.5;
  p+=(w1*.13+w2*.05)*uAmp;
  vec2 ca=vec2(aspect*.88,.99-uScroll*.25)+orbit(11.0,0.0,.160)+uPtr*.060;
  vec2 cb=vec2(aspect*.05,.31-uScroll*.14)+orbit(8.5,2.1,.140)+uPtr*.045;
  vec2 cg=vec2(aspect*.62,.78-uScroll*.19)+orbit(13.0,4.0,.180)+uPtr*.030;
  float a=smoothstep(1.30,.58,length((p-ca)*vec2(.86,1.)));
  float b=smoothstep(1.14,.50,length((p-cb)*vec2(.92,1.)));
  float g=smoothstep(.66,.10,length((p-cg)*vec2(.80,1.)));
  vec3 col=mix(mix(uG,uA,a),uB,b*.88);
  col=mix(col,uH,g*.80);
  oCol=vec4(col+(hash(gl_FragCoord.xy)-.5)/255.,1.);
}`;

  function compile(gl, type, source) {
    var sh = gl.createShader(type);
    gl.shaderSource(sh, source);
    gl.compileShader(sh);
    if (gl.getShaderParameter(sh, gl.COMPILE_STATUS)) return sh;
    gl.deleteShader(sh);
    return null;
  }

  function start() {
    var canvas = document.createElement('canvas');
    canvas.className = 'hero-gl';
    canvas.setAttribute('aria-hidden', 'true');

    var gl = null;
    try {
      gl = canvas.getContext('webgl2', {
        alpha: false, antialias: false, depth: false, stencil: false,
        preserveDrawingBuffer: false, powerPreference: 'low-power'
      });
    } catch (err) { gl = null; }
    if (!gl) return;

    var vs = compile(gl, gl.VERTEX_SHADER, VERT);
    var fs = vs && compile(gl, gl.FRAGMENT_SHADER, FRAG);
    if (!fs) return;

    var prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.bindAttribLocation(prog, 0, 'aPos');
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return;
    gl.useProgram(prog);

    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    var u = {};
    ['uRes', 'uTime', 'uPtr', 'uScroll', 'uA', 'uB', 'uG', 'uH', 'uAmp'].forEach(function (n) {
      u[n] = gl.getUniformLocation(prog, n);
    });

    var colors = readColors();
    var dead = false, raf = null, visible = true;
    var ptrX = 0, ptrY = 0, tgtX = 0, tgtY = 0, scroll = 0, t0 = 0, last = 0;
    var coarse = mq('(pointer: coarse)').matches;
    var minFrame = coarse ? 1000 / 30 : 0;
    var amp = coarse ? 0.5 : 1.0;   /* halved warp and orbit on touch */
    var PTR_EASE = 2.6;             /* rad/s toward the pointer target */

    function resize() {
      var dpr = Math.min(window.devicePixelRatio || 1, 2);
      var w = Math.max(1, Math.round(bg.clientWidth * dpr));
      var h = Math.max(1, Math.round(bg.clientHeight * dpr));
      if (canvas.width === w && canvas.height === h) return;
      canvas.width = w;
      canvas.height = h;
      gl.viewport(0, 0, w, h);
    }

    function draw(sec) {
      gl.uniform2f(u.uRes, canvas.width, canvas.height);
      gl.uniform1f(u.uTime, sec);
      gl.uniform2f(u.uPtr, ptrX, ptrY);
      gl.uniform1f(u.uScroll, scroll);
      gl.uniform3f(u.uA, colors[0][0], colors[0][1], colors[0][2]);
      gl.uniform3f(u.uB, colors[1][0], colors[1][1], colors[1][2]);
      gl.uniform3f(u.uG, colors[2][0], colors[2][1], colors[2][2]);
      gl.uniform3f(u.uH, colors[3][0], colors[3][1], colors[3][2]);
      gl.uniform1f(u.uAmp, amp);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    function frame(now) {
      raf = null;
      if (dead || document.hidden || !visible) return;
      if (minFrame && now - last < minFrame) { raf = requestAnimationFrame(frame); return; }
      /* Exponential ease toward the pointer target, so the blobs follow the
         cursor with weight and drift back when it leaves the hero. */
      var dt = last ? Math.min((now - last) / 1000, 1 / 15) : 1 / 60;
      var k = 1 - Math.exp(-PTR_EASE * dt);
      ptrX += (tgtX - ptrX) * k;
      ptrY += (tgtY - ptrY) * k;
      last = now;
      if (!t0) t0 = now;
      draw((now - t0) / 1000);
      raf = requestAnimationFrame(frame);
    }
    function wake() {
      if (!dead && raf === null && visible && !document.hidden) raf = requestAnimationFrame(frame);
    }
    function sleep() {
      if (raf !== null) { cancelAnimationFrame(raf); raf = null; }
    }
    function teardown() {
      if (dead) return;
      dead = true;
      sleep();
      bg.removeAttribute('data-gl');
      if (canvas.parentNode) canvas.parentNode.removeChild(canvas);
    }

    canvas.addEventListener('webglcontextlost', function (evt) {
      evt.preventDefault();
      teardown();
    });

    if ('IntersectionObserver' in window) {
      visible = false;
      new IntersectionObserver(function (e) {
        visible = e[0].isIntersecting;
        if (visible) wake(); else sleep();
      }, { threshold: 0 }).observe(hero);
    }

    document.addEventListener('visibilitychange', function () {
      if (document.hidden) sleep(); else wake();
    });

    function onResize() { resize(); wake(); }
    if ('ResizeObserver' in window) new ResizeObserver(onResize).observe(bg);
    else window.addEventListener('resize', onResize, { passive: true });

    window.addEventListener('scroll', function () {
      scroll = Math.max(0, Math.min(1.4, window.scrollY / (hero.offsetHeight || 1)));
    }, { passive: true });

    if (mq('(hover: hover) and (pointer: fine)').matches) {
      hero.addEventListener('pointermove', function (evt) {
        var r = hero.getBoundingClientRect();
        tgtX = (evt.clientX - r.left) / (r.width || 1) * 2 - 1;
        tgtY = 1 - (evt.clientY - r.top) / (r.height || 1) * 2;
      }, { passive: true });
      /* Target only: the eased position in frame() drifts back on its own. */
      hero.addEventListener('pointerleave', function () { tgtX = 0; tgtY = 0; });
    }

    /* Both theme routes: the toggle stamps data-theme on <html>, the system
       setting only changes what the media query resolves to. */
    function refresh() { colors = readColors(); wake(); }
    if ('MutationObserver' in window) {
      new MutationObserver(refresh).observe(document.documentElement, {
        attributes: true, attributeFilter: ['data-theme']
      });
    }
    var dark = mq('(prefers-color-scheme: dark)');
    if (dark.addEventListener) dark.addEventListener('change', refresh);
    else if (dark.addListener) dark.addListener(refresh);

    resize();
    draw(0);
    bg.appendChild(canvas);
    bg.setAttribute('data-gl', 'on');
    wake();
  }

  /* Never in the way of the hero text: the LCP candidate paints first. */
  function boot() {
    if (window.requestIdleCallback) requestIdleCallback(start, { timeout: 1200 });
    else window.setTimeout(start, 240);
  }
  if (document.readyState === 'complete') boot();
  else window.addEventListener('load', boot, { once: true });
}());
