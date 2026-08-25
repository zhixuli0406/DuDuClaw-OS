# DuDuClaw OS — Y1-1 minimal bring-up image.
#
# Boots to a login prompt via a signed UKI + systemd-boot chain under QEMU
# (OVMF/edk2 UEFI firmware). This is the smallest useful proof that the
# layer skeleton + distro policy + UKI build chain actually work end to
# end — no Wayland/gateway/Rust payload yet (that lands in Y1-2 on top of
# this same recipe; see recipes-duduclaw/duduclaw-sysd/ for the stub).
#
# Config lifted verbatim from oe-core's own CI selftest for this exact
# scenario (meta/lib/oeqa/selftest/cases/uki.py::test_uki_boot_systemd, at
# the pinned openembedded-core commit — see meta-duduclaw/kas/duduclaw-os.yml
# for the commit hash and how it was found), not guessed — the selftest is
# the one place upstream actually exercises "core-image-minimal + uki.bbclass
# + systemd-boot + QEMU x86_64 + OVMF" together and asserts it boots.

SUMMARY = "DuDuClaw OS minimal bring-up image (Y1-1)"
DESCRIPTION = "${SUMMARY} — console-only, UKI + systemd-boot, proves the \
Yocto base layer boots before any product payload is added."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

IMAGE_FEATURES += "ssh-server-dropbear"

# --- UKI + systemd-boot chain -----------------------------------------
# EFI_PROVIDER / INIT_MANAGER are distro-level (duduclaw-os.conf); efi
# MACHINE_FEATURES and the QB_* / QEMU_USE_KVM runqemu knobs are
# machine-level (duduclaw-qemux86-64.conf). This recipe only carries the
# image-level half of the contract.
IMAGE_FSTYPES:append = " wic"
WKS_FILE = "efi-uki-bootdisk.wks.in"

INITRAMFS_IMAGE = "core-image-minimal-initramfs"
IMAGE_CLASSES:append = " uki"

# Boot command line baked into the signed UKI itself (not supplied by the
# bootloader) — root is found by GPT partition LABEL, matching
# efi-uki-bootdisk.wks.in's `part / --source rootfs ... --label root`.
UKI_CMDLINE = "rootwait root=LABEL=root console=${KERNEL_CONSOLE}"
