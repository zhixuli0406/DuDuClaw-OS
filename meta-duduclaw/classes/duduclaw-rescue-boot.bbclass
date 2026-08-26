# duduclaw-rescue-boot.bbclass — Entry B (實體救援開機項) boot-side mechanism.
#
# Authority: commercial/docs/DESIGN-maintenance-mode-2026-08.md §3. This
# class builds ONE extra signed UKI (a "rescue" variant of the already-built
# product UKI — same kernel + same initramfs, only the embedded kernel
# cmdline differs) and overrides wic's auto-generated loader.conf with a
# hardened one. It is the MECHANISM only: which target the rescue cmdline
# points at, the account it logs into, and the emergency/rescue.target mask
# all live in the separate `duduclaw-rescue` recipe (recipes-duduclaw/
# duduclaw-rescue/) — this class never references that recipe, so an image
# could in principle inherit just the boot-menu half without the identity
# half (kept decoupled on purpose, matching this codebase's existing
# "mechanism in a class, policy in the recipe" split, e.g. uki.bbclass vs.
# duduclaw-image.bb's own UKI_CMDLINE).
#
# ---------------------------------------------------------------------
# Why a hand-written second do_uki-shaped task, not a second `inherit uki`:
# uki.bbclass's own `do_uki` task (meta/classes-recipe/uki.bbclass at the
# pinned oe-core commit — see meta-duduclaw/kas/duduclaw-os.yml for the exact
# hash) is not parameterized for multiple UKIs per recipe: fixed global
# UKI_FILENAME/UKI_CMDLINE vars, `addtask uki` can only exist once per
# recipe. This task mirrors do_uki's own python body (identical ukify
# invocation shape, read end-to-end before writing this) with an
# independent cmdline/filename pair, so the SAME kernel+initramfs the
# product UKI already embeds gets a second, differently-labelled signed
# entry — no second kernel build, no rootfs duplication, no new initramfs.
# ---------------------------------------------------------------------

require conf/image-uefi.conf

UKI_RESCUE_FILENAME ?= "duduclaw-os-rescue.efi"

# `systemd.unit=NAME` is a real, documented kernel-command-line override
# (systemd's kernel-command-line(7): overrides default.target for that ONE
# boot only) — chosen over a home-grown `duduclaw.rescue=1` flag + a
# systemd-generator target-switch scheme because the TARGET-SELECTION half
# of Entry B then needs zero extra generator code. The GETTY-MASKING half
# still needs its own unit design, but that half never depended on
# cmdline-flag parsing to begin with — duduclaw-rescue.target simply never
# appears in the normal boot graph, so nothing needs to conditionally
# unmask anything (see that recipe's own header comment for the full
# reasoning, including why this sidesteps the /etc-vs-/run unit-search-path
# precedence problem a mask-then-conditionally-unmask generator design
# would have hit).
UKI_RESCUE_CMDLINE ?= "${UKI_CMDLINE} systemd.unit=duduclaw-rescue.target"

# Distinguishable os-release PRETTY_NAME so a person who reveals the
# (hidden-by-default — see DUDUCLAW_LOADER_CONF_SRC below) systemd-boot
# menu can actually tell the rescue entry apart from the normal A/B entry.
# `ukify --os-release=@file` accepts any NAME=VALUE file; it does not have
# to be the real target /etc/os-release.
UKI_RESCUE_OS_RELEASE_ID ?= "duduclaw-os-rescue"
UKI_RESCUE_OS_RELEASE_NAME ?= "DuDuClaw Rescue Mode (Entry B)"

# The hardened loader.conf this class expects the CONSUMING recipe to have
# already fetched into WORKDIR via its own SRC_URI (see duduclaw-image.bb's
# "file://duduclaw-loader.conf" entry + the accompanying comment for the
# exact content and the `editor no` gap it closes). Overridable per-image if
# a future image wants a different filename; the class only cares that
# *some* file by this name exists in WORKDIR by the time do_unpack finishes.
DUDUCLAW_LOADER_CONF_SRC ?= "duduclaw-loader.conf"

# --- Second signed UKI ---------------------------------------------------

do_uki_rescue[depends] += " \
    systemd-boot:do_deploy \
    virtual/kernel:do_deploy \
"
do_uki_rescue[depends] += "${@ '${INITRAMFS_IMAGE}:do_image_complete' if d.getVar('INITRAMFS_IMAGE') else ''}"
do_uki_rescue[dirs] = "${B}"

python do_uki_rescue() {
    import bb.process

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

    cmdline = d.getVar('UKI_RESCUE_CMDLINE')
    ukify_cmd += " --cmdline='%s'" % (cmdline)

    # Distinguishable os-release for the rescue entry's own menu label —
    # see class header comment.
    rescue_os_release = "%s/duduclaw-rescue-os-release" % (d.getVar('B'))
    with open(rescue_os_release, 'w') as f:
        f.write('ID=%s\n' % d.getVar('UKI_RESCUE_OS_RELEASE_ID'))
        f.write('NAME="%s"\n' % d.getVar('UKI_RESCUE_OS_RELEASE_NAME'))
        f.write('PRETTY_NAME="%s"\n' % d.getVar('UKI_RESCUE_OS_RELEASE_NAME'))
    ukify_cmd += " --os-release=@%s" % (rescue_os_release)

    ukify_cmd += " --tools=%s%s/lib/systemd/tools" % \
        (d.getVar("RECIPE_SYSROOT_NATIVE"), d.getVar("prefix"))

    key = d.getVar('UKI_SB_KEY')
    if key:
        ukify_cmd += " --sign-kernel --secureboot-private-key='%s'" % (key)
    cert = d.getVar('UKI_SB_CERT')
    if cert:
        ukify_cmd += " --secureboot-certificate='%s'" % (cert)

    output = " --output=%s/%s" % (deploy_dir_image, d.getVar('UKI_RESCUE_FILENAME'))
    ukify_cmd += " %s" % (output)

    bb.debug(2, "uki_rescue: running command: %s" % (ukify_cmd))
    out, err = bb.process.run(ukify_cmd, shell=True)
    bb.debug(2, "%s\n%s" % (out, err))
}
addtask uki_rescue after do_uki before do_deploy do_image_complete do_image_wic

# --- Hardened loader.conf, installed straight into DEPLOY_DIR_IMAGE ------
#
# Needs to land in DEPLOY_DIR_IMAGE (not just WORKDIR) because wic's own
# src-path resolution for IMAGE_EFI_BOOT_FILES entries is DEPLOY_DIR_IMAGE-
# relative (verified below), the same place do_uki/do_uki_rescue already
# write their UKIs — no do_install/do_package involved, matching uki.bbclass's
# own already-established convention in this codebase.
do_deploy_duduclaw_loader_conf[dirs] = "${DEPLOY_DIR_IMAGE}"
do_deploy_duduclaw_loader_conf() {
	# ${UNPACKDIR}, not ${WORKDIR} -- this release's do_unpack places
	# fetched SRC_URI file:// sources into a distinct UNPACKDIR
	# subdirectory (confirmed live: a first attempt using ${WORKDIR} here
	# failed with "install: cannot stat .../duduclaw-loader.conf: No such
	# file or directory"; duduclaw-shell's own recipe already relies on
	# ${UNPACKDIR} for its own fetched file:// units, e.g.
	# "install -m 0644 ${UNPACKDIR}/duduclaw-kiosk.service ..." -- same
	# fix, already-proven convention in this exact layer).
	install -m 0644 "${UNPACKDIR}/${DUDUCLAW_LOADER_CONF_SRC}" "${DEPLOY_DIR_IMAGE}/${DUDUCLAW_LOADER_CONF_SRC}"
}
addtask deploy_duduclaw_loader_conf after do_unpack before do_image_wic

# --- Wire both files into the ESP via IMAGE_EFI_BOOT_FILES ---------------
#
# Verified 2026-08-26 against wic's own bootimg-efi.py source (WebFetch
# against the GitHub mirror of the upstream `git.yoctoproject.org/wic` tree
# — git.yoctoproject.org's own cgit blocks automated fetches — not guessed):
#
#   - do_configure_partition() runs FIRST and calls do_configure_systemdboot(),
#     which ALWAYS writes an auto-generated loader.conf
#     ("default boot\n"-if-not-unified-image + "timeout <wks bootloader
#     --timeout>\n") with NO bitbake-variable hook for anything else — in
#     particular there is no way to add `editor no` through that code path
#     at all, at any version of this wks/wic combination.
#   - do_prepare_partition() runs AFTER and installs every
#     IMAGE_EFI_BOOT_FILES "src;dst" pair via a plain OVERWRITING
#     `install -m 0644 -D <DEPLOY_DIR_IMAGE>/<src> <hdddir>/<dst>` (exact
#     quoted source: `for src_path, dst_path in cls.install_task: ...
#     os.path.join(kernel_dir, src_path)`, kernel_dir defaulting to
#     DEPLOY_DIR_IMAGE).
#
# So listing our own loader.conf here with dst `loader/loader.conf`
# deterministically wins over wic's own generated file, using an
# already-supported bitbake variable rather than patching the wic tool or
# post-processing the finished .wic image with mtools/`wic cp`.
IMAGE_EFI_BOOT_FILES:append = " ${DUDUCLAW_LOADER_CONF_SRC};loader/loader.conf ${UKI_RESCUE_FILENAME};EFI/Linux/${UKI_RESCUE_FILENAME}"
