SUMMARY = "polkit rule: duduclaw agent group gets passwordless Flatpak SystemHelper access"
DESCRIPTION = "Installs a single polkit .rules file granting the 'duduclaw' \
group (the gateway/agent service account's existing primary group) \
unauthenticated access to org.freedesktop.Flatpak.* SystemHelper actions \
(install/update/uninstall/modify-repo). This is the OS-side permission \
foundation for 'agent installs/updates Flatpak apps on the user's behalf' \
(Y3-2 ticket, MAP-agent-native-os-2026-08.md decision ③) -- it does NOT \
implement any DuDuClaw-side approval gate in front of that capability, see \
files/60-duduclaw-flatpak-agent.rules for the full reasoning, including why \
this does NOT reuse flatpak's own upstream org.freedesktop.Flatpak.rules \
(privileged_group=wheel) unchanged: that rule additionally requires a \
logind-tracked active session, which this headless/no-logind architecture \
never has."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# DEPENDS (build-time): mirrors meta-oe's own recipes-extended/polkit/
# polkit-group-rule.inc pattern (DEPENDS += "polkit",
# REQUIRED_DISTRO_FEATURES = "polkit") rather than `require`-ing that .inc
# across a layer boundary, since the logic is five lines and duplicating
# it here keeps this recipe resilient to that upstream file moving/
# renaming.
#
# RDEPENDS (runtime, added on top of the upstream pattern -- checked, not
# assumed): flatpak's own RDEPENDS chain (flatpak_1.17.6.bb) does NOT list
# polkit at runtime, and duduclaw-image-flatpak.bb's IMAGE_INSTALL doesn't
# list the bare "polkit" package either -- without this line, a rules.d
# file could ship into the image with no polkitd ever reading it, PASSing
# do_install/QA silently while doing nothing at runtime. A polkit .rules
# file is inert without the daemon that scans ${datadir}/polkit-1/rules.d;
# this package's entire purpose is that file, so the runtime dependency is
# not optional.
DEPENDS += "polkit"
RDEPENDS:${PN} += "polkit"
inherit features_check
REQUIRED_DISTRO_FEATURES = "polkit"

SRC_URI = "file://60-duduclaw-flatpak-agent.rules"

S = "${UNPACKDIR}"

do_install() {
    # ${UNPACKDIR}, NOT ${WORKDIR} -- a real build-time bug caught here: on
    # this OE-core release, file:// SRC_URI entries land in ${UNPACKDIR}
    # (${S} above is already set to it), not directly in ${WORKDIR}. Caught
    # by `bitbake duduclaw-image-flatpak` actually failing do_install with
    # "cannot stat .../60-duduclaw-flatpak-agent.rules: No such file or
    # directory" -- meta-oe's own polkit-group-rule.inc (the pattern this
    # recipe otherwise mirrors) already used ${UNPACKDIR} for exactly this
    # reason; this recipe just failed to copy that one detail correctly the
    # first time.
    install -d ${D}${datadir}/polkit-1/rules.d
    install -m 0644 ${UNPACKDIR}/60-duduclaw-flatpak-agent.rules \
        ${D}${datadir}/polkit-1/rules.d/
}

FILES:${PN} += "${datadir}/polkit-1/rules.d"

# Config-only package -- nothing arch-specific, allow it onto any machine
# that has DISTRO_FEATURES polkit turned on (keeps this recipe reusable for
# duduclaw-genericx86-64 without any changes).
COMPATIBLE_MACHINE = ".*"
