# duduclaw-tpm.bbclass — TPM2-bound LUKS2 `/data` unlock (trust chain P1
# wave TPM, 2026-09-02 — commercial/docs/DESIGN-os-trust-chain-2026-09.md
# §4 + 2026-09-02 拍板紀錄 T5=靜態 PCR 7+11 / T6=LUKS /data 解鎖優先 /
# T7=TPM 缺席 fail-open 記錄). Read that design doc's §4 before touching
# this file. Builds on TWO already-shipped waves this design's own §5.1
# ("SB → verity → TPM") sequences ahead of this one — read their headers
# too before changing anything here:
#   - classes/duduclaw-secure-boot.bbclass (Secure Boot signing chain)
#   - classes/duduclaw-verity.bbclass (dm-verity read-only root; ALSO the
#     source of the hardest constraint this file has to work around — see
#     "WHY A GENERATOR, NOT A STATIC /etc/crypttab" below)
#
# UNCONDITIONALLY inherited by recipes-core/images/duduclaw-image-ab.bb
# (same "self-gated, off = byte-identical" convention as duduclaw-verity/
# duduclaw-secure-boot one/two waves prior — see either of THOSE classes'
# own headers for the fuller statement of this convention, not repeated
# verbatim a third time here) — every image-payload change this class
# makes is gated on DUDUCLAW_TPM_ENABLE == "1" (no `?=` default anywhere
# in this file for that variable, matching DUDUCLAW_VERITY_ENABLE's own
# precedent: an unset bitbake variable already reads as empty/None,
# `!= "1"` is `True` for that case). Set to "1" only by
# meta-duduclaw/kas/tpm-luks.yml (the overlay that ALSO adds the
# meta-security/meta-tpm sublayer pin this variable's own consumers need —
# see "LAYER AVAILABILITY" below for why the two are a matched pair, never
# one without the other).
#
# Off (unset / anything other than "1"): the one IMAGE_INSTALL:append
# block below is a python-conditional no-op — package selection, the
# final rootfs manifest, and every unit/generator this class's own sibling
# recipe (recipes-duduclaw/duduclaw-data-open/) would otherwise install
# are ALL absent, byte-identical to a build where this class were never
# inherited. Unlike duduclaw-verity.bbclass this file defines NO do_*
# tasks and touches NO wks/partition layout at all — /data's on-disk
# GEOMETRY (PARTUUID, size, GPT type) is completely unchanged by this
# wave; only what RUNS AGAINST that partition at boot changes, and only
# when this variable is on.
#
# =========================================================================
# WHY THIS WAVE EXISTS: TPM2 binds LUKS2 `/data` unlock to PCR 7 (Secure
# Boot state) + PCR 11 (this exact UKI's own measured PE sections) — T6's
# own priority order (§4.2): "只有在信任的開機鏈完整時，才能解鎖敏感資
# 料". `/data` is this device's one persistent store for `device.key` /
# `machine-id` / agent credentials / update staging (see recipes-duduclaw/
# duduclaw-firstboot/'s own SYSTEM_DIR) — TPM2-bound LUKS2 makes physical
# possession of a powered-off device insufficient to read that content;
# the disk boots into this device's OWN specific, unmodified boot chain
# or it does not unlock at all (T7: fail-CLOSED on a PCR mismatch,
# fail-OPEN only on TPM ABSENCE — the two are deliberately different
# failure classes, see recipes-duduclaw/duduclaw-data-open/files/
# duduclaw-data-open.sh's own header for the full four-cell truth table).
# =========================================================================
#
# =========================================================================
# WHY A GENERATOR, NOT A STATIC /etc/crypttab — the read-only-root
# constraint this design doc's own §4 task brief flagged as "本波最硬的約
# 束" (VER-RO wave, commit 601ba347: root is dm-verity read-only, /etc/
# crypttab and /etc/fstab are BAKED, build-time-immutable content)
# =========================================================================
#
# /data ships from the FACTORY BUILD as a real, mkfs'd, EMPTY ext4
# filesystem (files/wic/duduclaw-ab-bootdisk.wks.in's own `part /data
# --fstype=ext4 ...` line, no `--source` clause — confirmed by reading
# that exact line and its own neighboring root-B comment, which states
# explicitly that a `--fstype`-tagged partition with no `--source` still
# gets a real, empty, formatted filesystem, not raw unformatted bytes).
# `/etc/fstab`'s existing `/data` line (classes/duduclaw-verity.bbclass's
# own `duduclaw_verity_static_fstab()`, baked into the read-only rootfs
# when DUDUCLAW_VERITY_ENABLE=1 — a hard prerequisite state for THIS
# variable to make sense, per §5.1's own SB→verity→TPM order) reads
# `PARTUUID=${DUDUCLAW_AB_DATA_PARTUUID} /data ext4 defaults,
# x-systemd.growfs 0 2` — a PLAIN mount, unconditionally. A device that
# has TPM2-converted `/data` to LUKS2 needs a DIFFERENT `data.mount` (one
# that mounts `/dev/mapper/duduclaw-data`, ordered after an unlock step)
# on THAT SAME immutable rootfs — and a device WITHOUT TPM must keep
# using the existing plain line completely unmodified.
#
# THIS FILE DOES NOT TOUCH `/etc/fstab` AT ALL. Both branches are handled
# entirely at RUNTIME, by a systemd GENERATOR
# (recipes-duduclaw/duduclaw-data-open/files/duduclaw-data-open-generator,
# installed to `${nonarch_libdir}/systemd/system-generators/` — the exact
# directory systemd's OWN recipe installs its own generators to, e.g.
# `systemd-gpt-auto-generator`, confirmed by reading systemd_259.5.bb
# directly rather than guessing a plausible-looking path) that decides,
# on EVERY boot, whether to override `data.mount` at all:
#
#   override = tpm_present || luks_already_present
#
# When override is false (no TPM, disk still plain — the common case on
# any device that shipped without a TPM chip, or before this wave's own
# DUDUCLAW_TPM_ENABLE flag existed), the generator writes NOTHING. The
# EXISTING, already-verity-wave-tested `data.mount` (derived from the
# static `/etc/fstab` line above via oe-core's own systemd-fstab-
# generator, landing in the NORMAL-priority `/run/systemd/generator/`
# directory) stands completely unmodified — this is what makes "off (or
# TPM physically absent) = byte-identical" true even on an image that
# HAS this wave's own DUDUCLAW_TPM_ENABLE=1 baked in: the runtime decision,
# not just the build-time flag, is what governs behavior, per T7's own
# "TPM 缺席不拒絕開機" mandate.
#
# When override is true, the generator writes a `data.mount` (What=
# /dev/mapper/duduclaw-data, Requires=+After= duduclaw-data-open.service)
# PLUS that service unit into `/run/systemd/generator.early/` — the
# HIGHEST-priority generator output directory. Verified one-hand against
# `man/systemd.generator.xml` at this project's pinned systemd SRCREV
# (b3d8fc43e9cb531d958c17ef2cd93b374bc14e8a, the same commit
# recipes-core/systemd/systemd_%.bbappend's own header already cites):
# "Unit files placed in [generator.early] override unit files in /usr/,
# /run/ and /etc/. This means that unit files placed in this directory
# take precedence over all normal configuration, both vendor and
# user/administrator." — generator.early wins over BOTH the static
# `/etc/fstab` line AND whatever the NORMAL-priority systemd-fstab-
# generator would otherwise derive from it, by unit-search-path
# precedence (systemd loads the FIRST same-named unit it finds and never
# considers the rest — full same-named unit files, not `.d/` drop-ins,
# do not merge), NOT by execution-order luck between the two generators.
# This is the one-hand answer to the exact question the design doc's own
# §4 task brief flagged as unverified ("fstab-generator 與自訂 generator
# 的優先序要一手查證 systemd.generator(7)").
#
# The generator itself does ONLY this cheap present/absent decision
# (bounded blkid probe + a /dev/tpm0 existence check, no cryptsetup/
# cryptenroll calls at all — generators run very early and must be fast);
# ALL of the actual conversion/unlock/fail-closed logic lives in
# duduclaw-data-open.sh, a REGULAR service run later in the same
# local-fs-pre.target-ordered slot as duduclaw-firstboot-repart.service —
# see that script's own header for the full first-boot-conversion /
# every-boot-unlock / fail-closed design and its own one-hand citations
# for the exact `cryptsetup`/`systemd-cryptenroll`/`systemd-cryptsetup`
# CLI syntax used (all read directly from this project's pinned systemd
# v259.5 man-page sources in the builder container, not recalled from
# training data).
#
# =========================================================================
# LAYER AVAILABILITY — tpm2-tss / tpm2-tools are NOT in this project's
# base layer set (a real gap, not a formality)
# =========================================================================
#
# `find . -iname "tpm2-tss*.bb"` across every layer this project's base
# kas configs currently pin (openembedded-core / meta-openembedded /
# meta-virtualization / meta-yocto) returns ZERO hits — confirmed by
# actually running that search in this reconnaissance session, not
# assumed from systemd's own `PACKAGECONFIG[tpm2]` DEPENDS existing.
# `recipes-core/systemd/systemd_%.bbappend`'s own DUDUCLAW_TPM_ENABLE-
# gated `cryptsetup tpm2` PACKAGECONFIG addition (same wave) would fail
# `bitbake systemd` outright ("Nothing PROVIDES 'tpm2-tss'") without a
# layer that actually carries that recipe.
#
# Fixed by `meta-duduclaw/kas/tpm-luks.yml` (a NEW overlay, not an edit to
# the base duduclaw-os.yml/duduclaw-os-genericx86-64.yml — same
# "compose only what a test line needs" convention meta-duduclaw/kas/
# sb-signing.yml already established) pinning `meta-security`'s `wrynose`
# branch, `meta-tpm/` sublayer only (NOT meta-integrity/meta-parsec/other
# meta-security sublayers this wave has no use for): one-hand verified via
# that repo's own cgit at git.yoctoproject.org —
#   meta-security  c0d1d6200e7a84c39fb940cb1f22aad4b0b3d808  (wrynose
#     branch HEAD as of 2026-09-02, "tpm2-pkcs11: upgrade 1.9.1 -> 1.9.2")
# `meta-tpm/conf/layer.conf`, read directly at this exact commit, declares
# `LAYERSERIES_COMPAT_tpm-layer = "wrynose"` (exact generation match with
# this project's own oe-core/meta-yocto pin, same verification standard
# duduclaw-os.yml's own meta-virtualization addition already used) and
# `LAYERDEPENDS_tpm-layer = "core openembedded-layer meta-python"` — ALL
# THREE already present in this project's base layer set (core=oe-core,
# openembedded-layer=meta-oe, meta-python — both pinned since Y3-2/Y7-3),
# so no cascading new repo/commit pin is needed beyond meta-security
# itself. `meta-tpm/recipes-tpm2/` confirmed (same cgit walk, same exact
# commit) to contain `tpm2-tss_4.1.3.bb` and `tpm2-tools_5.7.bb` —
# resolving both the systemd `tpm2` PACKAGECONFIG DEPENDS and this file's
# own `tpm2-tools` IMAGE_INSTALL addition below from the SAME new layer.
#
# A kas config with DUDUCLAW_TPM_ENABLE=1 (via a build's own
# local_conf_header, however set) but WITHOUT `tpm-luks.yml` composed
# would fail at `bitbake systemd` (missing layer) before ever reaching
# this class's own IMAGE_INSTALL:append — a loud, early, correctly-
# attributed failure, not a silent wrong-image build. This class does NOT
# duplicate that layer pin itself (bbclass files cannot add kas `repos:`
# entries — that is a kas-file-only mechanism) — the pairing is
# enforced by convention (this header + tpm-luks.yml's own header,
# cross-referencing each other), not by a machine-checked gate. Flagged
# honestly rather than silently assumed always paired correctly.
#
# =========================================================================
# HONESTLY UNVERIFIED (no bitbake/kas run in this reconnaissance session —
# see this wave's own task brief, "絕不跑 bitbake/kas")
# =========================================================================
#
# - Whether `bitbake systemd` with `cryptsetup tpm2` actually resolves and
#   BUILDS cleanly against the newly-pinned tpm2-tss_4.1.3.bb (recipe
#   EXISTENCE was confirmed via cgit tree listing; its own DEPENDS chain —
#   e.g. whether tpm2-tss itself needs anything this project's layer set
#   still lacks — was NOT independently walked this round).
# - Whether the generator's directory-precedence override (generator.early
#   beating the static /etc/fstab-derived normal-priority unit) behaves
#   exactly as `systemd.generator.xml` documents on THIS project's actual
#   259.5 build (man-page text is authoritative for behavior, but the
#   NEXT real boot is the first literal confirmation).
# - The swtpm QEMU harness itself — explicitly a DIFFERENT agent/session's
#   deliverable per this wave's own task brief, not attempted here.
IMAGE_INSTALL:append = "${@ ' duduclaw-data-open systemd-crypt tpm2-tools' if d.getVar('DUDUCLAW_TPM_ENABLE') == '1' else ''}"

# `systemd-crypt` explicit, NOT relied on via systemd's own
# `RRECOMMENDS:${PN} += "${PN}-crypt"` (confirmed present in
# systemd_259.5.bb by reading it directly) — same discipline this
# project's own recipes-duduclaw/duduclaw-firstboot.bb already states for
# util-linux-findmnt/util-linux-lsblk ("A bare util-linux RDEPENDS would
# likely still pull findmnt/lsblk in on an image that honors
# recommends... this layer's own recipes consistently avoid elsewhere").
# `systemd-crypt` (FILES:${PN}-crypt in systemd_259.5.bb) carries
# `${bindir}/systemd-cryptenroll` — the ENROLL side duduclaw-data-open.sh
# calls at first-boot conversion time — plus `${libdir}/cryptsetup`
# (systemd's own cryptsetup-token plugin objects). `systemd-cryptsetup`
# itself (the UNLOCK side, `${nonarch_libdir}/systemd/systemd-cryptsetup`)
# is NOT in this split package — it falls into the default `systemd` main
# package (unclaimed by any earlier PACKAGE_BEFORE_PN entry, confirmed by
# reading systemd_259.5.bb's own PACKAGE_BEFORE_PN list: `systemd-crypt`
# only claims the two paths above), which is unconditionally in every
# image already — no separate RDEPENDS needed for that binary.
#
# `tpm2-tools` — design brief item 4 ("tpm2-tools 入 target 供診斷"):
# operator-facing diagnostics (`tpm2_pcrread`, `tpm2_getcap`, etc.) for
# investigating a TPM-related boot failure from a rescue/maintenance
# shell — NOT called by duduclaw-data-open.sh itself (that script uses
# only `systemd-cryptenroll`/`systemd-cryptsetup`, which have their own
# built-in TPM2 support via the `tpm2` PACKAGECONFIG flag above, no
# separate tpm2-tools dependency for the automated path).
