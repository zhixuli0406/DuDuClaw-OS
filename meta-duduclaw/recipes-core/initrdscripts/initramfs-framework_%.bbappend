# Preserve a trusted /run ancestor when the installed initramfs hands off
# its tmpfs to systemd. Dropbear checks this ancestor for external -D keys.
FILESEXTRAPATHS:prepend := "${THISDIR}/initramfs-framework:"
SRC_URI += "file://0001-init-set-run-tmpfs-mode.patch"
