/* DuDuClaw OS website behaviour.
   No framework, no build step. Every piece degrades to plain HTML.

   ---------------------------------------------------------------
   RELEASE — single source of truth for release metadata in JS.
   When a new OS version ships, update this object AND the matching
   static text in index.html / download.html (see website/README.md).
   `id` values pair with the data-edition / data-form / data-machine
   attributes on the asset cards in download.html.
   --------------------------------------------------------------- */
var RELEASE = {
  version: 'v0.2.0',
  date: '2026-09-09',
  platform: '1.63.0',
  kernel: 'Linux 6.18',
  yocto: 'Yocto Project 6.0 "wrynose"',
  stage: 'pre-GA bring-up',
  previous: 'v0.1.0',
  repo: 'https://github.com/zhixuli0406/DuDuClaw-OS',
  downloadBase: 'https://github.com/zhixuli0406/DuDuClaw-OS/releases/download/v0.2.0/',
  minisignKey: 'RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n',
  assets: [
    {
      file: 'duduclaw-os-duduclaw-genericx86-64-v0.2.0.wic.zst',
      bytes: 1727284910, size: '1.61 GiB',
      edition: 'desktop', form: 'wic', machine: 'generic'
    },
    {
      file: 'duduclaw-os-duduclaw-qemux86-64-v0.2.0.wic.zst',
      bytes: 1723552090, size: '1.61 GiB',
      edition: 'desktop', form: 'wic', machine: 'qemu'
    },
    {
      file: 'duduclaw-os-installer-desktop-duduclaw-genericx86-64-v0.2.0.iso',
      bytes: 2005925888, size: '1.87 GiB',
      edition: 'desktop', form: 'iso', machine: 'generic'
    },
    {
      file: 'duduclaw-os-installer-desktop-duduclaw-qemux86-64-v0.2.0.iso',
      bytes: 1995728896, size: '1.86 GiB',
      edition: 'desktop', form: 'iso', machine: 'qemu'
    },
    {
      file: 'duduclaw-os-installer-duduclaw-genericx86-64-v0.2.0.iso',
      bytes: 601882624, size: '574 MiB',
      edition: 'base', form: 'iso', machine: 'generic'
    },
    {
      file: 'duduclaw-os-installer-duduclaw-qemux86-64-v0.2.0.iso',
      bytes: 590690304, size: '563 MiB',
      edition: 'base', form: 'iso', machine: 'qemu'
    }
  ]
};

(function () {
  'use strict';

  var root = document.documentElement;
  var THEME_KEY = 'duduclaw-os-theme';

  function each(list, fn) {
    Array.prototype.forEach.call(list, fn);
  }

  /* ---------- theme ---------- */

  function currentTheme() {
    var set = root.getAttribute('data-theme');
    if (set === 'light' || set === 'dark') return set;
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
      ? 'dark'
      : 'light';
  }

  function labelToggle(btn, theme) {
    var next = theme === 'dark' ? '淺色' : '深色';
    btn.setAttribute('aria-label', '切換到' + next + '主題');
    btn.setAttribute('title', '切換到' + next + '主題');
  }

  function initTheme() {
    var buttons = document.querySelectorAll('[data-theme-toggle]');
    if (!buttons.length) return;

    each(buttons, function (btn) { labelToggle(btn, currentTheme()); });

    each(buttons, function (btn) {
      btn.addEventListener('click', function () {
        var next = currentTheme() === 'dark' ? 'light' : 'dark';
        root.setAttribute('data-theme', next);
        try { localStorage.setItem(THEME_KEY, next); } catch (err) { /* storage blocked */ }
        each(buttons, function (b) { labelToggle(b, next); });
      });
    });
  }

  /* ---------- mobile nav ---------- */

  function initNav() {
    var toggle = document.querySelector('[data-nav-toggle]');
    var panel = document.getElementById('nav-panel');
    if (!toggle || !panel) return;

    function setOpen(open) {
      panel.setAttribute('data-open', open ? 'true' : 'false');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    }

    setOpen(false);

    toggle.addEventListener('click', function () {
      setOpen(panel.getAttribute('data-open') !== 'true');
    });

    each(panel.querySelectorAll('a'), function (link) {
      link.addEventListener('click', function () { setOpen(false); });
    });

    document.addEventListener('keydown', function (evt) {
      if (evt.key === 'Escape' && panel.getAttribute('data-open') === 'true') {
        setOpen(false);
        toggle.focus();
      }
    });
  }

  /* ---------- tabs ---------- */

  function initTabs() {
    each(document.querySelectorAll('[role="tablist"]'), function (list) {
      var tabs = Array.prototype.slice.call(list.querySelectorAll('[role="tab"]'));
      if (!tabs.length) return;

      function select(tab, focus) {
        tabs.forEach(function (t) {
          var on = t === tab;
          t.setAttribute('aria-selected', on ? 'true' : 'false');
          t.setAttribute('tabindex', on ? '0' : '-1');
          var panel = document.getElementById(t.getAttribute('aria-controls'));
          if (panel) panel.hidden = !on;
        });
        if (focus) tab.focus();
      }

      tabs.forEach(function (tab, index) {
        tab.addEventListener('click', function () { select(tab, false); });
        tab.addEventListener('keydown', function (evt) {
          var next = null;
          if (evt.key === 'ArrowRight' || evt.key === 'ArrowDown') next = tabs[(index + 1) % tabs.length];
          else if (evt.key === 'ArrowLeft' || evt.key === 'ArrowUp') next = tabs[(index - 1 + tabs.length) % tabs.length];
          else if (evt.key === 'Home') next = tabs[0];
          else if (evt.key === 'End') next = tabs[tabs.length - 1];
          if (next) {
            evt.preventDefault();
            select(next, true);
          }
        });
      });

      var initial = tabs.filter(function (t) { return t.getAttribute('aria-selected') === 'true'; })[0] || tabs[0];
      select(initial, false);
    });
  }

  /* ---------- copy to clipboard ---------- */

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      try {
        document.execCommand('copy') ? resolve() : reject(new Error('copy rejected'));
      } catch (err) {
        reject(err);
      }
      document.body.removeChild(area);
    });
  }

  function initCopy() {
    each(document.querySelectorAll('[data-copy]'), function (btn) {
      var original = btn.querySelector('[data-copy-label]');
      btn.addEventListener('click', function () {
        var target = document.getElementById(btn.getAttribute('data-copy'));
        if (!target) return;
        copyText(target.textContent.trim()).then(function () {
          if (!original) return;
          var was = original.textContent;
          original.textContent = '已複製';
          window.setTimeout(function () { original.textContent = was; }, 1600);
        }, function () {
          if (original) original.textContent = '請手動複製';
        });
      });
    });
  }

  /* ---------- scroll reveal ---------- */

  function initReveal() {
    var items = document.querySelectorAll('.reveal');
    if (!items.length) return;

    var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced || !('IntersectionObserver' in window)) {
      each(items, function (el) { el.classList.add('is-visible'); });
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });

    each(items, function (el) { observer.observe(el); });
  }

  /* ---------- download selector ---------- */

  function initSelector() {
    var selector = document.querySelector('[data-selector]');
    var listing = document.getElementById('asset-list');
    if (!selector || !listing) return;

    var cards = Array.prototype.slice.call(listing.querySelectorAll('.asset'));
    var note = document.getElementById('asset-empty');
    var state = {};

    each(selector.querySelectorAll('.chip'), function (chip) {
      if (chip.getAttribute('aria-pressed') === 'true') {
        state[chip.getAttribute('data-group')] = chip.getAttribute('data-value');
      }
    });

    function matches(card) {
      var keys = ['edition', 'form', 'machine'];
      for (var i = 0; i < keys.length; i += 1) {
        var want = state[keys[i]];
        if (want && card.getAttribute('data-' + keys[i]) !== want) return false;
      }
      return true;
    }

    function apply() {
      var shown = 0;
      cards.forEach(function (card) {
        var ok = matches(card);
        card.hidden = !ok;
        if (ok) shown += 1;
      });
      if (note) note.hidden = shown !== 0;
      each(selector.querySelectorAll('.chip'), function (chip) {
        var on = state[chip.getAttribute('data-group')] === chip.getAttribute('data-value');
        chip.setAttribute('aria-pressed', on ? 'true' : 'false');
      });
    }

    each(selector.querySelectorAll('.chip'), function (chip) {
      chip.addEventListener('click', function () {
        var group = chip.getAttribute('data-group');
        var value = chip.getAttribute('data-value');
        state[group] = state[group] === value ? null : value;
        apply();
      });
    });

    var reset = document.querySelector('[data-selector-reset]');
    if (reset) {
      reset.addEventListener('click', function () {
        state = {};
        apply();
      });
    }

    apply();
  }

  /* ---------- copy a link ---------- */

  function initCopyUrl() {
    each(document.querySelectorAll('[data-copy-url]'), function (btn) {
      var label = btn.querySelector('[data-copy-label]');
      btn.addEventListener('click', function () {
        copyText(btn.getAttribute('data-copy-url')).then(function () {
          if (!label) return;
          var was = label.textContent;
          label.textContent = '已複製';
          window.setTimeout(function () { label.textContent = was; }, 1600);
        }, function () {
          if (label) label.textContent = '請手動複製';
        });
      });
    });
  }

  /* ---------- motion helpers ---------- */

  function mq(query) {
    return window.matchMedia ? window.matchMedia(query) : { matches: false, addEventListener: null };
  }

  var motionOK = !mq('(prefers-reduced-motion: reduce)').matches;
  var pointerOK = mq('(hover: hover) and (pointer: fine)').matches;

  function supportsTimeline(value) {
    return !!(window.CSS && CSS.supports && CSS.supports('animation-timeline', value));
  }

  /* Runs a callback at most once per frame, with the latest arguments. */
  function framed(fn) {
    var pending = false;
    return function () {
      if (pending) return;
      pending = true;
      window.requestAnimationFrame(function () {
        pending = false;
        fn();
      });
    };
  }

  /* ---------- scroll progress ---------- */

  function initProgress() {
    var bar = document.querySelector('.scroll-progress span');
    if (!bar || !motionOK) return;
    if (supportsTimeline('scroll()')) return;   /* CSS drives it */

    var update = framed(function () {
      var doc = document.documentElement;
      var span = doc.scrollHeight - doc.clientHeight;
      var ratio = span > 0 ? doc.scrollTop / span : 0;
      bar.style.transform = 'scaleX(' + Math.min(1, Math.max(0, ratio)).toFixed(4) + ')';
    });

    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update, { passive: true });
    update();
  }

  /* ---------- hero: circle drift, parallax, magnetic button, cat ---------- */

  function initHero() {
    var hero = document.querySelector('.hero');
    if (!hero || !motionOK) return;

    var visible = true;
    if ('IntersectionObserver' in window) {
      visible = false;
      new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
      }, { threshold: 0 }).observe(hero);
    }

    /* pointer drift */
    if (pointerOK) {
      var px = 0;
      var py = 0;
      var applyDrift = framed(function () {
        hero.style.setProperty('--mx', px.toFixed(1) + 'px');
        hero.style.setProperty('--my', py.toFixed(1) + 'px');
      });
      hero.addEventListener('pointermove', function (evt) {
        if (!visible) return;
        var r = hero.getBoundingClientRect();
        px = ((evt.clientX - r.left) / r.width - 0.5) * 24;
        py = ((evt.clientY - r.top) / r.height - 0.5) * 24;
        applyDrift();
      }, { passive: true });
      hero.addEventListener('pointerleave', function () {
        px = 0;
        py = 0;
        applyDrift();
      });
    }

    /* scroll parallax, transform only */
    var applyParallax = framed(function () {
      if (!visible) return;
      var offset = Math.min(window.scrollY * 0.15, 120);
      hero.style.setProperty('--par', (-offset).toFixed(1) + 'px');
    });
    window.addEventListener('scroll', applyParallax, { passive: true });
    applyParallax();

    /* magnetic primary call to action */
    var magnet = hero.querySelector('[data-magnetic]');
    if (magnet && pointerOK) {
      var mx = 0;
      var my = 0;
      var applyMagnet = framed(function () {
        magnet.style.setProperty('--mag-x', mx.toFixed(1) + 'px');
        magnet.style.setProperty('--mag-y', my.toFixed(1) + 'px');
      });
      var release = function () {
        mx = 0;
        my = 0;
        applyMagnet();
      };
      hero.addEventListener('pointermove', function (evt) {
        if (!visible) return;
        var r = magnet.getBoundingClientRect();
        var dx = evt.clientX - (r.left + r.width / 2);
        var dy = evt.clientY - (r.top + r.height / 2);
        var reach = 40;
        var outX = Math.max(0, Math.abs(dx) - r.width / 2);
        var outY = Math.max(0, Math.abs(dy) - r.height / 2);
        if (Math.sqrt(outX * outX + outY * outY) > reach) {
          release();
          return;
        }
        mx = Math.max(-10, Math.min(10, dx * 0.34));
        my = Math.max(-10, Math.min(10, dy * 0.34));
        applyMagnet();
      }, { passive: true });
      hero.addEventListener('pointerleave', release);
      magnet.addEventListener('blur', release);
    }

    /* mascot: one-time unfold, then a small tilt toward the pointer.
       The 3D module stamps data-cat3d="on" on .hero-cat once it is really
       running, and from then on it owns both. */
    var cat = hero.querySelector('.hero-cat-svg');
    var catBox = hero.querySelector('.hero-cat');
    if (!cat) return;

    function cat3dOn() {
      return !!catBox && catBox.getAttribute('data-cat3d') === 'on';
    }

    if ('IntersectionObserver' in window) {
      var catWatch = new IntersectionObserver(function (entries) {
        if (!entries[0].isIntersecting) return;
        cat.classList.add('is-unfolded');
        catWatch.disconnect();
      }, { threshold: 0.2 });
      catWatch.observe(cat);
      /* Safety net: observers are frozen while the tab is in the background,
         and the panels start hidden. Never leave the mascot invisible. */
      window.setTimeout(function () {
        cat.classList.add('is-unfolded');
        catWatch.disconnect();
      }, 2000);
    } else {
      cat.classList.add('is-unfolded');
    }

    if (!pointerOK) return;
    var rx = 0;
    var ry = 0;
    var applyTilt = framed(function () {
      cat.style.setProperty('--cat-rx', rx.toFixed(2) + 'deg');
      cat.style.setProperty('--cat-ry', ry.toFixed(2) + 'deg');
    });
    hero.addEventListener('pointermove', function (evt) {
      if (!visible || cat3dOn()) return;
      var r = cat.getBoundingClientRect();
      var dx = (evt.clientX - (r.left + r.width / 2)) / (r.width || 1);
      var dy = (evt.clientY - (r.top + r.height / 2)) / (r.height || 1);
      ry = Math.max(-10, Math.min(10, dx * 16));
      rx = Math.max(-10, Math.min(10, -dy * 16));
      applyTilt();
    }, { passive: true });
    hero.addEventListener('pointerleave', function () {
      rx = 0;
      ry = 0;
      applyTilt();
    });
  }

  /* ---------- layer stack entrance ---------- */

  function initStack() {
    var stack = document.querySelector('.stack');
    if (!stack || !motionOK) return;
    if (supportsTimeline('view()')) return;   /* CSS drives it */
    if (!('IntersectionObserver' in window)) {
      stack.classList.add('is-charged');
      each(stack.querySelectorAll('.stack-row'), function (row) { row.classList.add('is-in'); });
      return;
    }

    var rows = Array.prototype.slice.call(stack.querySelectorAll('.stack-row'));
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-in');
        observer.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.15 });

    rows.forEach(function (row, i) {
      row.style.transitionDelay = (i * 120) + 'ms';
      observer.observe(row);
    });

    var charge = new IntersectionObserver(function (entries) {
      if (!entries[0].isIntersecting) return;
      stack.classList.add('is-charged');
      charge.disconnect();
    }, { threshold: 0.08 });
    charge.observe(stack);
  }

  /* ---------- screenshot frame tilt ---------- */

  /* A small pointer-following pitch on the screenshot frames, on top of the
     CSS hover lift. Hover-capable fine pointers only, and the two custom
     properties both default to 0deg, so a device without one never sees a
     transform it did not ask for. */
  function initFrameTilt() {
    if (!motionOK || !pointerOK) return;
    var frames = document.querySelectorAll('.frame');
    if (!frames.length) return;

    var MAX = 3;   /* degrees */

    each(frames, function (frame) {
      var rx = 0;
      var ry = 0;
      var apply = framed(function () {
        frame.style.setProperty('--tilt-x', rx.toFixed(2) + 'deg');
        frame.style.setProperty('--tilt-y', ry.toFixed(2) + 'deg');
      });
      var reset = function () {
        rx = 0;
        ry = 0;
        apply();
      };
      frame.addEventListener('pointermove', function (evt) {
        var r = frame.getBoundingClientRect();
        if (!r.width || !r.height) return;
        var dx = (evt.clientX - (r.left + r.width / 2)) / (r.width / 2);
        var dy = (evt.clientY - (r.top + r.height / 2)) / (r.height / 2);
        ry = Math.max(-MAX, Math.min(MAX, dx * MAX));
        rx = Math.max(-MAX, Math.min(MAX, -dy * MAX));
        apply();
      }, { passive: true });
      frame.addEventListener('pointerleave', reset);
    });
  }

  /* ---------- wide tables ---------- */

  function initTableHints() {
    var shells = document.querySelectorAll('.table-shell');
    if (!shells.length) return;

    var check = framed(function () {
      each(shells, function (shell) {
        var scroller = shell.querySelector('.table-scroll');
        if (!scroller) return;
        var over = scroller.scrollWidth - scroller.clientWidth > 4;
        shell.setAttribute('data-scrollable', over ? 'true' : 'false');
      });
    });

    window.addEventListener('resize', check, { passive: true });
    each(shells, function (shell) {
      var scroller = shell.querySelector('.table-scroll');
      if (scroller) scroller.addEventListener('scroll', check, { passive: true });
    });
    check();
  }

  /* ---------- comparison table disclosures ---------- */

  /* The third column ships open so the row reads as an ordinary cell on wide
     screens and stays readable with JS off. Narrow screens collapse it. */
  function initCellDetails() {
    var cells = document.querySelectorAll('.cell-detail');
    if (!cells.length) return;

    var narrow = mq('(max-width: 600px)');
    var apply = function () {
      each(cells, function (cell) {
        if (narrow.matches) {
          if (!cell.dataset.collapsed) {
            cell.open = false;
            cell.dataset.collapsed = '1';
          }
        } else {
          cell.open = true;
          delete cell.dataset.collapsed;
        }
      });
    };

    if (narrow.addEventListener) narrow.addEventListener('change', apply);
    else if (narrow.addListener) narrow.addListener(apply);
    apply();
  }

  /* ---------- boot ---------- */

  function boot() {
    initTheme();
    initNav();
    initTabs();
    initCopy();
    initCopyUrl();
    initReveal();
    initSelector();
    initProgress();
    initHero();
    initStack();
    initFrameTilt();
    initTableHints();
    initCellDetails();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
}());
