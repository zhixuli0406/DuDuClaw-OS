SUMMARY = "Pre-normalized OSTree/Flatpak repo (Chromium + runtime deps) baked in for zero-network first boot"
DESCRIPTION = "${SUMMARY}. This is the Y6-3 answer to \
research/native-os-2026-08/flatpak-carrier-2026-08.md §2.3/§2.4 and the \
Y3-2 handoff notes' 'sid-test' spike, both of which found that the \
OFFICIAL flatpak sideload-repos mechanism (`sideload-repos` auto-detect \
dirs / `--sideload-repo=` CLI flag / the official `flatpak create-usb` \
tool) does NOT work on this network-first-then-give-up behavior confirmed \
on flatpak 1.16.6 (Debian trixie, research spike) AND independently \
re-confirmed on 1.18.1 (Y3-2's own debian:sid spike) -- summary.idx is \
always fetched over the network first and sideload content is never \
consulted as a fallback. The validated replacement (both spikes agree): \
skip sideload-repos entirely, ref-promote a real pull into head refs, run \
`flatpak build-update-repo`, and point a plain second `file://` remote at \
the result. This recipe just ships that result as a package; \
gen-flatpak-offline-repo.sh (next to this .bb, NOT under files/ -- same \
convention as duduclaw-shell's gen-git-manifests.sh/gen-git-deps.py, a \
host-side pre-generation helper, not something bitbake ever executes) is \
how the tarball in files/ was produced, kept for reproducibility/refresh, \
not invoked by any bitbake task (it needs live Flathub network access and \
apt-installs its own flatpak/ostree/gnupg tooling in a throwaway \
container -- neither of which belongs inside a do_fetch/do_compile \
sandbox). See duduclaw-flatpak-kiosk-verify.sh's 'Offline preload repo' \
section for the consumer side (tries this repo as a `flathub-offline` \
remote before falling back to the live `flathub` network remote)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Native zstd binary to decompress the tarball in do_install -- NOT relying
# on the build host's `tar` having --zstd support (varies by tar version,
# unverified here), same reasoning as every other "don't assume a host tool
# capability, DEPENDS the exact tool" convention already used in this
# layer.
DEPENDS = "zstd-native"

SRC_URI = "file://duduclaw-flatpak-offline-repo.tar.zst;unpack=0"

# Real measured size (research spike + this recipe's own
# gen-flatpak-offline-repo.sh run against a live Flathub pull, both agree):
# Chromium + its 7 runtime/extension deps (org.chromium.Chromium.Codecs,
# org.chromium.Chromium.Locale, org.freedesktop.Platform + .GL.default +
# .GL.default-extra + .Locale + .codecs-extra) land at 2.4G of OSTree
# objects. SRC_URI_STRICT_CHECKSUMS is NOT set here on purpose -- Flathub
# content is refreshed upstream over time (security updates), and this
# package's whole point is "whatever gen-flatpak-offline-repo.sh most
# recently produced", not a byte-pinned external download -- there is
# nothing for bitbake to verify against a network source here, this is a
# pure local file:// SRC_URI.

S = "${UNPACKDIR}"

# This package is a passthrough of real Flathub-built OSTree content
# (Chromium binaries, .so's, compressed media assets already inside the
# per-object OSTree store). It MUST NOT go through OE's normal
# strip/debug-split/sysroot-strip pipeline: OSTree's repo is
# content-addressed (object filenames under objects/xx/yyyy... ARE the
# sha256 of their exact byte content) -- if do_package_strip or any other
# packaging step so much as touches one byte of one object file, that
# object's filename no longer matches its content and the repo silently
# becomes internally inconsistent (every commit/dirtree that references
# the old checksum would then point at either nothing or the wrong bytes).
# There is no QA check that would catch this after the fact -- it would
# just manifest as a mysterious "delta not found"/corrupt-checkout failure
# at `flatpak install` time, on a real machine, possibly during the Y6-3
# real-hardware bring-up this recipe exists for. Byte-for-byte passthrough
# is not optional here.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_SYSROOT_STRIP = "1"
# Same reasoning extended to insane.bbclass's package QA scan -- it walks
# every ELF-looking file in ${D} regardless of extension (OSTree objects
# have checksum filenames, no .so/.bin naming to exempt them via FILES
# patterns) and would otherwise flag real, correctly-built-by-Flathub
# x86_64 binaries as "already-stripped" (Flathub release builds ship
# pre-stripped) or trip the arch/ldflags/textrel checks this recipe never
# built anything to satisfy in the first place -- none of these are actual
# defects in content we did not compile ourselves.
INSANE_SKIP:${PN} += "already-stripped arch ldflags textrel build-deps file-rdeps dev-so libdir staticdev split-strip"
# Auto file-dependency (shlibs/pkgconfig) scanning would walk 2.3G of
# unrelated Chromium-internal .so's and either take a very long time or
# manufacture bogus RDEPENDS/RPROVIDES entries from SONAMEs this image's
# package manager has no business tracking (they are consumed exclusively
# from inside Flatpak's own sandboxed runtime, never dynamically linked by
# anything else on the host rootfs).
SKIP_FILEDEPS:${PN} = "1"
PRIVATE_LIBS:${PN} = "*"

# Genuinely x86_64-specific content (Chromium's Flathub build for this
# arch) -- see gen-flatpak-offline-repo.sh's ARCH= var. Not COMPATIBLE_MACHINE
# = ".*" like the config-only recipes in this layer; this one only makes
# sense on an x86_64 MACHINE (duduclaw-qemux86-64 / duduclaw-genericx86-64,
# the only two this layer currently defines).
#
# Real build-time bug caught here, same class already documented in
# recipes-kernel/linux/linux-yocto_6.18.bbappend's own COMPATIBLE_MACHINE
# comment: this layer's actual ${MACHINE} values are "duduclaw-qemux86-64"
# / "duduclaw-genericx86-64" (the "duduclaw-" prefix is load-bearing, see
# conf/machine/*.conf's MACHINEOVERRIDES), and COMPATIBLE_MACHINE is
# matched with re.match() (anchored at the START of the string only) --
# the bare "qemux86-64|genericx86-64" this line originally had does NOT
# match "duduclaw-genericx86-64" (it doesn't start with either
# alternative), so `bitbake duduclaw-flatpak-offline-repo` failed outright
# with "Nothing PROVIDES 'duduclaw-flatpak-offline-repo' ... incompatible
# with machine duduclaw-qemux86-64 (not in COMPATIBLE_MACHINE)" the first
# time this recipe was actually built, not caught by re-reading it.
COMPATIBLE_MACHINE = "^duduclaw-qemux86-64$|^duduclaw-genericx86-64$"
PACKAGE_ARCH = "${MACHINE_ARCH}"

OFFLINE_REPO_INSTALL_DIR = "/opt/duduclaw-flatpak-offline-repo"

do_install() {
    install -d ${D}${OFFLINE_REPO_INSTALL_DIR}
    # --strip-components=1: the tarball's own top-level entry is `repo/`
    # (gen-flatpak-offline-repo.sh does `tar -C "$INSTALL_PATH" -cf ... repo`)
    # -- this lands objects/refs/config/summary directly under
    # OFFLINE_REPO_INSTALL_DIR, matching what duduclaw-flatpak-kiosk-verify.sh
    # checks for (`$OFFLINE_REPO_DIR/objects`).
    zstd -dc ${UNPACKDIR}/duduclaw-flatpak-offline-repo.tar.zst | \
        tar -xf - -C ${D}${OFFLINE_REPO_INSTALL_DIR} --strip-components=1
}

FILES:${PN} += "${OFFLINE_REPO_INSTALL_DIR}"
