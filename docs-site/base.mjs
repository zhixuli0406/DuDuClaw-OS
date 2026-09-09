/**
 * The one place the docs site's URL prefix is decided.
 *
 * `DOCS_BASE` lets the same build serve two shapes of GitHub Pages site:
 *
 *   custom domain / user page   base_path = ''            -> /docs
 *   project page                base_path = '/DuDuClaw-OS' -> /DuDuClaw-OS/docs
 *
 * CI composes it as `${{ steps.pages.outputs.base_path }}/docs`, which can
 * arrive as `//docs` when base_path is `/`, so collapse repeated slashes and
 * drop a trailing one. The assembled output directory is always `_site/docs/`
 * — the base only changes the URLs written into the generated HTML.
 *
 * Imported by astro.config.mjs (as Astro's `base`) and by
 * scripts/sync-docs.mjs (to write links between pages).
 */
export function docsBase(env = process.env) {
  const raw = env.DOCS_BASE ?? '/docs';
  const collapsed = `/${raw}`.replace(/\/{2,}/g, '/').replace(/\/+$/, '');
  return collapsed === '' ? '/' : collapsed;
}

/**
 * The same value as a prefix to concatenate paths onto: `/docs` stays `/docs`,
 * and a site mounted at the root becomes `''` so links read `/features/…`
 * rather than `//features/…`.
 */
export function docsBasePrefix(env = process.env) {
  const base = docsBase(env);
  return base === '/' ? '' : base;
}
