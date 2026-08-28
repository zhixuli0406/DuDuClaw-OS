# DuDuClaw OS — Y18 live-ISO initramfs (2026-08-28).
#
# This is a DELIBERATELY SEPARATE initramfs from core-image-minimal-initramfs
# (the one duduclaw-image-minimal.bb / duduclaw-image-ab.bb use for the real
# UKI+systemd-boot A/B boot chain). Do not merge them. The two have opposite
# requirements around the same package:
#
#   - core-image-minimal-initramfs (production A/B boot): walks
#     initramfs-framework's own device-scan + LABEL/PARTUUID logic to find
#     root. Y16 (2026-08-28, see core-image-minimal-initramfs.bbappend)
#     removed `initramfs-module-setup-live` from it specifically BECAUSE its
#     transitive `udev-extraconf` automount rule races that framework's own
#     root-mount logic and wins often enough to break boot on hybrid media.
#
#   - THIS initramfs (live-ISO boot): uses `initramfs-live-boot`
#     (openembedded-core/meta/recipes-core/initrdscripts/
#     initramfs-live-boot_1.0.bb -> files/init-live.sh), a completely
#     different, framework-independent /init script whose ENTIRE root-
#     discovery mechanism IS udev-extraconf's automount behavior: it waits
#     for udev-extraconf to mount the boot media (CD, USB, whatever) under
#     /run/media/<label>, then looks for `rootfs.img` inside that mount.
#     Here udev-extraconf is not a bug, it is the mechanism.
#
# See commercial/docs/DESIGN-live-installer-iso-2026-08.md §2.3 for the full
# root-cause writeup of why these must never share one initramfs image.

SUMMARY = "DuDuClaw OS live-ISO boot initramfs (Y18)"
DESCRIPTION = "${SUMMARY} — mounts the live boot medium (CD/ISO9660 or USB) \
via udev-extraconf automount, loop-mounts the squashfs rootfs.img found on \
it, and switch_roots into the live environment. Independent of, and never \
shared with, the production A/B boot initramfs."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

PACKAGE_INSTALL = "\
    initramfs-live-boot \
    udev \
    udev-extraconf \
    base-passwd \
    ${VIRTUAL-RUNTIME_base-utils} \
"

# Do not pollute the initrd image with rootfs features.
IMAGE_FEATURES = ""

# Don't allow the initramfs to contain a kernel.
PACKAGE_EXCLUDE = "kernel-image-*"

IMAGE_NAME_SUFFIX ?= ""
IMAGE_LINGUAS = ""

IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"
inherit core-image

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Same host-arch restriction as core-image-minimal-initramfs /
# initramfs-module-install (this pulls in the same udev/base-utils family).
COMPATIBLE_HOST = '(x86_64.*|i.86.*|arm.*|aarch64.*)-(linux.*|freebsd.*)'
