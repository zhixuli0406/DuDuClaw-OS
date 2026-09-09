#!/usr/bin/env node
/**
 * sync-docs.mjs — assemble the Starlight content tree from two repos.
 *
 * Sources
 *   1. This repo (DuDuClaw-OS): `docs/**` plus README.md / README.en.md /
 *      CHANGELOG.md / SECURITY.md at the repo root.
 *   2. The platform repo (DuDuClaw): only the five public sections listed in
 *      SECTIONS below. Everything else in that repo (todo/, rfc/, adr/, …)
 *      is deliberately not public and is never read.
 *
 * Locale layout in the platform repo
 *   <section>/x.md          English      -> en/<section>/x
 *   <section>/zh-TW/x.md    Traditional  -> <section>/x        (root locale)
 *   <section>/ja-JP/x.md    Japanese     -> ja/<section>/x
 *   An English file with no zh-TW twin is also published at the root slug,
 *   carrying a short notice that the page is the English original.
 *
 * The script is idempotent: it wipes and rebuilds src/content/docs/ on every
 * run. If the platform checkout is missing it warns and builds the OS docs
 * only, so the site always builds.
 *
 * Env
 *   DUDUCLAW_PLATFORM_DOCS  path to the platform repo's docs/ directory
 *                           (default: ../DuDuClaw/docs relative to this repo)
 *   DOCS_BASE               site path prefix, must match astro.config base
 *                           (default: /docs)
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { docsBase, docsBasePrefix } from '../base.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SITE_ROOT = path.resolve(HERE, '..');
const REPO_ROOT = path.resolve(SITE_ROOT, '..');

const PLATFORM_DOCS = path.resolve(
  process.env.DUDUCLAW_PLATFORM_DOCS || path.join(REPO_ROOT, '..', 'DuDuClaw', 'docs'),
);
const OS_DOCS = path.join(REPO_ROOT, 'docs');
const OUT = path.join(SITE_ROOT, 'src', 'content', 'docs');
const CONTENT_SRC = path.join(SITE_ROOT, 'content-src');
/** Written for astro.config.mjs; see START_SLUGS below. */
const START_LINKS_JSON = path.join(SITE_ROOT, 'src', 'start-links.json');

/**
 * The "入門與安裝" sidebar group, in order. Starlight rejects a sidebar slug
 * that has no page, so the list is filtered against what was actually emitted
 * and handed to astro.config.mjs — that way a build without the platform
 * checkout still succeeds with a shorter group instead of failing.
 */
const START_SLUGS = [
  'os/readme',
  'guides/hardware-requirements',
  'features/50-duduclaw-os-appliance',
  'features/52-desktop-edition',
  'guides/app-compat',
];

/** Concatenation-friendly form of the site's base path; see ../base.mjs. */
const BASE = docsBasePrefix();

/** Public whitelist for the platform repo. Nothing else is ever read. */
const SECTIONS = ['features', 'guides', 'architecture', 'spec', 'api'];

/** Source subdirectory -> site locale. */
const LOCALE_DIRS = { 'zh-TW': 'root', 'ja-JP': 'ja' };
const LOCALE_PREFIX = { root: '', en: 'en', ja: 'ja' };

const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.svg', '.gif', '.webp', '.avif']);

const EN_ONLY_NOTICE = [
  ':::note',
  '此頁尚無中文版，以下為英文原文。',
  ':::',
  '',
].join('\n');

const stats = {
  pages: { root: 0, en: 0, ja: 0 },
  bySource: { platform: 0, os: 0 },
  enFallbackPages: 0,
  links: {
    rewritten: 0,
    plaintextOutsideWhitelist: 0,
    plaintextGithub: 0,
    keptGithubReleases: 0,
    bareGithubDefused: 0,
  },
  imagesCopied: 0,
  warnings: [],
};

// ---------------------------------------------------------------- helpers

function walk(dir, filter = () => true, acc = []) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, filter, acc);
    else if (e.isFile() && filter(p)) acc.push(p);
  }
  return acc;
}

const isMarkdown = (p) => p.toLowerCase().endsWith('.md');

function slugForBasename(file) {
  const base = path.basename(file, path.extname(file));
  return base.toLowerCase() === 'readme' ? 'index' : base;
}

/** Site URL for a logical page id in a given locale. Always ends with `/`. */
function urlFor(id, locale) {
  const prefix = LOCALE_PREFIX[locale];
  const clean = id.replace(/(^|\/)index$/, '$1').replace(/\/$/, '');
  return `${BASE}/${prefix ? `${prefix}/` : ''}${clean ? `${clean}/` : ''}`;
}

/** Content-collection path for a logical page id in a given locale. */
function filePathFor(id, locale) {
  const prefix = LOCALE_PREFIX[locale];
  return path.join(OUT, prefix, `${id}.md`);
}

// ------------------------------------------------- frontmatter extraction

function stripInlineMarkdown(s) {
  return s
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/(^|\W)\*([^*]+)\*/g, '$1$2')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function truncateChars(s, max) {
  const chars = Array.from(s);
  if (chars.length <= max) return s;
  return `${chars.slice(0, max - 1).join('').trimEnd()}…`;
}

/**
 * Pull the title out of the first H1 and drop that line from the body.
 * Returns { title, description, body }.
 */
function extractFrontmatterParts(raw, fallbackTitle) {
  const lines = raw.replace(/\r\n/g, '\n').split('\n');

  let titleIdx = -1;
  let title = '';
  for (let i = 0; i < lines.length; i += 1) {
    const m = /^#\s+(.*\S)\s*$/.exec(lines[i]);
    if (m) {
      titleIdx = i;
      title = stripInlineMarkdown(m[1]);
      break;
    }
    // Stop looking once real prose has started; a doc with no leading H1
    // keeps its filename-derived title.
    if (i > 40) break;
  }

  const body = lines.slice();
  if (titleIdx >= 0) {
    body.splice(titleIdx, 1);
    while (body[titleIdx] !== undefined && body[titleIdx].trim() === '') body.splice(titleIdx, 1);
  }

  const description = firstParagraph(body);
  return {
    title: title || fallbackTitle,
    description,
    body: body.join('\n'),
  };
}

function firstParagraph(lines) {
  let inFence = false;
  const buf = [];
  for (const rawLine of lines) {
    const line = rawLine.trimEnd();
    if (/^\s*(```|~~~)/.test(line)) {
      inFence = !inFence;
      if (buf.length) break;
      continue;
    }
    if (inFence) continue;

    const t = line.trim();
    if (!t) {
      if (buf.length) break;
      continue;
    }
    if (/^#{1,6}\s/.test(t)) {
      if (buf.length) break;
      continue;
    }
    // Skip structural / non-prose openers until prose shows up.
    if (!buf.length && (/^\|/.test(t) || /^[-*+]\s/.test(t) || /^\d+\.\s/.test(t) || /^<\w/.test(t) || /^<\//.test(t) || /^(-{3,}|={3,})$/.test(t))) {
      continue;
    }
    buf.push(t.replace(/^>\s?/, ''));
    if (buf.join(' ').length > 400) break;
  }
  const text = stripInlineMarkdown(buf.join(' '));
  return text ? truncateChars(text, 160) : '';
}

// ---------------------------------------------------------- link rewriting

/** Replace fenced code blocks and inline code with placeholders. */
function maskCode(text) {
  const store = [];
  let out = text.replace(/(^|\n)(\s*)(```|~~~)[^\n]*\n[\s\S]*?\n\s*\3[^\n]*(?=\n|$)/g, (m) => {
    store.push(m);
    return `\u0000FENCE${store.length - 1}\u0000`;
  });
  out = out.replace(/(`+)(?:(?!\1)[\s\S])+?\1/g, (m) => {
    store.push(m);
    return `\u0000CODE${store.length - 1}\u0000`;
  });
  return { text: out, store };
}

function unmaskCode(text, store) {
  return text.replace(/\u0000(?:FENCE|CODE)(\d+)\u0000/g, (_, i) => store[Number(i)]);
}

const EXTERNAL_RE = /^(https?:|mailto:|tel:|data:|#|\/\/)/i;

/**
 * Rewrite one link target found in `sourceFile` (locale `locale`).
 * Returns { href } to keep the link, or { plain: true } to drop the link and
 * leave only its text.
 */
function resolveLink(target, sourceFile, locale, pageIndex, currentId) {
  const trimmed = target.trim();
  if (!trimmed) return { plain: true };

  if (/^https?:\/\/(www\.)?github\.com\//i.test(trimmed)) {
    if (/\/releases(\/|$|\?|#)/i.test(trimmed)) {
      stats.links.keptGithubReleases += 1;
      return { href: trimmed };
    }
    stats.links.plaintextGithub += 1;
    return { plain: true };
  }
  if (EXTERNAL_RE.test(trimmed)) return { href: trimmed };

  const [pathPart, hash = ''] = splitHash(trimmed);
  if (!pathPart) return { href: trimmed };

  const abs = path.resolve(path.dirname(sourceFile), safeDecode(pathPart));
  const hit = pageIndex.get(abs);
  if (hit) {
    stats.links.rewritten += 1;
    // Same document, different language file (README.md ↔ README.en.md):
    // honour the language the author pointed at. Everything else stays in the
    // reader's current language.
    const wanted = hit.id === currentId && hit.locale !== locale ? hit.locale : locale;
    return { href: urlFor(hit.id, wanted) + hash };
  }
  stats.links.plaintextOutsideWhitelist += 1;
  return { plain: true };
}

function splitHash(s) {
  const i = s.indexOf('#');
  if (i < 0) return [s, ''];
  return [s.slice(0, i), s.slice(i)];
}

/** decodeURI throws on a stray `%`; a malformed link is just an unknown link. */
function safeDecode(s) {
  try {
    return decodeURI(s);
  } catch {
    return s;
  }
}

/** Copy an image referenced by a page and return its new relative href. */
function handleImage(target, sourceFile, outFile) {
  const [pathPart, hash = ''] = splitHash(target.trim());
  if (EXTERNAL_RE.test(pathPart)) return target;
  const abs = path.resolve(path.dirname(sourceFile), safeDecode(pathPart));
  if (!IMAGE_EXT.has(path.extname(abs).toLowerCase()) || !fs.existsSync(abs)) return target;

  const rel = pathPart.includes('..') ? `./${path.basename(abs)}` : `./${pathPart.replace(/^\.\//, '')}`;
  const dest = path.resolve(path.dirname(outFile), rel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(abs, dest);
  stats.imagesCopied += 1;
  return rel + hash;
}

function transformLinks(body, { sourceFile, outFile, locale, pageIndex, currentId }) {
  const masked = maskCode(body);
  let text = masked.text;

  // Images first, so the link pass never sees them.
  text = text.replace(/!\[([^\]]*)\]\(([^)\s]+)(\s+"[^"]*")?\)/g, (_m, alt, target, title) => {
    const next = handleImage(target, sourceFile, outFile);
    return `![${alt}](${next}${title || ''})`;
  });

  // Inline links. The label may itself contain an image (badge links), so one
  // level of `![...]` nesting is allowed inside it.
  const LINK_RE = /(^|[^!])\[((?:[^[\]]|!\[[^\]]*\])*)\]\(([^)\s]+)(\s+"[^"]*")?\)/g;
  text = text.replace(LINK_RE, (_m, lead, label, target, title) => {
    const r = resolveLink(target, sourceFile, locale, pageIndex, currentId);
    if (r.plain) return `${lead}${label}`;
    return `${lead}[${label}](${r.href}${title || ''})`;
  });

  // Bare GitHub URLs would be auto-linked by GFM; defuse them into code spans
  // unless they point at a Releases page.
  text = text.replace(/(^|[\s(|>])(https:\/\/(?:www\.)?github\.com\/[^\s)|<>\]]+)/g, (m, lead, url) => {
    if (/\/releases(\/|$|\?|#)/i.test(url)) return m;
    stats.links.bareGithubDefused += 1;
    return `${lead}\`${url}\``;
  });

  return unmaskCode(text, masked.store);
}

// -------------------------------------------------------------- page model

/**
 * A page to emit.
 * @typedef {{ id: string, locale: 'root'|'en'|'ja', source: string,
 *             enOnly?: boolean, origin: 'platform'|'os' }} Page
 */

function collectPlatformPages() {
  /** @type {Page[]} */
  const pages = [];
  if (!fs.existsSync(PLATFORM_DOCS)) {
    stats.warnings.push(
      `platform docs not found at ${PLATFORM_DOCS} — building OS docs only ` +
        `(set DUDUCLAW_PLATFORM_DOCS to fix)`,
    );
    return pages;
  }

  for (const section of SECTIONS) {
    const dir = path.join(PLATFORM_DOCS, section);
    if (!fs.existsSync(dir)) {
      stats.warnings.push(`whitelisted section missing: ${section}`);
      continue;
    }

    const englishFiles = fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isFile() && isMarkdown(e.name))
      .map((e) => path.join(dir, e.name));

    for (const file of englishFiles) {
      const id = `${section}/${slugForBasename(file)}`;
      pages.push({ id, locale: 'en', source: file, origin: 'platform' });

      const zh = path.join(dir, 'zh-TW', path.basename(file));
      if (fs.existsSync(zh)) {
        pages.push({ id, locale: 'root', source: zh, origin: 'platform' });
      } else {
        // No Chinese twin: publish the English original at the root slug so
        // the default sidebar has no holes.
        pages.push({ id, locale: 'root', source: file, enOnly: true, origin: 'platform' });
      }

      const ja = path.join(dir, 'ja-JP', path.basename(file));
      if (fs.existsSync(ja)) {
        pages.push({ id, locale: 'ja', source: ja, origin: 'platform' });
      }
    }

    // Translated files with no English original still deserve a page.
    for (const [subdir, locale] of Object.entries(LOCALE_DIRS)) {
      const sub = path.join(dir, subdir);
      if (!fs.existsSync(sub)) continue;
      for (const e of fs.readdirSync(sub, { withFileTypes: true })) {
        if (!e.isFile() || !isMarkdown(e.name)) continue;
        if (fs.existsSync(path.join(dir, e.name))) continue;
        const id = `${section}/${slugForBasename(e.name)}`;
        pages.push({ id, locale, source: path.join(sub, e.name), origin: 'platform' });
      }
    }
  }
  return pages;
}

/**
 * The OS repo has no per-language directories — some of its documents are
 * written in Chinese, some in English. A page landing in the zh-TW root locale
 * with essentially no CJK in it is an English original and says so.
 */
function looksEnglish(file) {
  const text = fs.readFileSync(file, 'utf8');
  const cjk = text.match(/[\u3400-\u9FFF\uF900-\uFAFF]/g);
  return (cjk ? cjk.length : 0) < 20;
}

function collectOsPages() {
  /** @type {Page[]} */
  const pages = [];

  const rootFiles = [
    { file: 'README.md', id: 'os/readme', locale: 'root' },
    { file: 'README.en.md', id: 'os/readme', locale: 'en' },
    { file: 'CHANGELOG.md', id: 'os/changelog', locale: 'root' },
    { file: 'SECURITY.md', id: 'os/security', locale: 'root' },
  ];
  for (const r of rootFiles) {
    const abs = path.join(REPO_ROOT, r.file);
    if (!fs.existsSync(abs)) {
      stats.warnings.push(`OS root file missing: ${r.file}`);
      continue;
    }
    pages.push({
      id: r.id,
      locale: r.locale,
      source: abs,
      origin: 'os',
      enOnly: r.locale === 'root' && looksEnglish(abs),
    });
  }

  for (const abs of walk(OS_DOCS, isMarkdown)) {
    const rel = path.relative(OS_DOCS, abs);
    const dir = path.dirname(rel);
    const id = ['os', ...(dir === '.' ? [] : dir.split(path.sep)), slugForBasename(abs)].join('/');
    pages.push({ id, locale: 'root', source: abs, origin: 'os', enOnly: looksEnglish(abs) });
  }
  return pages;
}

// -------------------------------------------------------------------- main

function rmrf(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

function copyTree(from, to) {
  if (!fs.existsSync(from)) return 0;
  let n = 0;
  for (const abs of walk(from)) {
    const dest = path.join(to, path.relative(from, abs));
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(abs, dest);
    n += 1;
  }
  return n;
}

function main() {
  const pages = [...collectPlatformPages(), ...collectOsPages()];

  // Index every source file so links between them can be rewritten.
  const pageIndex = new Map();
  for (const p of pages) {
    if (!pageIndex.has(p.source)) pageIndex.set(p.source, p);
  }

  rmrf(OUT);
  fs.mkdirSync(OUT, { recursive: true });

  const seen = new Set();
  for (const p of pages) {
    const key = `${p.locale}:${p.id}`;
    if (seen.has(key)) {
      stats.warnings.push(`duplicate page id skipped: ${key} (${p.source})`);
      continue;
    }
    seen.add(key);

    const outFile = filePathFor(p.id, p.locale);
    const raw = fs.readFileSync(p.source, 'utf8');
    const fallbackTitle = path.basename(p.source, '.md');
    const { title, description, body } = extractFrontmatterParts(raw, fallbackTitle);

    const transformed = transformLinks(body, {
      sourceFile: p.source,
      outFile,
      locale: p.locale,
      pageIndex,
      currentId: p.id,
    });

    const fm = ['---', `title: ${JSON.stringify(title)}`];
    if (description) fm.push(`description: ${JSON.stringify(description)}`);
    fm.push('---', '');

    const notice = p.enOnly ? EN_ONLY_NOTICE : '';
    fs.mkdirSync(path.dirname(outFile), { recursive: true });
    fs.writeFileSync(outFile, `${fm.join('\n')}${notice}${transformed.replace(/^\n+/, '')}\n`);

    stats.pages[p.locale] += 1;
    stats.bySource[p.origin] += 1;
    if (p.enOnly) stats.enFallbackPages += 1;
  }

  const handAuthored = copyTree(CONTENT_SRC, OUT);

  const startLinks = START_SLUGS.filter((slug) => seen.has(`root:${slug}`));
  fs.writeFileSync(START_LINKS_JSON, `${JSON.stringify(startLinks, null, 2)}\n`);
  for (const slug of START_SLUGS) {
    if (!startLinks.includes(slug)) {
      stats.warnings.push(`start-group slug has no page, dropped from sidebar: ${slug}`);
    }
  }

  // ------------------------------------------------------------- report
  const total = stats.pages.root + stats.pages.en + stats.pages.ja;
  const lines = [
    'sync-docs: content tree rebuilt',
    `  platform docs : ${fs.existsSync(PLATFORM_DOCS) ? PLATFORM_DOCS : `${PLATFORM_DOCS} (MISSING)`}`,
    `  os docs       : ${OS_DOCS}`,
    `  output        : ${path.relative(SITE_ROOT, OUT)}   base=${BASE}`,
    '',
    `  pages          ${total} total  (zh-TW ${stats.pages.root} · en ${stats.pages.en} · ja ${stats.pages.ja})`,
    `  by source      platform ${stats.bySource.platform} · os repo ${stats.bySource.os}`,
    `  hand-authored  ${handAuthored} file(s) from content-src/`,
    `  start group    ${startLinks.length}/${START_SLUGS.length} slug(s) available`,
    `  en-at-root     ${stats.enFallbackPages} page(s) published in zh-TW with the English-original notice`,
    '',
    `  links rewritten to site paths   ${stats.links.rewritten}`,
    `  links plain-texted (not public) ${stats.links.plaintextOutsideWhitelist}`,
    `  links plain-texted (github.com) ${stats.links.plaintextGithub}`,
    `  bare github URLs defused        ${stats.links.bareGithubDefused}`,
    `  github Releases links kept      ${stats.links.keptGithubReleases}`,
    `  images copied                   ${stats.imagesCopied}`,
  ];
  for (const w of stats.warnings) lines.push(`  WARN ${w}`);
  console.log(lines.join('\n'));
}

main();
