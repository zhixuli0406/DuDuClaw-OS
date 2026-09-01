# duduclaw-ab-dualsign-uki.bbclass — per-slot signed UKI variant (T4,
# 2026-09-02 修正案 — commercial/docs/DESIGN-os-trust-chain-2026-09.md's
# 2026-09-02 拍板紀錄 entry).
#
# WHY THIS EXISTS: Secure Boot's Authenticode signature covers the WHOLE UKI
# PE image (stub + kernel + initrd + every embedded section, `.cmdline`
# included — see crates/duduclaw-gateway/src/uki_patch.rs's own module doc,
# the same fact this class is the build-side response to). The original A/B
# design rewrote `.cmdline`'s `root=PARTUUID=` bytes ON THE DEVICE at update
# time (os_update.rs's staging step), which corrupts that signature — an
# SB-enforcing firmware refuses to load the rewritten result. The fix: stop
# rewriting, ship ONE PRE-SIGNED UKI PER SLOT instead, and let the device
# SELECT the already-correct one at staging time
# (crates/duduclaw-gateway/src/uki_patch.rs's `verify_root_partuuid`,
# `os_update.rs`'s `bind_uki_to_slot`). This is only possible now that
# root-B's own PARTUUID is ALSO a build-time constant
# (classes/duduclaw-ab-partflags.bbclass's `DUDUCLAW_AB_ROOTB_PARTUUID`) — a
# random per-build PARTUUID could never be baked into a signed artifact ahead
# of time, which is exactly why the device-side rewrite existed in the first
# place (that class's own comment has the full history).
#
# MECHANISM: hand-rolled second do_uki-shaped task, same reasoning
# classes/duduclaw-rescue-boot.bbclass's own do_uki_rescue task already
# documents (oe-core's uki.bbclass `do_uki` is not parameterized for
# multiple UKIs per recipe — fixed global UKI_FILENAME/UKI_CMDLINE vars,
# `addtask uki` can only exist once per recipe). This task's body mirrors
# do_uki's own python body (read end-to-end at the pinned oe-core commit
# before writing this — meta/classes-recipe/uki.bbclass,
# openembedded-core@5d1aa5c806c061a2994f4decb59016610f093213, the exact
# commit meta-duduclaw/kas/duduclaw-os.yml pins): identical ukify invocation
# shape, same kernel + initramfs the product UKI already embeds (no second
# kernel build, no rootfs duplication), only cmdline/output filename differ.
# UKI_SB_KEY/UKI_SB_CERT are threaded through exactly like do_uki's (and
# do_uki_rescue's) own signing block — an UNSIGNED slot-B UKI would defeat
# the entire point of this wave: the on-device selection path trusts a
# candidate BECAUSE it is independently Secure-Boot-signed, not because
# os_update.rs re-verifies anything beyond the cmdline's baked PARTUUID.
#
# NOT added to IMAGE_EFI_BOOT_FILES / the factory ESP (unlike
# duduclaw-rescue-boot.bbclass's rescue UKI, which IS meant to be selectable
# from THIS build's own boot menu): this variant's cmdline points at root-B,
# which is the empty `_empty` reserved slot on a fresh factory image —
# booting it would hang in an initrd waiting for a partition with no real
# root filesystem on it, and it would also blow the ESP sizing budget
# classes/duduclaw-ab-partflags.bbclass's own DUDUCLAW_AB_ESP_SIZE_MB
# comment already calibrated for exactly 3 simultaneous UKIs (rescue +
# slot-A/running + incoming update), not 4. This variant exists purely as a
# RELEASE ARTIFACT: it lands in DEPLOY_DIR_IMAGE like every other do_uki*
# output, and appliance/tools/make-payload.py picks it up from there to ship
# alongside the slot-A UKI in the signed update payload — a FUTURE device,
# updating INTO its own root-B, then has a pre-signed UKI matching that
# device's own (now build-time-constant) root-B PARTUUID ready to select.
# ESP occupancy is therefore UNCHANGED by this class, exactly as the design
# doc's 2026-09-02 修正案 entry states ("ESP 佔用不變，release 產物 +一顆
# UKI 體積").
#
# Consuming recipe MUST set UKI_SLOTB_CMDLINE (no generic default is
# derivable here without assuming UKI_CMDLINE's exact string shape — the
# product recipe already owns that string, see UKI_CMDLINE's own definition)
# — recipes-core/images/duduclaw-image-ab.bb sets UKI_SLOTB_CMDLINE right
# next to its own UKI_CMDLINE, for the same self-consistency reason
# DUDUCLAW_AB_ROOTA_PARTUUID vs DUDUCLAW_AB_ROOTB_PARTUUID stay side by side
# in duduclaw-ab-partflags.bbclass.
#
# NO `require conf/image-uefi.conf` here, a deliberate departure from
# duduclaw-rescue-boot.bbclass's defensive copy of that line: with THREE
# classes in the same inherit chain each require-ing the same conf
# (uki.bbclass line 72, rescue-boot, and originally this one), bitbake's
# parser emitted a "Duplicate inclusion" warning for every image recipe in
# the require chain — 29 of them per bake, drowning real warnings. The
# variables this class reads (UKIFY_CMD/EFI_ARCH/...) are guaranteed
# in-scope by uki.bbclass's own unconditional require: every consuming
# image recipe reaches this class via the duduclaw-image chain, which
# always inherits uki.bbclass first (duduclaw-image-minimal.bb), so the
# inherit-order concern rescue-boot's comment guards against cannot arise
# for this class's one real consumer (duduclaw-image-ab.bb).

UKI_SLOTB_FILENAME ?= "duduclaw-os_${DISTRO_VERSION}.slot-b.efi"
UKI_SLOTB_CMDLINE ?= ""

do_uki_slotb[depends] += " \
    systemd-boot:do_deploy \
    virtual/kernel:do_deploy \
"
do_uki_slotb[depends] += "${@ '${INITRAMFS_IMAGE}:do_image_complete' if d.getVar('INITRAMFS_IMAGE') else ''}"
do_uki_slotb[dirs] = "${B}"

python do_uki_slotb() {
    import bb.process

    cmdline = d.getVar('UKI_SLOTB_CMDLINE')
    if not cmdline:
        bb.fatal("UKI_SLOTB_CMDLINE is unset -- the consuming image recipe must define it "
                 "(see classes/duduclaw-ab-dualsign-uki.bbclass's own header comment); "
                 "refusing to bake an empty root= into a signed UKI.")

    ukify_cmd = d.getVar('UKIFY_CMD')
    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')

    target_arch = d.getVar('EFI_ARCH')
    if target_arch:
        ukify_cmd += " --efi-arch %s" % (target_arch)

    stub = "%s/linux%s.efi.stub" % (deploy_dir_image, target_arch)
    if not os.path.exists(stub):
        bb.fatal(f"ERROR: cannot find {stub}.")
    ukify_cmd += " --stub %s" % (stub)

    uki_fstype = d.getVar("INITRAMFS_FSTYPES").split()[0]
    initramfs_image = "%s-%s.%s" % (d.getVar('INITRAMFS_IMAGE'), d.getVar('MACHINE'), uki_fstype)
    ukify_cmd += " --initrd=%s" % (os.path.join(deploy_dir_image, initramfs_image))

    kernel_filename = d.getVar('UKI_KERNEL_FILENAME') or d.getVar('KERNEL_IMAGETYPE')
    if not kernel_filename:
        bb.fatal("ERROR - neither UKI_KERNEL_FILENAME nor KERNEL_IMAGETYPE is set")
    kernel = "%s/%s" % (deploy_dir_image, kernel_filename)
    if not os.path.exists(kernel):
        bb.fatal(f"ERROR: cannot find {kernel}")
    ukify_cmd += " --linux=%s" % (kernel)
    kernel_version = d.getVar('KERNEL_VERSION')
    if kernel_version:
        ukify_cmd += " --uname %s" % (kernel_version)

    ukify_cmd += " --cmdline='%s'" % (cmdline)

    # Same os-release source as oe-core's own do_uki (RECIPE_SYSROOT's real
    # /etc/os-release, NOT a hand-synthesized one like do_uki_rescue's own
    # distinguishable PRETTY_NAME) -- deliberate: unlike the rescue entry,
    # this variant is never meant to be human-distinguishable in a boot menu
    # (it never reaches one at all, see class header comment), it represents
    # the SAME product, just with a different destination slot baked in.
    ukify_cmd += " --os-release=@%s%s/lib/os-release" % \
        (d.getVar("RECIPE_SYSROOT"), d.getVar("prefix"))

    ukify_cmd += " --tools=%s%s/lib/systemd/tools" % \
        (d.getVar("RECIPE_SYSROOT_NATIVE"), d.getVar("prefix"))

    key = d.getVar('UKI_SB_KEY')
    if key:
        ukify_cmd += " --sign-kernel --secureboot-private-key='%s'" % (key)
    cert = d.getVar('UKI_SB_CERT')
    if cert:
        ukify_cmd += " --secureboot-certificate='%s'" % (cert)

    output = " --output=%s/%s" % (deploy_dir_image, d.getVar('UKI_SLOTB_FILENAME'))
    ukify_cmd += " %s" % (output)

    bb.debug(2, "uki_slotb: running command: %s" % (ukify_cmd))
    out, err = bb.process.run(ukify_cmd, shell=True)
    bb.debug(2, "%s\n%s" % (out, err))
}
addtask uki_slotb after do_uki before do_deploy do_image_complete do_image_wic
