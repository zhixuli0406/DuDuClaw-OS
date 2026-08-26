SUMMARY = "udev rules: /dev/uinput + Valve USB device access for Steam Flatpak"
DESCRIPTION = "Formalizes a Y4-2 manual QEMU-session workaround into a real \
image mechanism: Steam's Flatpak wrapper (steam_wrapper.py, \
check_device_perms()) does a literal os.access(\"/dev/uinput\", R_OK|W_OK) \
before launching, and without a udev rule that changes /dev/uinput's group \
ownership the device stays root:root/0600 regardless of the caller's own \
group membership -- the exact dead end Y4-2 hit. See \
files/99-duduclaw-steam-devices.rules for the full one-hand-verified \
reasoning (upstream ValveSoftware/steam-devices content, Batocera \
cross-check, and why GROUP=\"input\" is used instead of upstream's \
TAG+=\"uaccess\" alone on this no-logind kiosk OS)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://99-duduclaw-steam-devices.rules"

S = "${UNPACKDIR}"

do_install() {
    # ${nonarch_base_libdir}/udev/rules.d -- the standard oe-core location
    # for package-owned (non-/etc, non-operator-editable) udev rules;
    # systemd-udevd's compiled-in search path includes this directory
    # ahead of /etc/udev/rules.d, same convention every other udev-rules-
    # shipping oe-core/meta-oe recipe uses.
    install -d ${D}${nonarch_base_libdir}/udev/rules.d
    install -m 0644 ${UNPACKDIR}/99-duduclaw-steam-devices.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/
}

FILES:${PN} += "${nonarch_base_libdir}/udev/rules.d/99-duduclaw-steam-devices.rules"

# Config-only package, nothing arch-specific -- same reasoning as
# duduclaw-polkit-flatpak.bb's own COMPATIBLE_MACHINE, reusable verbatim on
# duduclaw-genericx86-64.
COMPATIBLE_MACHINE = ".*"
