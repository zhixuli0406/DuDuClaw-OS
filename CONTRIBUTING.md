# Contributing to DuDuClaw OS

This page is the map — where each kind of contribution goes and what the
quality bar is. 繁中使用者：各節開頭附中文摘要。

## Where things live

> 先看這張表：改 OS 行為的地方是 Yocto layer；改 agent／gateway 行為請去平台 repo。

| You want to change… | Where | Notes |
|---|---|---|
| What ships in the image (packages, services, partition layout, boot chain) | `meta-duduclaw/` (recipes, classes, images, kas configs) | See [`meta-duduclaw/README.md`](meta-duduclaw/README.md) |
| The DuDuClaw gateway / dashboard / `duduclaw-*` binaries themselves | The [DuDuClaw platform repo](https://github.com/zhixuli0406/DuDuClaw) | Sources here are vendored snapshots — fix upstream, then re-run the recipe's `refresh-src.sh` |
| The build → smoke → package → publish pipeline | `scripts/release-os.sh` | Guard-gated; read the header comment first |
| The frozen Debian/mkosi line | `appliance/` | **Frozen** — reference only, not accepting feature work |

## Layer contributions

> 中文摘要：改 recipe 要真的 `kas build` 過；開機相關的改動要真的 QEMU 開機過；
> conventional commits；文件與程式同 commit；`CHANGELOG.md [Unreleased]` 要有一行。

- **Setup**: see [`meta-duduclaw/README.md`](meta-duduclaw/README.md) "Usage"
  for the builder container and the `kas build` invocation. A sibling
  checkout of the platform repo is needed only to refresh the vendored
  snapshots.
- **Definition of done**: the affected image builds (`kas build`), and any
  boot-facing change boots under QEMU (`scripts/release-os.sh smoke`).
  `duduclaw-genericx86-64` cannot be booted under QEMU — say so in the
  PR instead of implying it was tested.
- **Style**: match the recipe you are in. Recipe header comments are the
  reference for that recipe — keep them accurate when behaviour changes.
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat(os):` / `fix(os):` / `docs(os):` …).
- **Docs in the same commit**: behaviour changes update `README*.md`, the
  component README, and `CHANGELOG.md [Unreleased]`. Stale docs are treated
  as bugs.
- **Security gates fail closed**: signing, verity, TPM, firewall, and the
  publish-time re-verification must refuse on the unknown case. PRs that
  loosen a gate need an explicit rationale.

## Docs contributions

Public docs live under `docs/` by type (`architecture/`, `guides/`,
`features/`, `spec/`, `adr/`, `rfc/`, `todo/`); internal bring-up notes,
checklists, and evidence transcripts live under `wiki/`. Update
[`docs/README.md`](docs/README.md) in the same PR. The full placement rule
(three confidentiality tiers, cross-repo pointer convention) is in
[`CLAUDE.md`](CLAUDE.md) → "Documentation Classification & Placement".

## Reporting issues

Use GitHub Issues. For suspected security vulnerabilities, see
[`SECURITY.md`](SECURITY.md) instead of filing a public issue.

## License

By contributing you agree your contribution is licensed under the
repository's license (see [`LICENSE`](LICENSE)).
