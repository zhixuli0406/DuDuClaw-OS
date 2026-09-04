# Bring-up evidence transcripts (L2)

Raw QEMU serial-console and bitbake transcripts kept as the evidence behind
"verified" claims in the bring-up notes. Moved here unchanged from the
`meta-duduclaw/` layer root on 2026-09-04 (the layer root holds source, not
reports). Newer releases are verified by `scripts/release-os.sh smoke`
instead of hand-kept logs.

| File | What it proves |
|---|---|
| `qemu-boot-y1-1-PASS-evidence-2026-08-25.log` | Y1-1: `duduclaw-image-minimal` boots under OVMF/QEMU to a serial login prompt |
| `qemu-boot-y2-3-dual-verify-2026-08-25.log` | Y2-3: `duduclaw-sysd` socket + gateway `/healthz` both answer on the booted image |
| `y2-3-cli-and-image-build-2026-08-25.log` / `-retry-` | Y2-3: `duduclaw-cli` recipe + image build transcripts (first attempt and retry) |
| `y2-3-genericx86-64-build-2026-08-25.log` | Y2-3: first `duduclaw-genericx86-64` kernel/image build |

Context for the wave numbers: [`../../impl/meta-duduclaw-bring-up-notes-2026-08.md`](../../impl/meta-duduclaw-bring-up-notes-2026-08.md).
