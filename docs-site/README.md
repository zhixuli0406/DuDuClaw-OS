# docs-site

The documentation site for DuDuClaw OS and the DuDuClaw platform. It is an
[Astro](https://astro.build) + [Starlight](https://starlight.astro.build) build
that turns Markdown from two repositories into a searchable, three-language
static site, published under the main site — at `/docs/` by default, see
[The base path](#the-base-path).

The site never links to GitHub for content. Every document a reader can reach
lives on our own domain: there is no "edit this page" link, no GitHub icon in
the header, and body-text links that would leave for a source file are rendered
as plain text instead. The one exception is a link to a GitHub **Releases**
page, which is where release artifacts genuinely live.

## Run it

Node 20+ (24 is what CI uses) and npm.

```bash
npm install          # first time only
npm run dev          # http://localhost:4321/docs/
npm run build        # static output in dist/
npm run preview      # serve dist/ locally
npm run sync         # regenerate the content tree without building
```

`npm run dev` and `npm run build` both run `scripts/sync-docs.mjs` first, so the
content tree is always rebuilt from the current sources. Nothing under
`src/content/docs/` is authored by hand — it is generated and gitignored.

To assemble the full public site (marketing pages + these docs) into `_site/`:

```bash
../scripts/build-site.sh
python3 -m http.server 8766 --directory ../_site
```

## The base path

The docs are served from a sub-path, and which sub-path depends on how GitHub
Pages is set up. `DOCS_BASE` decides it; `base.mjs` is the only place it is
normalised, and both `astro.config.mjs` (as Astro's `base`) and
`scripts/sync-docs.mjs` (for the links it writes between pages) read it there.

| Deployment | `configure-pages` `base_path` | `DOCS_BASE` | Pages served at |
|---|---|---|---|
| Custom domain or user page | `''` | `/docs` (the default) | `example.com/docs/` |
| Project page | `/DuDuClaw-OS` | `/DuDuClaw-OS/docs` | `user.github.io/DuDuClaw-OS/docs/` |

CI composes it as `${{ steps.pages.outputs.base_path }}/docs`; a `base_path` of
`/` would yield `//docs`, which `base.mjs` collapses, along with a trailing
slash. Locally, `scripts/build-site.sh` exports the same variable and defaults
it to `/docs`.

The base only changes the URLs written into the HTML — the assembled output is
always `_site/docs/`. To check the other shape:

```bash
DOCS_BASE=/DuDuClaw-OS/docs npm run build
grep -roh 'href="/docs/' dist --include=*.html | wc -l              # 0
grep -roh 'href="/DuDuClaw-OS/docs/' dist --include=*.html | wc -l  # many
```

Nothing in the site hard-codes the prefix. Page-to-page links come from
Starlight's routing (base-aware by construction), the landing pages build their
card hrefs from `import.meta.env.BASE_URL`, and the hero buttons use links
relative to the landing page — Starlight writes `hero.actions[].link` to `href`
verbatim, so an absolute path there would bake the base in. The 「回到官網」
header link is the parent of the base (`/docs/` → `/`, `/DuDuClaw-OS/docs/` →
`/DuDuClaw-OS/`), computed in `SiteLink.astro` rather than written as a literal
`../`, which would otherwise resolve wrongly from a deep page.

## Where the content comes from

Two repositories feed one content tree.

**This repo (DuDuClaw-OS)** — everything under `docs/**` plus four files at the
repo root:

| Source | Page |
|---|---|
| `README.md` | `/docs/os/readme/` (zh-TW) |
| `README.en.md` | `/docs/en/os/readme/` |
| `CHANGELOG.md` | `/docs/os/changelog/` |
| `SECURITY.md` | `/docs/os/security/` |
| `docs/README.md` | `/docs/os/` |
| `docs/guides/*.md` | `/docs/os/guides/…` |

**The platform repo (`zhixuli0406/DuDuClaw`)** — only these five directories are
public, and the sync script reads nothing else:

```
docs/features/  docs/guides/  docs/architecture/  docs/spec/  docs/api/
```

Everything else in that repo — `docs/todo/`, `docs/rfc/`, `docs/adr/`, and any
directory not on the list — is deliberately **not** published. Adding a
directory to `SECTIONS` in `scripts/sync-docs.mjs` is the only way to widen the
whitelist, which makes the decision reviewable in a diff.

The platform checkout is found via `DUDUCLAW_PLATFORM_DOCS`, defaulting to
`../DuDuClaw/docs` next to this repo (CI sets it to `platform/docs`). If the
path does not exist the build still succeeds: it warns and publishes the OS
documents only.

## Languages

zh-TW is the default locale and lives at the root of the site; English is under
`/docs/en/`, Japanese under `/docs/ja/`.

The platform repo stores English at `docs/<section>/x.md` and translations in
sibling directories, so the mapping is:

| Source | Page |
|---|---|
| `<section>/zh-TW/x.md` | `/docs/<section>/x/` |
| `<section>/x.md` | `/docs/en/<section>/x/` |
| `<section>/ja-JP/x.md` | `/docs/ja/<section>/x/` |

A document with no zh-TW translation is still published at the root slug — the
English original, with a short notice at the top saying so — so the default
sidebar has no holes. Pages missing from `ja` fall back to the zh-TW content
through Starlight's own fallback mechanism, which also labels them.

## What the sync script does

`scripts/sync-docs.mjs` (plain Node, no dependencies) wipes and rebuilds
`src/content/docs/` on every run:

1. Injects frontmatter — `title` from the first H1 (which is then removed, so
   Starlight renders the page title once) and `description` from the first
   paragraph, truncated to 160 characters.
2. Rewrites relative `.md` links to site paths, keeping the reader in their
   current language. Links pointing at files outside the whitelist become plain
   text carrying the original wording — never a GitHub fallback link.
3. Plain-texts `github.com` links (Releases excepted) and defuses bare GitHub
   URLs that GFM would otherwise auto-link, outside code blocks.
4. Copies images referenced by a page next to that page.
5. Prints a report: pages per locale, links rewritten, links plain-texted,
   images copied, and any warning (missing platform checkout, missing section,
   duplicate slug).

Hand-authored pages live in `content-src/` and are copied over the generated
tree, so they survive the wipe. Today that is the three landing pages
(`index.mdx`, `en/index.mdx`, `ja/index.mdx`).

It also writes `src/start-links.json` — the curated 「入門與安裝」 sidebar group,
filtered down to slugs that actually exist. Starlight refuses to build on a
sidebar slug with no page, so a checkout without the platform docs would
otherwise fail instead of degrading; the list is generated (and gitignored) for
that reason. Edit `START_SLUGS` in the sync script to change the group.

## Adding things

**A new section from the platform repo.** Add its directory name to `SECTIONS`
in `scripts/sync-docs.mjs`, then add a sidebar group in `astro.config.mjs` with
its zh-TW label plus `translations` for `en` and `ja`. Confirm the directory
really is meant to be public before doing either.

**A new language.** Add it to `locales` in `astro.config.mjs` (key = URL prefix,
`lang` = BCP-47 tag), add the prefix to `LOCALE_PREFIX` in the sync script, and
map the source directory in `LOCALE_DIRS` if the platform repo grows one. Add
the label to every sidebar group's `translations` and write the matching
`content-src/<prefix>/index.mdx` landing page.

**A hand-authored page.** Drop it in `content-src/` at the path it should have
under `src/content/docs/`.

**A page in the "getting started" group.** Add its slug to `START_SLUGS` in
`scripts/sync-docs.mjs`; the sidebar picks it up on the next sync.

## Theme

`src/styles/custom.css` maps the main site's design tokens
(`website/assets/css/site.css`) onto Starlight's CSS custom properties, so the
docs read as a section of the same site: the same ground colours (`#f3f3f3` /
`#0c0c0e`), the same MDS blue accent (`#2171cc` / `#4390ee` in dark), Inter +
Noto Sans TC for text, JetBrains Mono for code, 10–12px radii and hairline
borders. Crimson (`#e5484d`) is reserved for the logo mark and is never used as
a UI colour. Light, dark and system all work — Starlight stamps `data-theme`
before first paint, the same three-state pattern the main site uses.

The only chrome customisation beyond CSS is `src/components/SiteLink.astro`,
which replaces Starlight's social-icon slot with the single 「回到官網」 link
back to the main site.

Search is Pagefind, Starlight's built-in static index — no third-party search
service, no runtime dependency.

## Relationship to the main site

`website/` at the repo root stays zero-build: plain HTML, CSS and JS that can be
opened from disk. This directory is the part that needs Node. They are joined
only at assembly time, by `scripts/build-site.sh` locally and by
`.github/workflows/pages.yml` in CI, which copies `website/` to `_site/` and
this build to `_site/docs/`.

Generated and installed state — `node_modules/`, `dist/`, `src/content/docs/`,
`.astro/` and the assembled `_site/` — is gitignored.
