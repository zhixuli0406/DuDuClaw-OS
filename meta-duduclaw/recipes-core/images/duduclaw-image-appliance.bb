# DuDuClaw OS — shipping convergence image: A/B update + full desktop payload (Y14-A, 2026-08-27).
#
# This is the OUT-SHIPPING target commercial/docs/DESIGN-image-convergence-
# 2026-08.md (Y10-2) designed: today's layer has FOUR fragmented images and
# no single one carries flatpak+IME+A/B+/data together (see that design
# doc's §1.2 feature matrix). This recipe is the first one that does, by
# `require`-ing the A/B partition-layout recipe directly and pulling in the
# other two axes' package lists through the same shared `.inc` files those
# axes' own recipes now `require` (Y14-A, same day) — NOT by editing
# duduclaw-image-ab.bb/-data.bb/-flatpak.bb, so all three keep their own
# independent, already-QEMU-verified existence as single-axis regression
# checkpoints (design doc §2.5 "兩層 recipe 分工": this recipe is for
# integration/pre-ship verification, NOT day-to-day single-feature dev).
#
# WHY `require duduclaw-image-ab.bb` (not duduclaw-image-flatpak.bb or
# duduclaw-image-data.bb): partition layout is a CHOICE, not a stackable
# feature (design doc §2.1) — A/B (root-A/root-B) and a single root are
# mutually exclusive disk layouts. duduclaw-image-ab.bb is the only branch
# that already `inherit`s duduclaw-ab-partflags + sets WKS_FILE to the
# 4-partition layout; `require`-ing duduclaw-image-flatpak.bb instead would
# drag in duduclaw-data-partflags (3-partition assumption) through its own
# `require duduclaw-image-data.bb` chain — inheriting BOTH *-partflags
# classes on the same image would run two incompatible `sfdisk
# --part-attrs` calls against the same partition NUMBER with two different
# roles (root-B here, /data there) — see duduclaw-image-data.bb's own
# header and design doc §4.2/§5(c) for the full reasoning this recipe
# deliberately avoids re-triggering.
#
# WHY TWO `.inc` REQUIRES INSTEAD OF `require duduclaw-image-flatpak.bb`
# DIRECTLY: same reason as above, one level down — duduclaw-image-flatpak.bb
# itself `require`s duduclaw-image-data.bb (3-partition). Y14-A extracted
# both single-axis recipes' package lists into plain `.inc` files (no
# `inherit`/`WKS_FILE`, pure `IMAGE_INSTALL`/`IMAGE_ROOTFS_EXTRA_SPACE` data
# — see duduclaw-image-data.inc / duduclaw-image-flatpak.inc's own headers)
# specifically so this recipe can pull in "which packages" without also
# pulling in "which partition layout". `bitbake -e duduclaw-image-data` /
# `duduclaw-image-flatpak` were diffed against their pre-extraction values
# the same day (Y14-A) and are byte-identical — the two `.inc` files are not
# a new invention, just the pre-existing package lists given a shared home.
SUMMARY = "DuDuClaw OS shipping image — A/B update + full desktop (Steam/Chromium/IME) payload (Y14-A)"
DESCRIPTION = "${SUMMARY}. See commercial/docs/DESIGN-image-convergence-2026-08.md \
for the full convergence design and commercial/docs/TODO-agent-first-os-2026-08.md \
Y14-A entry for this recipe's own build/QEMU verification record. \
require duduclaw-image-ab.bb (A/B GPT layout + systemd-sysupdate chain) \
+ duduclaw-image-data.inc (duduclaw-firstboot /data provisioning) \
+ duduclaw-image-flatpak.inc (flatpak/bubblewrap/ostree/Steam/Chromium \
offline-repo carriage chain)."
LICENSE = "MIT"

require recipes-core/images/duduclaw-image-ab.bb
require recipes-core/images/duduclaw-image-data.inc
require recipes-core/images/duduclaw-image-flatpak.inc
# CP-1 (2026-08-30): app-compat payload — compat.d runner declarations +
# Waydroid chain. See duduclaw-image-compat.inc's own header for what ships
# and what is deliberately absent (GApps/ARM translation; Bottles rides the
# Flathub channel, not IMAGE_INSTALL). duduclaw-image-appliance-test.bb
# inherits this via its `require` of this file, so the QEMU harness sees
# the same payload.
require recipes-core/images/duduclaw-image-compat.inc

# `serial-autologin-root` / `empty-root-password` (design doc §2.3, "必須
# 移除，非可選"): duduclaw-image.bb's own IMAGE_FEATURES carries both,
# annotated there with "MUST NOT ship with this on" -- every image in this
# layer up to and including duduclaw-image-ab.bb still inherits them
# unchanged because none of them is the actual shipping target yet. This
# recipe IS, so this is the one place in the require chain that finally
# turns them off. `bitbake -e duduclaw-image-appliance` with this line
# active confirms IMAGE_FEATURES="ssh-server-dropbear" (no autologin, no
# empty password) -- this is the state this recipe ships in.
#
# TESTABILITY NOTE (Y14-A, 2026-08-27): removing this line is exactly what
# breaks the existing serial-console test harness
# (appliance/.vm/inject/serial_expect.py + appliance/tests/ab-update/
# y92_yocto_probe.py), which every prior image in this layer's own
# verification history (-ab/-data/-flatpak, all still carrying
# serial-autologin-root+empty-root-password) relies on for root shell
# access -- confirmed live: a real boot of THIS hardened recipe reaches a
# genuine `login:` prompt with no known credential, timing out the same
# harness that logs into every other image in this layer. This round's own
# QEMU verification (desktop boot + kiosk/flatpak checks) was done against
# a ONE-OFF throwaway rebuild with this line temporarily commented back out
# (never committed in that state) -- the artifact actually measured for
# A/B slot sizing (§ below) and shipped by this file is the hardened one.
# Follow-up recommendation (not done this round): a dedicated,
# non-shipped test credential mechanism (e.g. a QEMU-only kernel cmdline
# override or a separate `-test` image variant) instead of re-opening this
# exact hole every time the appliance image needs a QEMU regression pass.
# See TODO-agent-first-os-2026-08.md Y14-A entry for the full accounting.
#
# Y14 A/B T2/T6 verification round (2026-08-28): this line was temporarily
# re-commented for two more throwaway rebuilds (same reasoning as the
# Y14-A note above -- T2/T6 need a root shell for
# `appliance/tests/ab-update/y92_yocto_probe.py`'s SLOT_CHECKS over serial)
# to get `device.update_apply` (T2) and `device.update_rollback` (T6) both
# PASS end to end against this recipe's own A/B layout + full desktop
# payload (see TODO-agent-first-os-2026-08.md's Y14 entry for the complete
# evidence trail: signed release downloaded/verified/installed into the
# free slot/booted/blessed, then rolled back to the factory slot on
# demand). Restored to the shipping state here once verification
# completed -- confirmed via `bitbake -e` that this line active yields
# IMAGE_FEATURES="ssh-server-dropbear" (no autologin, no empty password).
#
# App-compat verification round (2026-08-29): the follow-up the Y14-A note
# above recommends now exists -- duduclaw-image-appliance-test.bb, a
# never-shipped `require`-variant that re-opens the two features for QEMU
# harnesses WITHOUT anyone editing this file again. bitbake's `:remove` is
# applied after every `+=`/`append` at final expansion, so a variant recipe
# cannot simply re-add the removed tokens; instead the removal itself is
# guarded by ?=-defaulted DUDUCLAW_IMAGE_TEST_LOGIN, which ONLY that test
# recipe sets. Default ("0") keeps this shipping image bit-identical to the
# unconditional remove above: `bitbake -e duduclaw-image-appliance` still
# yields IMAGE_FEATURES="ssh-server-dropbear".
DUDUCLAW_IMAGE_TEST_LOGIN ?= "0"
IMAGE_FEATURES:remove = "${@'' if d.getVar('DUDUCLAW_IMAGE_TEST_LOGIN') == '1' else 'serial-autologin-root empty-root-password'}"

# --- A/B slot sizing (Y14-A/Y14 T2-T6 round, 2026-08-27/28, real-build
# calibration, revised twice against real measurements) --------------------
#
# ROUND 1 (Y14-A, 2026-08-27): duduclaw-ab-partflags.bbclass's own inherited
# defaults (DUDUCLAW_AB_SLOT_SIZE_MB ?= "3072") are calibrated for
# duduclaw-image-ab.bb's OWN content (kiosk/IME/network/audio/A-B/data, NO
# flatpak) -- too small once this recipe's root-A/root-B also has to hold
# the flatpak/Steam/Chromium/offline-repo payload on top. Started at 10240
# (10GiB) as a deliberately generous placeholder; `do_image_wic` succeeded.
#
# ROUND 2 (Y14 T2/T6 verification, 2026-08-28): a REAL `device.update_apply`
# run against a 10240M-slot build failed with `verification_failed:
# duduclaw-os_1.62.1.root-x86-64.raw exceeded its 8589934592-byte ceiling
# mid-transfer` -- crates/duduclaw-gateway/src/os_update.rs's own
# `MAX_ROOT_BYTES = 8 * 1024 * 1024 * 1024` (8GiB), whose own doc comment
# ("a root slot is 5 GiB") predates this recipe and is now stale for the
# appliance line specifically. `make-payload.py`'s `extract_root_payload`
# truncates the extracted `.raw` payload to the FULL declared partition
# length (10240 MiB, sparse-padded) -- a plain HTTP GET (this test harness's
# own `y92_yocto_probe.py:serve()`, Python stdlib `http.server`, with no
# byte-range/sparse awareness) transmits that entire logical length,
# tripping the 8GiB ceiling on total bytes-seen well before the payload's
# real (non-zero) content -- measured by that same extraction step at
# 6,211,764,224 bytes (5924 MiB) -- ever finishes landing. NOT fixed by
# touching the 8GiB production constant (a shared safety ceiling other
# tickets/lines depend on, out of this ticket's recipe-only scope) --
# fixed here instead by keeping this recipe's OWN declared slot size under
# that ceiling with margin, which also shrinks the wastefully-transferred
# zero-padding on every future test run through this same non-sparse-aware
# harness. 7168 MiB (7GiB): comfortably under the 8192 MiB (8GiB) ceiling
# (1024 MiB / ~12% margin) and comfortably over the measured 5924 MiB real
# content (1244 MiB / ~21% margin for `do_image_wic`'s own ext4 overhead
# and near-term content growth) -- both margins are real numbers checked
# against this round's own measurements, not round numbers picked by feel.
#
# Root-A and root-B MUST stay the same size (systemd-sysupdate dd's a
# slot-A-sized payload into slot B with no resize step -- same invariant
# duduclaw-ab-partflags.bbclass's own header states), so this ONE constant
# governs both.
#
# CROSS-REFERENCE, NOT ACTED ON HERE: if a future round needs a bigger
# slot again (more app content), `MAX_ROOT_BYTES` in os_update.rs will
# need to grow WITH it (its own 8GiB ceiling is not automatically derived
# from any wks/partflags constant) -- that is a production Rust change
# with its own review, deliberately out of scope for this recipe-only
# ticket. Tracked in TODO-agent-first-os-2026-08.md's Y14 entry.
#
# This value is the duduclaw-qemux86-64 (QEMU dev/test) calibration only --
# design doc §2.4 explicitly keeps qemu's slot size smaller than the real
# genericx86-64 hardware target's own (heavier: more firmware/driver
# packages via MACHINE_EXTRA_RRECOMMENDS) requirement, which needs its own
# separate real-build measurement before shipping to actual hardware --
# NOT done in this ticket (QEMU-only verification per this ticket's own
# scope), tracked as a follow-up in TODO-agent-first-os-2026-08.md.
DUDUCLAW_AB_SLOT_SIZE_MB = "7168"

# /data: revised twice against real measurements (Y14-A round 1 → Y14 T2/T6
# round 2, 2026-08-27/28), up from the A/B line's own inherited default
# (1024M). Root cause this closes: systemd-sysupdate's root transfer
# (recipes-duduclaw/duduclaw-ab-update/files/10-duduclaw-root.transfer)
# stages the FULL new-root payload as a regular file under
# /data/duduclaw/updates BEFORE writing it into the target slot
# (crates/duduclaw-gateway/src/os_update.rs's own staging_dir) -- this is
# real, non-sparse-reducible payload content.
#
# Round 1 measured 4.4GB real content (before this same round's own
# `DUDUCLAW_AB_SLOT_SIZE_MB` fix, and before Y14-B's offline-repo GPG-flag
# fix landed a more complete Chromium+LibreOffice payload) and set this to
# 6144M. Round 2's own fresh `make-payload.py` extraction against the
# CURRENT build measured real content at 6,211,764,224 bytes (5924 MiB) --
# genuinely larger, not a measurement error, because the offline repo now
# bakes in more complete content post-Y14-B-fix -- leaving only ~220 MiB
# of headroom in a 6144M /data, uncomfortably tight for a filesystem that
# also needs room for the gateway's own persisted state tree (databases,
# skills, wiki) and firstboot markers alongside the staged update. Raised
# to 8192M (8GiB): ~2268 MiB (~37%) headroom over the 5924 MiB measured
# payload, independent of the MAX_ROOT_BYTES 8GiB ceiling above (that
# ceiling gates the TRANSFER size / DUDUCLAW_AB_SLOT_SIZE_MB, not /data's
# own capacity -- the two constants are unrelated even though they happen
# to share a "8" digit).
#
# Still a QEMU dev/test disk size, not a real disk's eventual size (design
# doc §2.4) -- systemd-repart grows it to fill whatever real disk exists
# via duduclaw-firstboot-repart.sh + usr/lib/repart.d/30-data.conf, which
# this recipe already carries via duduclaw-image-ab.bb's own IMAGE_INSTALL.
# Root-A/root-B (DUDUCLAW_AB_SLOT_SIZE_MB above) are a separate constant --
# only the staging target's own size changes here.
DUDUCLAW_AB_DATA_SIZE_MB = "8192"

# COMPATIBLE_MACHINE is inherited unchanged from duduclaw-image-ab.bb
# (genericx86-64|qemux86-64) -- no re-declaration needed (design doc §2.2).
