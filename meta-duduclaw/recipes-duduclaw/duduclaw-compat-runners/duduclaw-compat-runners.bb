SUMMARY = "compat.d declarations: Bottles (Windows app) + Waydroid (Android) + windows-vm (Windows VM+RemoteApp)"
DESCRIPTION = "${SUMMARY}. CP-1/A3 (commercial/docs/TODO-compat-cp1-2026-08.md) \
shipped the Bottles+Waydroid pair; CP-2/B3 (commercial/docs/TODO-compat-cp2-2026-08.md) \
adds the third declaration, windows-vm.toml, for the self-packaged \
dockur/windows + FreeRDP 3 RemoteApp bridge (design §2.3 路 B). All three \
are compat.d/*.toml declarations duduclaw_core::compat_runners discovers \
at the shipped layer (/usr/share/duduclaw/compat.d), config-only, mirrors \
duduclaw-polkit-flatpak's and duduclaw-network-config's own shape (a \
handful of dropped-in files, no compiled payload). See files/bottles.toml, \
files/waydroid.toml and files/windows-vm.toml for the per-runner reasoning \
(scope limits, grey-market exclusions, license-responsibility disclosure) \
and commercial/docs/DESIGN-app-compat-layer-2026-08.md §1/§2.3/§2.4 for \
the design this implements. \
\
Deliberately does NOT install Bottles, Waydroid, or the Windows VM \
container themselves -- this recipe only ships the declaration files that \
let `duduclaw compat list` report whether each runner's require_tool \
entries (flatpak; waydroid/lxc-start; docker/xfreerdp3) are present. \
Bottles arrives via the Flatpak channel (user- or dashboard-triggered \
Flathub install); Waydroid's own packaging chain is a separate CP-1 wave \
(A5) not wired into any image .inc yet; docker+docker-compose+freerdp3 are \
CP-2 waves B1/B2 (kernel fragments + image/conf), also not wired into any \
image .inc by this recipe -- so on today's image duduclaw compat list is \
expected to report waydroid and windows-vm as missing, which is the \
honest, working-as-designed state these declarations exist to surface, \
not a bug in this recipe."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://bottles.toml \
    file://waydroid.toml \
    file://windows-vm.toml \
"

S = "${UNPACKDIR}"

# Installs under ${datadir}/duduclaw/compat.d (== /usr/share/duduclaw/compat.d
# once ${datadir} expands on this distro), the exact literal path
# duduclaw_core::compat_runners::SHIPPED_COMPAT_DIR scans -- keep those two
# in sync if either ever moves.
do_install() {
    install -d ${D}${datadir}/duduclaw/compat.d
    install -m 0644 ${UNPACKDIR}/bottles.toml ${D}${datadir}/duduclaw/compat.d/
    install -m 0644 ${UNPACKDIR}/waydroid.toml ${D}${datadir}/duduclaw/compat.d/
    install -m 0644 ${UNPACKDIR}/windows-vm.toml ${D}${datadir}/duduclaw/compat.d/
}

FILES:${PN} += "${datadir}/duduclaw/compat.d"

# Config-only package, nothing arch-specific -- same reasoning as
# duduclaw-polkit-flatpak.bb / duduclaw-network-config.bb's own
# COMPATIBLE_MACHINE. Deliberately NOT added to any image .inc in this
# wave -- integration is a separate wave per the CP-1 TODO's "整合" row,
# to avoid colliding with other in-flight edits to those files.
COMPATIBLE_MACHINE = ".*"
