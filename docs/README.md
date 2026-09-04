# DuDuClaw OS Documentation

> Public documentation index for DuDuClaw OS (v0.1.0, bring-up). Every
> document in this repo is filed by the same TYPE × CONFIDENTIALITY rule as
> the DuDuClaw platform repo — see [`../CLAUDE.md`](../CLAUDE.md) →
> "Documentation Classification & Placement".

---

## Start here

| Document | Description |
|----------|-------------|
| [../README.md](../README.md) · [../README.en.md](../README.en.md) | What DuDuClaw OS is, the two release artifact forms, verify / flash quick start, build pipeline |
| [../CHANGELOG.md](../CHANGELOG.md) | Release history (Keep a Changelog 1.1.0; the OS version line is independent of the platform) |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Where changes go, definition of done, docs-in-the-same-commit rule |
| [../SECURITY.md](../SECURITY.md) | Vulnerability reporting, scope, release-artifact verification |

## Component references (L1, co-located)

| Document | Description | Status |
|----------|-------------|--------|
| [../meta-duduclaw/README.md](../meta-duduclaw/README.md) | The Yocto layer: target release, layout, image recipes and their roles, builder container, `kas build`, QEMU boot, machine-aliasing gotchas | Current |
| [../appliance/README.md](../appliance/README.md) | The earlier Debian/mkosi appliance line: layout, boot sequence, A/B wiring, Flatpak layer, open points | **Frozen** (reference only) |
| [../appliance/tests/README.md](../appliance/tests/README.md) | VM acceptance-test helper library (QMP screendump, serial expect-login, OCR screen assertions) | Frozen with the line |

Recipe-level behaviour is documented in each `.bb` / `.bbclass` header
comment; those comments are the reference for that recipe and are not
duplicated here.

## Public docs by type (`docs/<type>/`)

No typed docs have landed in this repo yet. Each subdirectory is created
when its first document does:

| Subdir | Holds |
|--------|-------|
| `architecture/` | boot chain, partition layout, update chain, trust chain |
| `guides/` | how-tos: building, flashing, real-hardware install, key management |
| `features/` | feature deep-dives from the user's side |
| `spec/` | open formats: release manifest schema, update payload layout |
| `adr/` · `rfc/` · `todo/` | decisions, proposals, public tracking |

User-facing OS docs currently published from the platform repo:

| Document | Description |
|----------|-------------|
| [DuDuClaw OS appliance](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/features/50-duduclaw-os-appliance.md) | What the finished box does, from the user's side |
| [OS keyboard shortcuts](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/features/51-os-keyboard-shortcuts.md) | Global compositor bindings, shell UI, first-run setup, lock screen |
| [Hardware requirements & compatibility](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/hardware-requirements.md) | x86-64-v3 / UEFI / SSD hard requirements, recommended mini-PCs, driver gaps |
| [App compatibility layer](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/app-compat.md) | `compat.d` runners, Bottles, Waydroid, what is and is not promised |
| [Building the mkosi appliance image](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/appliance-build.md) | Describes the `appliance/` line, which is now frozen here |

## Internal notes (L2, `wiki/`)

| Document | Description |
|----------|-------------|
| [../wiki/impl/meta-duduclaw-bring-up-notes-2026-08.md](../wiki/impl/meta-duduclaw-bring-up-notes-2026-08.md) | Archived layer README from the Y1–Y9 bring-up waves: why three repos / why kas, UKI chain verification, disk strategy, fcitx5 dependency closure, `/data` provisioning. Dated; superseded by the CHANGELOG and the current layer README |
| [../wiki/eval/real-hw-acceptance-checklist-y6-3-2026-08-26.md](../wiki/eval/real-hw-acceptance-checklist-y6-3-2026-08-26.md) | Real-hardware acceptance checklist written for the Y6 burn package (N305 / 8845HS). Its premises predate v0.1.0 |
| [../wiki/reports/bring-up-evidence/](../wiki/reports/bring-up-evidence/README.md) | QEMU boot and bitbake transcripts behind the bring-up "verified" claims |

---

## Directory structure

```
docs/                        # L1 PUBLIC — typed product & developer docs
├── README.md                # This index
├── architecture/            # (created with its first document)
├── guides/
├── features/
├── spec/
└── adr/  rfc/  todo/
wiki/                        # L2 INTERNAL — bring-up notes, checklists, evidence
├── impl/
├── eval/
└── reports/<kind>/
commercial/  research/       # L3 CONFIDENTIAL — reserved, gitignored, never committed
```

> **Confidentiality tiers** — `docs/` and the root docs are **Public**.
> `wiki/` is **Internal** (committed, unpolished). Design docs, roadmaps,
> commercial/competitive notes, research, and signing keys are
> **Confidential** and never enter this repo; the OS design docs live in the
> platform maintainers' private tree. Full rule: [`../CLAUDE.md`](../CLAUDE.md).
