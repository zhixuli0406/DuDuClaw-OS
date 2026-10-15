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
  version: 'v0.4.0',
  date: '2026-10-16',
  platform: '1.73.4',
  kernel: 'Linux 6.18',
  yocto: 'Yocto Project 6.0 "wrynose"',
  stage: 'pre-GA bring-up',
  previous: 'v0.3.0',
  repo: 'https://github.com/zhixuli0406/DuDuClaw-OS',
  downloadBase: 'https://github.com/zhixuli0406/DuDuClaw-OS/releases/download/v0.4.0/',
  minisignKey: 'RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n',
  assets: [
    {
      file: 'duduclaw-os-duduclaw-genericx86-64-v0.4.0.wic.zst',
      bytes: 1708406777, size: '1.59 GiB',
      edition: 'desktop', form: 'wic', machine: 'generic'
    },
    {
      file: 'duduclaw-os-duduclaw-qemux86-64-v0.4.0.wic.zst',
      bytes: 1704709687, size: '1.59 GiB',
      edition: 'desktop', form: 'wic', machine: 'qemu'
    },
    {
      file: 'duduclaw-os-installer-desktop-duduclaw-genericx86-64-v0.4.0.iso',
      bytes: 1987051520, size: '1.85 GiB',
      edition: 'desktop', form: 'iso', machine: 'generic'
    },
    {
      file: 'duduclaw-os-installer-desktop-duduclaw-qemux86-64-v0.4.0.iso',
      bytes: 1976954880, size: '1.84 GiB',
      edition: 'desktop', form: 'iso', machine: 'qemu'
    },
    {
      file: 'duduclaw-os-installer-duduclaw-genericx86-64-v0.4.0.iso',
      bytes: 501219328, size: '478 MiB',
      edition: 'base', form: 'iso', machine: 'generic'
    },
    {
      file: 'duduclaw-os-installer-duduclaw-qemux86-64-v0.4.0.iso',
      bytes: 491083776, size: '468 MiB',
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

  /* ---------- nav hairline after scroll ---------- */

  function initNavScroll() {
    var nav = document.querySelector('.nav');
    if (!nav) return;
    var pending = false;
    function update() {
      pending = false;
      nav.setAttribute('data-scrolled', window.scrollY > 4 ? 'true' : 'false');
    }
    window.addEventListener('scroll', function () {
      if (pending) return;
      pending = true;
      window.requestAnimationFrame(update);
    }, { passive: true });
    update();
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
    initNavScroll();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
}());
