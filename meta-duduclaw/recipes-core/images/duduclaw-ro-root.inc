# DuDuClaw OS — read-only root (VER-RO, P1 Wave, 2026-09-02).
#
# Authority: commercial/docs/DESIGN-os-trust-chain-2026-09.md "依賴鏈補記"
# (2026-09-02): dm-verity (P2 拍板組 T4, still ahead) physically requires
# root to be unwriteable — verity's own hash-tree check only holds if
# nothing ever writes the protected block device out from under it. This
# `.inc` is the VER-RO sub-wave itself: flip root `ro` at the kernel
# cmdline level and carry every bind-mount this wave's own plenary
# write-point survey found necessary (recipes-duduclaw/duduclaw-data-binds/)
# so the OS still boots to a fully healthy state with root genuinely
# read-only, BEFORE dm-verity's own hash-tree machinery is attempted on
# top of it — dm-verity on a root nothing has proven can survive being
# read-only would just convert every one of these gaps into a hard boot
# failure instead of a diagnosable one.
#
# ROLLOUT GATING (deliberate, matches this ticket's own instructions):
# ONLY duduclaw-image-appliance-test.bb `require`s this file this round.
# duduclaw-image-appliance.bb — the actual shipping target
# (release-os.sh's own DEFAULT_IMAGE) — does NOT, on purpose: this is a
# real behavior change (root becomes unwriteable) that needs a real QEMU
# boot + this wave's own harness (private_scratch/os-security-harness/
# wavero.py, RO1-RO6) to go green before it is safe to promote onto the
# image real hardware actually ships. Promote by adding the identical
# `require recipes-core/images/duduclaw-ro-root.inc` line to
# duduclaw-image-appliance.bb once that harness passes — do not duplicate
# this file's content into that recipe instead, for the same "one already-
# verified step never re-edits the previous one" reasoning this whole
# image-recipe chain already follows throughout (see e.g.
# duduclaw-image-ab.bb's own header).
#
# WHY A DEDICATED `.inc`, NOT INLINE IN duduclaw-image-appliance-test.bb:
# matches this layer's own established shape for "a payload/behavior axis
# that more than one image recipe might eventually want" (duduclaw-image-
# flatpak.inc / duduclaw-image-data.inc / duduclaw-image-desktop.inc) —
# the day duduclaw-image-appliance.bb is ready to promote, it is a
# one-line `require`, not a diff against this file's own content.
#
# WHAT THIS FILE DOES NOT DO, ON PURPOSE (scope boundary, not an
# oversight):
#   - No oe-core `read-only-rootfs` IMAGE_FEATURE. Investigated (that
#     feature bundles opkg/rpm "delayed postinsts" scriptlet handling this
#     distro has zero use for — this line ships one immutable rootfs per
#     build, no runtime package manager at all, no postinst-at-first-
#     writable-boot story to defer) and a few rootfs-postcommands hooks
#     (e.g. `read_only_rootfs_hook` mangles /etc/resolv.conf and a few
#     opkg-specific paths this distro's own network-config recipe already
#     owns differently) that are either no-ops or would fight this
#     project's own established config recipes rather than help them.
#     Explicit, minimal mechanism (cmdline `ro` + this project's own
#     bind-mount recipe) was judged the better fit than inheriting an
#     IMAGE_FEATURE bundle designed around a different (opkg/rpm-managed,
#     runtime-mutable) class of Yocto image. Revisit if a future round
#     finds a specific sub-mechanism of that feature worth adopting on its
#     own — nothing here blocks cherry-picking one piece of it later.
#   - No dm-verity. That is DESIGN-os-trust-chain-2026-09.md T4's own
#     scope, explicitly sequenced AFTER this sub-wave goes green (see that
#     design doc's "依賴鏈補記" for the exact dependency this file exists
#     to satisfy).
#   - No /etc/machine-id / systemd-machine-id-commit.service handling —
#     already correctly handled by oe-core's own stock behavior with zero
#     action needed here; see duduclaw-data-binds.bb's own header for the
#     one-hand evidence (rootfs-postcommands.bbclass::
#     systemd_handle_machine_id()). Cross-reboot machine-id STABILITY (the
#     one known residual this bullet used to flag as separately-tracked)
#     is fixed by recipes-core/initrdscripts/
#     initramfs-module-duduclaw-persist (VER-P, 2026-09-03) — an initrd
#     module, not anything in THIS file, since the fix has to land before
#     PID 1 ever reads /etc/machine-id (see that module's own header for
#     the full "why an initrd module, not a main-system service"
#     reasoning). This file's own duduclaw_ro_root_hook() below is
#     unaffected either way — it still ships the same empty /etc/
#     machine-id oe-core always did; VER-P's own module is what makes the
#     TRANSIENT bind systemd performs against that empty file draw from a
#     persisted value instead of a fresh-random one each boot.
#
# `ro` on the kernel cmdline — VERIFIED against this line's own initrd,
# not assumed from generic Linux convention: this image's UKI carries
# initramfs-framework (no systemd in the initrd — see the design doc's own
# "依賴鏈補記" for why that also shapes the eventual dm-verity mechanism),
# and its `rootfs` module (openembedded-core/meta/recipes-core/
# initrdscripts/initramfs-framework/rootfs, read directly at this line's
# pinned oe-core commit) explicitly parses `$bootparam_ro` off
# /proc/cmdline and folds it into the `mount -o<rootflags>` invocation that
# actually mounts root — i.e. this is initramfs-framework's own supported,
# already-wired mechanism, not something this ticket bolts on. Nothing in
# this initrd's own `finish` module (the switch_root step) or in any unit
# this layer ships remounts root rw afterward (grepped this layer for
# `remount,rw`/`remount rw` — zero hits) — matching oe-core's own
# `read-only-rootfs` IMAGE_FEATURE's identical premise (this file just
# does not need that feature's OTHER, opkg/rpm-oriented behavior to get
# this one part of it).
#
# `:append`, not a redefining `=` copy of duduclaw-image-ab.bb's own
# UKI_CMDLINE value: append-vs-override matters here specifically because
# a concurrent P1 SB (Secure Boot) wave is also actively editing UKI/
# cmdline-adjacent files this same day (591ab022/0883491c, `git log`
# checked before writing this file) — an `:append` composes with whatever
# UKI_CMDLINE resolves to by the time bitbake finishes evaluating every
# `+=`/`.bbappend`/`:append` in the build (bitbake operators apply AFTER
# all plain `=` assignments regardless of file order), so this line cannot
# silently clobber or race a same-day edit to the base string the way a
# second `UKI_CMDLINE = "..."` copy-with-appended-ro would. The base
# cmdline (duduclaw-image-ab.bb) carries no `ro`/`rw` token today (checked
# by reading that file directly this round), so this append introduces the
# token cleanly with no duplicate/conflicting flag.
UKI_CMDLINE:append = " ro"

# --- Why cmdline `ro` alone was NOT enough (first QEMU round, 2026-09-02,
# verprobe evidence — real boot, not theory): initramfs-framework's rootfs
# module DID mount root ro (its $bootparam_ro handling, verified above),
# and the guest still ended up `rw,relatime` with a failed journal bind.
# Two independent root causes, both fixed in duduclaw_ro_root_hook below:
#
#   (1) base-files' stock /etc/fstab ships `/dev/root / auto defaults 1 1`
#       — systemd-remount-fs.service faithfully applies it and remounts /
#       rw a few seconds into every boot, silently undoing the initramfs's
#       ro mount. This is the exact line oe-core's own
#       read_only_rootfs_hook (rootfs-postcommands.bbclass:199) seds for
#       its read-only-rootfs IMAGE_FEATURE; this file's own header already
#       documents why that whole feature is not inherited — so the one
#       relevant piece of it is reproduced here, scoped to this image.
#   (2) /var/log is a SYMLINK to /var/volatile/log on a stock build
#       (base-files VOLATILE_LOG_DIR default) — systemd refuses to operate
#       a .mount unit on a non-canonical path ("Mount path /var/log/journal
#       is not canonical (contains a symlink)", verbatim from the failed
#       boot's own journal), which cascaded into journald itself being
#       down (RequiredBy=) for the whole boot. Converting /var/log into a
#       real (empty, root-owned) directory makes the bind target canonical
#       AND fixes a latent WS-3/B2 defect discovered by the same probe:
#       "persistent" journal storage aimed at a tmpfs-backed symlink was
#       never actually persistent across reboots. The runtime writability
#       of /var/log under ro root is provided by duduclaw-data-binds'
#       var-log.mount (bind from /data/system/log), not by this hook.
duduclaw_ro_root_hook () {
    # (0) /data mountpoint. Round-2 QEMU evidence (verbatim journal):
    # "data.mount: Failed to create mount point '/data', ignoring:
    # Read-only file system" — the rootfs never shipped a /data directory
    # at all; on every previous (rw-root) boot systemd silently mkdir'd it
    # at mount time, masking the gap since the day the A/B layout landed.
    # With / genuinely ro that auto-create fails, data.mount fails, and
    # everything Requires=data.mount (the whole VER-RO bind chain,
    # journald included) collapses behind it.
    install -d -m 0755 ${IMAGE_ROOTFS}/data
    # (1) fstab: / must never be remounted rw by systemd-remount-fs.
    sed -i -e '/^[[:space:]]*\/dev\/root/{s/defaults/ro/}' ${IMAGE_ROOTFS}/etc/fstab
    # (2) /var/log: symlink -> real directory (canonical bind target).
    if [ -L ${IMAGE_ROOTFS}/var/log ]; then
        rm ${IMAGE_ROOTFS}/var/log
        install -d -m 0755 ${IMAGE_ROOTFS}/var/log
    fi
    # (2b) /etc/iwd: iwd's upstream unit declares ConfigurationDirectory=iwd,
    # which makes systemd CREATE /etc/iwd at service spawn when missing —
    # round-5 QEMU autopsy verbatim: "iwd.service: Failed at step
    # CONFIGURATION_DIRECTORY spawning /usr/libexec/iwd: Read-only file
    # system". Baking the directory into the image makes the create a
    # no-op (systemd only mkdirs when absent). NOTE the failure class:
    # ANY unit with ConfigurationDirectory= (mkdir target /etc) has the
    # same landmine on ro root — iwd is the only one this wave's QEMU
    # rounds surfaced; grep unit files for ConfigurationDirectory= if a
    # future service joins the image and fails the same way.
    install -d -m 0755 ${IMAGE_ROOTFS}${sysconfdir}/iwd
    # (3) systemd-random-seed writes /var/lib/systemd/random-seed and
    # FAILS (oneshot, non-degradable) on a read-only fs. Masked rather
    # than bind-mounting /var/lib/systemd wholesale: a bind would hide the
    # shipped journal message catalog under an empty /data directory and
    # add one more very-early-boot ordering edge for marginal benefit —
    # the 6.18 kernel's own entropy sources (RDRAND + jitter) make the
    # carried-over seed an optimization, not a correctness requirement.
    #
    # STATUS (2026-09-03, VER-P — 信任鏈 P1 殘項): this mask STAYS exactly
    # as it was (unmasking systemd-random-seed.service itself was
    # considered and rejected — its own path is hard-coded to
    # /var/lib/systemd/random-seed, with no equivalent on a read-only root
    # short of the same wholesale-bind cost this comment already rejects
    # above). Cross-reboot seed persistence is no longer silently dropped
    # though — it is now handled by TWO cooperating pieces OUTSIDE this
    # file entirely, which together REPLACE what
    # systemd-random-seed.service would have done: (a)
    # recipes-core/initrdscripts/initramfs-module-duduclaw-persist loads a
    # persisted seed from /data/duduclaw/system/random-seed into
    # /dev/urandom during the initrd, before this masked unit would ever
    # have had a chance to run anyway; (b)
    # recipes-duduclaw/duduclaw-persist-seed's own
    # duduclaw-persist-seed.service refreshes that seed file on /data
    # (ExecStart at multi-user.target, ExecStop at shutdown) so the NEXT
    # boot has something new to load. Both pulled in via this same file's
    # own IMAGE_INSTALL:append below, alongside duduclaw-data-binds — same
    # rollout gating, same "only duduclaw-image-appliance-test.bb today"
    # scope.
    ln -sf /dev/null ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/systemd-random-seed.service
}
ROOTFS_POSTPROCESS_COMMAND += "duduclaw_ro_root_hook; "

# Same token for the slot-B UKI variant (VER-0's duduclaw-ab-dualsign-uki
# .bbclass, landed the same day): UKI_SLOTB_CMDLINE is a SEPARATE variable
# (deliberately not derived from UKI_CMDLINE — see that bbclass's own
# header), so the append above does not reach it. Without this line a
# device that updates INTO slot B would boot its root rw again, silently
# undoing this whole wave's guarantee on exactly half the fleet's boots.
UKI_SLOTB_CMDLINE:append = " ro"

# duduclaw-data-binds (recipes-duduclaw/duduclaw-data-binds/): the bind
# mounts + tmpfiles source-directory provisioning this wave's own plenary
# write-point survey found necessary for the OS to stay fully healthy with
# `ro` above actually in effect — see that recipe's own header for the
# full evidence trail per bind target (journal/iwd/docker/waydroid) and
# what was deliberately left out of it (flatpak-verify fixed directly in
# its own recipe).
#
# duduclaw-persist-seed (recipes-duduclaw/duduclaw-persist-seed/): the
# main-system half of VER-P's cross-reboot entropy-seed persistence (see
# this file's own duduclaw_ro_root_hook() comment, item (3), above for the
# full writeup) — the initrd half
# (initramfs-module-duduclaw-persist) is wired separately, via
# recipes-core/images/core-image-minimal-initramfs.bbappend, since it
# ships inside the initramfs cpio, not this rootfs image. Same rollout
# gating as duduclaw-data-binds (only duduclaw-image-appliance-test.bb
# requires this .inc today).
IMAGE_INSTALL:append = " duduclaw-data-binds duduclaw-persist-seed"
