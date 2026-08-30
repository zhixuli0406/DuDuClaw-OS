# Waydroid — CP-1 app-compat layer, Android app support via lxc + binder
# (commercial/docs/DESIGN-app-compat-layer-2026-08.md §2.4 /
# TODO-compat-cp1-2026-08.md A5).
#
# This recipe packages the Waydroid TOOLING ONLY — the `waydroid` Python
# CLI/daemon, its dbus/polkit/systemd glue, and its desktop-launcher
# metadata. It deliberately does NOT ship (and there is no companion
# `waydroid-data.bb` in this directory):
#   - The Android system/vendor base images ("waydroid init" fetches these
#     over the network at first run — the same upstream first-run flow
#     CP-0's own LINE-on-Waydroid PoC already exercised end-to-end).
#   - GApps or any ARM-translation component (libhoudini/libndk) — design
#     §2.4's law-firm-reviewed line: "內建 Waydroid 本體；不含 GApps／ARM
#     轉譯件... 留使用者自裝入口". Neither is fetched, referenced, or
#     linked from anywhere in this recipe.
# Both are explicit CP-1 scope boundaries, not oversights — see this
# recipe's own "NOT packaged here" section near the bottom for what a
# later wave would need to add for either.
SUMMARY = "Container-based runtime for a full Android system alongside the host"
DESCRIPTION = "${SUMMARY}, using Linux namespaces (user, ipc, net, mount) \
via lxc + the kernel binder driver to keep the Android system separated \
from the host while still compositing its windows onto the host Wayland \
session. This recipe ships the waydroid CLI/session-manager Python \
package and its systemd/dbus/polkit integration only — see this file's \
header for what is deliberately NOT included (Android base images, GApps, \
ARM translation)."
HOMEPAGE = "https://github.com/waydroid/waydroid"

# GPL-3.0-or-later per pyproject.toml's own SPDX header
# (`# SPDX-License-Identifier: GPL-3.0-or-later`) at the pinned tag — the
# LICENSE file itself is the generic FSF GPLv3 boilerplate text (same file,
# same md5, as python3-gbinder's LICENSE; independently confirmed by
# `curl`+`md5sum` on both before comparing) and does not itself distinguish
# -only from -or-later, so the SPDX header in the project's own source is
# the authoritative signal used here.
LICENSE = "GPL-3.0-or-later"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

# 1.6.3 — latest GitHub "Releases" tag as of 2026-08-30 (checked via the
# GitHub releases API, not just the newest entry in `git tag`, so this is
# the project's own declared stable point, not just its newest commit).
PV = "1.6.3"
SRCREV = "5b7e2e71be3f6bfaaaab3b461251dacaf1ce4991"
SRC_URI = "git://github.com/waydroid/waydroid.git;branch=main;protocol=https"

# mime-xdg: upstream ships two .desktop files carrying a MimeType key
# (waydroid.app.install.desktop / waydroid.market.desktop — the APK-install
# and app-store entries); oe-core's do_package_qa hard-fails such files
# unless the recipe inherits mime-xdg so the mime-cache postinst wiring
# exists (hit live on the 2026-08-30 CP-1 bake). Proper fix, not a QA skip.
inherit systemd mime-xdg

# Upstream's Makefile has no `clean` target — the default Makefile-project
# do_configure (`oe_runmake clean`) hard-fails on it ("No rule to make
# target 'clean'", hit live on the 2026-08-30 CP-1 bake). CLEANBROKEN is
# oe-core's designated flag for exactly this upstream shape.
CLEANBROKEN = "1"

# waydroid-container.service is the one unit upstream's own Makefile
# installs when USE_SYSTEMD=1 (its default — see do_install below).
# AUTO_ENABLE left at systemd.bbclass's own default ("enable" would start
# the LXC container at boot; this is a Waydroid CLI you invoke, not a
# resident service — same "ship the unit, don't force-enable it" posture
# duduclaw-flatpak-kiosk-verify's own verify.conf-gated services already
# use elsewhere in this layer).
SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "waydroid-container.service"
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

# Upstream's own Makefile has no build step at all ("Nothing to build, run
# 'make install' to copy the files!" — verified by reading the Makefile
# directly, not assumed from it being a Python project). Overriding
# do_compile to a real no-op rather than leaving the default `oe_runmake`
# (which would just run that same echo-and-exit target) is purely
# documentation — behavior is identical either way.
do_compile() {
    :
}

# USE_NFTABLES left at the upstream Makefile's own default (0 → iptables,
# via data/scripts/waydroid-net.sh's own `iptables-legacy`-then-`iptables`
# fallback) even though this layer now also carries meta-networking's
# nftables_1.1.6.bb (pulled in for meta-virtualization's own LAYERDEPENDS —
# see kas/duduclaw-os.yml's header comment). Explicit choice, not an
# oversight: iptables is the path debian/control's own RDEPENDS and every
# real-world Waydroid deployment this research found actually exercises;
# nftables is USE_NFTABLES=1-gated upstream and comparatively untested by
# this packaging pass. Flip to 1 and swap the RDEPENDS line below from
# `iptables` to `nftables` if a later wave wants the nftables path instead
# — both are one-line changes, not a re-architecture.
EXTRA_OEMAKE = "USE_SYSTEMD=1 USE_DBUS_ACTIVATION=1 USE_NFTABLES=0"

do_install() {
    oe_runmake install DESTDIR=${D}
    # Upstream's Makefile installs its data trees with `cp -r`, which
    # preserves the BUILD user's uid/gid on every copied file — classic
    # host contamination. Hit live on the first CP-1 bake (2026-08-30):
    # do_package failed with "Path .../etc/xdg/menus/applications-merged/
    # waydroid.menu is owned by uid 1000 ... doesn't match any user/group
    # on target". Reset the whole install tree under pseudo so every file
    # packages as root-owned — byte-identical to what a plain `install`
    # would have produced for each file.
    chown -R root:root ${D}
}

# Beyond oe-core's default FILES:${PN} globs (which already cover
# ${bindir}/* for the /usr/bin/waydroid symlink, bare ${sysconfdir} for the
# installed xdg menu-merge fragment, ${datadir}/applications for the
# .desktop file, and ${datadir}/${BPN} + ${libdir}/${BPN} — BPN=waydroid
# matches this recipe's own PN — for the /usr/lib/waydroid Python payload):
# desktop-directories, metainfo, icons, dbus-1, and polkit-1 are each their
# own datadir subtree with no matching default glob, verified by reading
# meta/conf/bitbake.conf's own FILES:${PN} default list, not assumed.
# systemd's own unit file is already covered by the `inherit systemd`
# block above (systemd.bbclass appends FILES for whatever
# SYSTEMD_SERVICE:${PN} declares).
FILES:${PN} += " \
    ${datadir}/desktop-directories \
    ${datadir}/metainfo \
    ${datadir}/icons \
    ${datadir}/dbus-1 \
    ${datadir}/polkit-1 \
    ${libdir}/waydroid \
"

# RDEPENDS below is a direct, package-name-mapped port of upstream's own
# debian/control `Depends:` line (the authoritative upstream-declared
# runtime dependency list — read from the pinned tag's actual
# debian/control, not reconstructed from grepping imports) onto this
# layer's OE package names. Three real naming/packaging divergences found
# by checking each one against the actual pinned recipe/class source
# rather than assuming a 1:1 Debian-name mapping:
#
#   gir1.2-gtk-3.0 -> gtk+3 (NOT a separate "-gir"/"-typelib" package).
#     oe-core's gobject-introspection.bbclass appends the .typelib file
#     straight into FILES:${PN} of the recipe that inherits it
#     (`FILES:${PN}:append = " ${libdir}/girepository-*/*.typelib"`,
#     confirmed by reading that class directly) — Debian splits gir data
#     into its own gir1.2-* package, oe-core does not.
#   dnsmasq -> not listed here at all. `recipes-containers/lxc/lxc_git.bb`
#     (meta-virtualization, pulled in by this same CP-1 change) already
#     carries `RDEPENDS:${PN} += "... dnsmasq ..."` unconditionally — lxc
#     itself, not Waydroid, owns that relationship in this layer's
#     dependency graph, so repeating it here would be a duplicate
#     assumption rather than a second source of truth.
#   `polkitd | policykit-1` / `pipewire-pulse | pulseaudio` -> bitbake has
#     no Depends-alternation syntax; each collapses to this distro's own
#     single chosen provider (polkit — already DISTRO_FEATURES-enabled for
#     the Y3-2 flatpak chain; pipewire-pulse — this distro's chosen audio
#     stack, see the "KNOWN GAP" comment below).
RDEPENDS:${PN} += " \
    lxc \
    libgbinder \
    python3-gbinder \
    python3-pygobject \
    gtk+3 \
    python3-dbus \
    dbus \
    polkit \
    pipewire-pulse \
    iptables \
"

# Soft dependency: `waydroid.py`'s own tools/helpers/arguments.py wraps
# `import argcomplete` in try/except (confirmed by reading that file
# directly) and only loses shell tab-completion if it's absent. A
# python3-argcomplete_3.6.3.bb recipe already exists in meta-python
# (already pinned by this file's own kas config) — cheap enough to
# recommend even though it is not upstream's own hard Depends.
RRECOMMENDS:${PN} += "python3-argcomplete"

# KNOWN GAP, for the integration wave (this recipe deliberately does NOT
# touch it — out of this ticket's file scope, and it is a cross-cutting
# distro-audio-policy decision, not a Waydroid-packaging one): this
# layer's own meta-duduclaw/recipes-multimedia/pipewire/pipewire_%.bbappend
# (Y7-3, 2026-08-26) explicitly DROPS the "pulseaudio" PACKAGECONFIG token
# from pipewire's build ("no libpulse-speaking app here either" — true at
# the time it was written) — which is also the exact PACKAGECONFIG that
# produces the `pipewire-pulse` package this recipe now RDEPENDS on above.
# Left as-is (not silently patched around) because re-opening that
# bbappend's own PACKAGECONFIG selection is squarely an image/audio-policy
# call, not something an app-compat packaging ticket should decide alone.
# The integration wave needs to append "pulseaudio" back onto that
# recipe's `PACKAGECONFIG:class-target` line (and update its own comment,
# which currently states the opposite) before `pipewire-pulse` actually
# exists to install — until then, adding `waydroid` to any IMAGE_INSTALL
# would fail dependency resolution on this exact package.

# NOT packaged here — left explicit rather than silently absent:
#   waydroid-data (Android system.img/vendor.img) — fetched by `waydroid
#     init` over the network at first run, matching every real-world
#     Waydroid deployment this research found (including the LuneOS one,
#     which vendors its own image mirror rather than baking images into
#     the recipe). No SRC_URI/checksum work needed unless a later wave
#     wants to pre-seed an offline image cache.
#   GApps / libhoudini / any ARM-translation runtime — design §2.4's
#     explicit legal line. The "使用者自裝入口" documentation this implies
#     is a product/docs-wave concern, not a packaging concern; nothing in
#     this recipe references, downloads, or stages any GApps/houdini
#     artifact.
#   apparmor profiles — the upstream Makefile's separate `install_apparmor`
#     target is never invoked by do_install above; this distro carries no
#     apparmor stack (matches this project's own steam-devices/network-
#     config recipes, which target a no-apparmor baseline throughout).

COMPATIBLE_MACHINE = ".*"
