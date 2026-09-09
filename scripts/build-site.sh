#!/usr/bin/env bash
# Assemble the full public site into _site/ at the repo root.
#
#   _site/            <- website/            (zero-build static marketing site)
#   _site/docs/       <- docs-site/dist/     (Astro + Starlight documentation)
#
# The same layout is produced by .github/workflows/pages.yml; this script is
# the local equivalent so the assembly can be inspected before it is deployed.
#
# Usage:
#   scripts/build-site.sh              # build the docs, then assemble
#   SKIP_DOCS=1 scripts/build-site.sh  # reuse an existing docs-site/dist
#
# Env:
#   DUDUCLAW_PLATFORM_DOCS  path to the platform repo's docs/ directory.
#                           Defaults to ../DuDuClaw/docs next to this repo;
#                           if it is missing the docs build still succeeds and
#                           publishes the OS documents only (with a warning).
#   SITE_URL                canonical site origin baked into sitemap/canonical
#                           tags. Defaults to a placeholder.
#   DOCS_BASE               URL prefix the docs are served from. Defaults to
#                           /docs (custom domain or user page); a GitHub
#                           project page needs /<repo>/docs. This only changes
#                           the URLs written into the generated HTML — the
#                           assembly below always lands in _site/docs/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_OUT="$REPO_ROOT/_site"
DOCS_DIR="$REPO_ROOT/docs-site"

if [[ ! -d "$REPO_ROOT/website" ]]; then
  echo "build-site: website/ not found at $REPO_ROOT/website" >&2
  exit 1
fi

# Exported so the docs build (and its sync step) see the same value; the two
# read it through docs-site/base.mjs, which normalises `//docs` and a trailing
# slash. Kept as one variable so the local build and CI cannot drift.
export DOCS_BASE="${DOCS_BASE:-/docs}"
echo "==> DOCS_BASE=$DOCS_BASE  (output always assembles into _site/docs/)"

if [[ "${SKIP_DOCS:-0}" != "1" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "build-site: npm not found — the docs site needs Node 20+ / npm." >&2
    echo "            Re-run with SKIP_DOCS=1 to assemble the marketing site only." >&2
    exit 1
  fi
  echo "==> building docs-site (npm)"
  if [[ -d "$DOCS_DIR/node_modules" ]]; then
    ( cd "$DOCS_DIR" && npm run build )
  else
    ( cd "$DOCS_DIR" && npm ci && npm run build )
  fi
fi

if [[ ! -d "$DOCS_DIR/dist" ]]; then
  echo "build-site: $DOCS_DIR/dist missing (run without SKIP_DOCS=1 first)" >&2
  exit 1
fi

echo "==> assembling $SITE_OUT"
rm -rf "$SITE_OUT"
mkdir -p "$SITE_OUT"

# 1. the marketing site, verbatim (website/ is never modified)
cp -R "$REPO_ROOT/website/." "$SITE_OUT/"

# website/lab/ holds acceptance pages for the interactive modules. They are
# development tooling, not part of the published site.
rm -rf "$SITE_OUT/lab"

# 2. the docs build under /docs/
mkdir -p "$SITE_OUT/docs"
cp -R "$DOCS_DIR/dist/." "$SITE_OUT/docs/"

# GitHub Pages must not run Jekyll over the output (Starlight emits
# directories such as _astro/ that Jekyll would drop).
touch "$SITE_OUT/.nojekyll"

echo "==> done"
echo "    pages : $(find "$SITE_OUT" -name '*.html' | wc -l | tr -d ' ')"
echo "    size  : $(du -sh "$SITE_OUT" | cut -f1)"
echo
echo "    preview with:  python3 -m http.server 8766 --directory $SITE_OUT"
