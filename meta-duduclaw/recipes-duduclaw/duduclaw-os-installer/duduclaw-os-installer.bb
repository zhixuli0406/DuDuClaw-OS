SUMMARY = "DuDuClaw OS installer — writes the production A/B image onto the target disk"
DESCRIPTION = "Installer that runs inside the live environment \
(duduclaw-image-live) and writes the already-built, already-signed A/B disk \
image the live ISO carries as install material onto the target machine's \
internal storage (whole-disk dd + GPT backup-header relocation). Data growth \
and OOBE are the production system's own first-boot responsibility."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://duduclaw-os-install.sh"

# This pinned oe-core hard-fatals on S = "${WORKDIR}" (insane.bbclass's
# unconditional bb.fatal, not skippable via INSANE_SKIP). file:// sources
# unpack into UNPACKDIR now, not the WORKDIR root — point S there (and
# do_install reads from UNPACKDIR to match).
S = "${UNPACKDIR}"

# Runtime tools the installer shells out to:
#  - gptfdisk        → sgdisk -e (move GPT backup header to real disk end)
#  - zstd            → zstd -dc (decompress-stream the .wic.zst to disk) +
#                      zstd -lv (Y20-P3: exact decompressed byte count for
#                      DUDUCLAW_INSTALL_PROGRESS's `pv -n -s` total)
#  - parted          → partprobe (re-read partition table after write)
#  - util-linux-*    → lsblk / findmnt / blkid / blockdev / umount
#  - coreutils       → stat / du / dd / sync (busybox equivalents also work,
#                      pulled explicitly so the script's `stat -c`/`du -h`
#                      behave identically regardless of the base image's
#                      busybox config) + mkfifo (Y20-P3's progress-line
#                      bridge, POSIX sh has no process substitution)
#  - pv              → Y20-P3: numeric (`-n`) progress samples feeding
#                      DUDUCLAW_INSTALL_PROGRESS=1's `DUDUCLAW_PROGRESS:<pct>`
#                      lines (see the script's own §5 comment); a real
#                      RDEPEND now (not merely optional-if-present) so the
#                      graphical installer's determinate progress bar is a
#                      live feature of the shipped image, not something that
#                      happens to work only when pv is present.
RDEPENDS:${PN} = " \
    gptfdisk \
    zstd \
    parted \
    coreutils \
    pv \
    util-linux-lsblk \
    util-linux-findmnt \
    util-linux-blkid \
    util-linux-blockdev \
    util-linux-umount \
"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${UNPACKDIR}/duduclaw-os-install.sh ${D}${sbindir}/duduclaw-os-install
}

FILES:${PN} = "${sbindir}/duduclaw-os-install"

# Target-independent shell script; no compiled artifacts.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
