# DuDuClaw OS — Y2-1 product image (five duduclaw-* Rust binaries on top of
# the Y1-1 minimal bring-up base).
#
# Extends duduclaw-image-minimal.bb via `require` (not a copy/paste) so the
# already-verified UKI/systemd-boot/QEMU boot contract from Y1-1 stays a
# single source of truth — this recipe only adds the Rust payload + its
# verification-time login affordance on top.

SUMMARY = "DuDuClaw OS product image (Y2-1) -- duduclaw-sysd + duduclaw payload"
DESCRIPTION = "${SUMMARY}. Built on the Y1-1 minimal image; adds whichever \
of the five duduclaw-* Rust binaries have a working Yocto recipe so far \
(see meta-duduclaw/recipes-duduclaw/*/PLAN.md and the Y2-1 handoff notes \
for per-binary status -- this image recipe only lists what actually \
builds, never speculative IMAGE_INSTALL entries for unfinished recipes)."
LICENSE = "MIT"

require recipes-core/images/duduclaw-image-minimal.bb

# Bring-up/verification-only: lets `root` log in on the serial console with
# no password so the QEMU dual-verification (sysd socket + gateway
# /healthz) in the Y2-1 handoff notes can actually run shell commands
# without provisioning a real user/SSH-key story first (that's separate,
# later product-layer work -- appliance/'s Debian line already has a real
# firstboot-provision flow to model it on, see appliance/mkosi.extra/usr/
# local/sbin/duduclaw-firstboot-provision.sh). MUST NOT ship with this on;
# tracked as an explicit TODO in the Y2-1 handoff, not silently dropped.
#
# `debug-tweaks` (the older Yocto convenience shorthand for this) is NOT a
# valid IMAGE_FEATURE on this release -- caught by actually running bitbake
# ("'debug-tweaks' in IMAGE_FEATURES is not a valid image feature", full
# valid list printed in the error). `serial-autologin-root` is this
# release's own explicit feature for exactly this bring-up need (auto-login
# root on the serial getty, no password prompt at all -- simpler than
# combining allow-root-login+empty-root-password+allow-empty-password).
#
# Y2-3 (2026-08-25) fix: `serial-autologin-root` alone does NOT work --
# read rootfs-postcommands.bbclass's own serial_autologin_root() gate
# directly (`bb.utils.contains("IMAGE_FEATURES", ['empty-root-password',
# 'serial-autologin-root'], ...)`, a list-form contains(), which requires
# ALL listed features present, not just this one). Without
# `empty-root-password` too, the getty autologin sed patch is silently
# skipped and the serial console falls back to a normal login prompt PAM
# would then reject anyway (no password set on root at all in
# core-image-minimal). Caught by reading the class before burning a boot
# cycle on a login prompt this recipe's own comment claimed didn't exist.
#
# WS-3/A1 (2026-09-01, DESIGN-os-security-line-2026-09.md §2 支柱一 A1):
# this line used to be an unconditional `+=`, which meant EVERY image that
# `require`s this file -- not just duduclaw-image itself, but
# duduclaw-image-data.bb / duduclaw-image-ab.bb / duduclaw-image-flatpak.bb
# and (transitively, through -ab.bb) duduclaw-image-appliance.bb -- shipped
# root-serial-autologin-with-no-password by default, with only
# duduclaw-image-appliance.bb's own IMAGE_FEATURES:remove (below this
# file's require chain) turning it back off again for THAT one image. The
# comment directly above already says "MUST NOT ship with this on"; the
# unconditional `+=` contradicted its own comment for every OTHER image in
# the require chain (duduclaw-image-flatpak.bb in particular has no
# removal step at all -- confirmed by reading it, see its own header note
# added the same day). Fixed at the root of the inheritance tree instead of
# patching each downstream image separately: this now mirrors
# duduclaw-image-appliance.bb's own DUDUCLAW_IMAGE_TEST_LOGIN gate
# (inverted -- ADD only when the var is "1", vs. that file's REMOVE only
# when it's not "1"), sharing the exact same variable name and semantics so
# a single `DUDUCLAW_IMAGE_TEST_LOGIN=1` (local.conf or `bitbake -D`) still
# lights up serial autologin end to end for manual QEMU verification of
# ANY image in this chain, and duduclaw-image-appliance-test.bb's existing
# `DUDUCLAW_IMAGE_TEST_LOGIN = "1"` (set before its own require chain
# reaches this file) needs zero changes to keep working -- verified by
# inspection of bitbake's require-is-textual-inline + `?=`-only-sets-once
# semantics, NOT by an actual build (this ticket is recipe-only, no
# bitbake run). Default "0" (nothing has set the var yet at this point in
# the require chain for every other image) yields IMAGE_FEATURES with
# neither token, matching duduclaw-image-appliance.bb's own "MUST NOT ship"
# intent for the whole tree, not just the one image that used to bother
# removing it again downstream. duduclaw-image-appliance.bb's own
# IMAGE_FEATURES:remove (unedited by this fix) becomes a no-op most of the
# time now (removing a token nothing added) but is deliberately left in
# place as defense-in-depth against a future recipe re-adding the tokens
# between here and there in the require chain.
#
# duduclaw-image-live.bb is NOT affected by this change -- verified by
# reading it (recipes-core/images/duduclaw-image-live.bb): it `require`s
# core-image-minimal.bb directly, never this file, and carries its own,
# independently-declared `IMAGE_FEATURES += "allow-empty-password
# allow-root-login empty-root-password serial-autologin-root"` for its own
# disposable, unsigned, not-part-of-the-trust-chain live-installer
# environment (that recipe's own header: "not the trusted production
# system"). Its root-shell story is unconditional serial autologin from
# core-image-minimal upward, same as always; the live wizard's kiosk
# session identity (duduclaw-live-tweaks' `User=root` drop-in) is a
# SEPARATE, unrelated mechanism for the graphical Wayland kiosk surface,
# not the serial console this A1 change touches -- the two never intersect
# in this recipe's require chain, so the live installer wizard is
# unaffected by this fix regardless of which mechanism is asked about.
DUDUCLAW_IMAGE_TEST_LOGIN ?= "0"
IMAGE_FEATURES += "${@'serial-autologin-root empty-root-password' if d.getVar('DUDUCLAW_IMAGE_TEST_LOGIN') == '1' else ''}"

# Y2-3 (2026-08-25) fix: this list was missing duduclaw-cli, the package
# that actually installs /usr/bin/duduclaw (and duduclaw-gateway.service,
# which execs it) -- duduclaw-sysd alone cannot satisfy this milestone's
# QEMU dual-verification (sysd socket + gateway /healthz), since there was
# no gateway binary in the image to begin with. Caught by actually trying
# the boot verification, not by re-reading the recipe.
IMAGE_INSTALL:append = " duduclaw-sysd duduclaw-cli"

# --- Desktop stack (Y3-1/Y3-8/Y5-4/Y6-1/Y7-1/Y7-3, Y20-P4 consolidation) --
# comp/shell/mesa/vulkan/xkb + fcitx5 IME + PipeWire/WirePlumber audio +
# kernel-modules + (Y20-P4) the Japanese CJK fallback font — extracted into
# a shared .inc so `duduclaw-image-live.bb`'s own live-installer
# environment stops carrying a byte-for-byte COPY of these same five
# blocks (see that recipe's own Y20-P1 header, which named this exact
# extraction as an explicit P4 deferral). Every individual package's own
# "why" (real boot panics, real QEMU verification gaps) lives in the .inc
# itself now, not duplicated here.
require recipes-core/images/duduclaw-image-desktop.inc

# --- Network: Wi-Fi via iwd + systemd-networkd (Y7-3, 2026-08-26) ---------
# Closes REAL-HW-CHECKLIST.md §5's honest gap: this image previously had
# firmware blobs (Y2-2's linux-firmware-iwlwifi/-mediatek/-rtl-nic, machine
# .conf) and kernel drivers (Y2-2's duduclaw-{n305,8845hs}.cfg fragments)
# but NO userspace connection-management stack at all -- a Wi-Fi-capable
# kernel with nothing able to actually join a network. Ports the Debian
# appliance line's D4a-1 decision (DESIGN-network-settings-2026-08.md §2,
# decision A-①: iwd + systemd-networkd over NetworkManager + wpa_supplicant,
# measured there at 12.6x less resident memory and 2 packages vs 12) onto
# this Yocto image -- `iwd` resolves from meta-oe (recipes-connectivity/
# iwd/iwd_3.12.bb, one-hand-verified present at the pinned meta-openembedded
# commit, see kas/duduclaw-os.yml), no new layer needed for it.
#
# duduclaw-network-config (this layer's own small recipe, recipes-
# connectivity/duduclaw-network-config/) carries the matching
# 25-wireless-dhcp.network drop-in and RDEPENDS on iwd +
# wireless-regdb-static -- see that recipe's own header for why
# `wireless-regdb-static`, not bare `wireless-regdb`, is the package this
# kernel actually needs (an OE package split with no Debian equivalent).
#
# gateway's D-Bus client for iwd (crates/duduclaw-gateway/src/network/
# iwd.rs, from the Debian line's D4a-3) needs ZERO Yocto-side changes --
# confirmed byte-identical between crates/ and this recipe's own vendored
# duduclaw-cli-src/ snapshot before this ticket touched anything, so the
# same binary that already speaks iwd's D-Bus API on the Debian line speaks
# it here too, the moment iwd itself is actually on the image.
#
# NO netdev group / SupplementaryGroups wiring, and this is a REAL
# divergence from the Debian line's D4a-1, not an oversight: the Debian
# line needed `netdev` because ITS gateway runs as an unprivileged
# `duduclaw` service user (appliance/mkosi.extra's gateway unit, `User=
# duduclaw`) and iwd's D-Bus policy denies everyone except root/sudo/netdev
# by default. THIS image's duduclaw-gateway.service (duduclaw-cli's own
# recipe, files/duduclaw-gateway.service) has no `User=` line at all -- it
# runs as root, per this Yocto product line's own Y2-1 bring-up decision
# ("this Yocto image doesn't provision a non-root service user ... yet").
# Root already clears any sane default-deny D-Bus policy's root/sudo hole
# with no group membership needed, so the whole netdev mechanism the Debian
# line built is currently a no-op HERE. NOT independently verified against
# the exact D-Bus policy file iwd's upstream tarball installs (unlike the
# Debian line's own iwd .deb, which is confirmed to patch in a `netdev`
# policy stanza) -- flagged rather than assumed, and this comment is the
# marker to revisit the moment this Yocto line's gateway ever moves to an
# unprivileged service user (matching the Debian line's own architecture),
# at which point the D4a-1 netdev machinery needs porting for real.
#
# Firmware is NOT repeated here -- already on the machine (duduclaw-
# genericx86-64.conf's MACHINE_EXTRA_RRECOMMENDS, Y2-2) and does not need a
# duduclaw-qemux86-64 equivalent (QEMU has no real Wi-Fi radio to load
# firmware for at all; this ticket's own QEMU verification is therefore
# necessarily limited to "iwd daemon runs + D-Bus service registers +
# gateway's iwd.rs gets a real, non-error 'no adapter' answer instead of
# erroring out", NOT "a real network associates" -- that half needs the
# real N305/8845HS hardware, same honest limit REAL-HW-CHECKLIST.md already
# states for the Debian line's own equivalent).
IMAGE_INSTALL:append = " iwd wireless-regdb-static duduclaw-network-config"

# (PipeWire/WirePlumber audio + the kernel-modules umbrella both moved into
# `duduclaw-image-desktop.inc`, `require`d above — see this file's own
# "Desktop stack" comment block for why, and that .inc for each package's
# full rationale, unchanged from before this Y20-P4 extraction.)

# --- Entry B: 實體救援開機項 (Y7-2, 2026-08-26) ---------------------------
# Authority: commercial/docs/DESIGN-maintenance-mode-2026-08.md §3 — the
# Yocto-line-specific rescue boot entry, dependent on the sd-boot menu
# mechanism (DRAFT-no-linux-surface-2026-08.md item 4) which this ticket
# also realizes on this line for the first time (no loader.conf existed
# on this line before this ticket at all — wic's own auto-generated
# default was silently in effect, see duduclaw-rescue-boot.bbclass's own
# header for the exact finding).
#
# `duduclaw-rescue-boot` (meta-duduclaw/classes/) is the MECHANISM: builds
# a second signed UKI (same kernel+initramfs as the product UKI, cmdline
# `systemd.unit=duduclaw-rescue.target`) and overrides wic's own
# auto-generated loader.conf with a hardened one (`timeout 0` + `editor
# no` — the `editor no` line is a real gap this ticket found and closed,
# see that class's own comment and the fetched loader.conf file's header
# for the systemd upstream documentation evidence).
#
# `duduclaw-rescue` (recipes-duduclaw/duduclaw-rescue/) is the POLICY: the
# target itself, its diagnostic-shell/audit/root-lock units, the
# restricted non-root autologin account, and the emergency.target/
# rescue.target mask — see that recipe's own header for the full
# identity-model decision record (§3.3 option (a) chosen over (b)) and the
# DRAFT item 5 (emergency.target) mask decision.
inherit duduclaw-rescue-boot

# Y7-1 (2026-08-26) real parse-time fix, hit while rebuilding
# duduclaw-image-flatpak (this ticket's own deliverable, which `require`s
# this file): "Unable to get checksum for duduclaw-image-flatpak SRC_URI
# entry duduclaw-loader.conf: file could not be found" -- bitbake's default
# FILESPATH is computed from the OUTERMOST recipe's PN/BPN (whichever .bb
# file bitbake was actually asked to build), not the PN of whichever file a
# `require`d snippet happens to live in; Y7-2's own `bitbake duduclaw-image`
# runs never hit this because there PN really is `duduclaw-image` and the
# default `${THISDIR}/duduclaw-image/` search entry already covers it --
# only a *different* top-level recipe requiring this one (duduclaw-image-
# flatpak.bb) exposes the gap. Explicit FILESEXTRAPATHS makes the lookup
# PN-independent, matching the fix's own file (still `duduclaw-image/
# duduclaw-loader.conf`, untouched -- this only adds a search path, it does
# not move/rename Y7-2's file).
FILESEXTRAPATHS:prepend := "${THISDIR}/duduclaw-image:"

SRC_URI += "file://duduclaw-loader.conf"

IMAGE_INSTALL:append = " duduclaw-rescue"

# WS-3/B2 (2026-09-01, DESIGN-os-security-line-2026-09.md §2 支柱二 B2 /
# G17: "journald 現況零配置"). Added at this base level, not scoped to the
# appliance payload the way A4's firewall was (that recipe's own comment
# in duduclaw-image-appliance.bb explains the different reasoning) --
# journald hardening is a base-OS-service default every image in this
# require chain should carry, the same "push the safe default to the
# root of the inheritance tree" reasoning this file's own A1 fix (above)
# already established for IMAGE_FEATURES, and matching duduclaw-rescue's
# own placement one line up. See recipes-duduclaw/duduclaw-journald/
# files/duduclaw.conf for the full per-directive reasoning and the one
# known limitation (journal not yet bound onto /data).
IMAGE_INSTALL:append = " duduclaw-journald"

# WS-3/自掃 timer (2026-09-01, DESIGN-os-security-line-2026-09.md §2
# secaudit 遷入 D2' / 拍板 D4). Same base-level placement reasoning as
# duduclaw-journald immediately above -- ConditionPathExists=/data/duduclaw
# in the .service unit itself (recipes-duduclaw/duduclaw-secaudit-scan/)
# makes this a clean no-op on the bare bring-up image, which has no /data
# partition to scan.
IMAGE_INSTALL:append = " duduclaw-secaudit-scan"
