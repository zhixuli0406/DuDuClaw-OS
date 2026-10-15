# DuDuClaw OS boot splash (C1 identity, 2026-10-16) -- plymouth itself comes
# from meta-oe (plymouth_24.004.60.bb at the meta-openembedded pin in
# kas/duduclaw-os.yml); openembedded-core at its pin ships no plymouth recipe
# (only psplash). The theme is recipes-duduclaw/duduclaw-boot-splash; the
# image wiring and kernel arguments are recipes-core/images/
# duduclaw-image-splash.inc.

# No plymouth in the initramfs. meta-oe's `initrd` PACKAGECONFIG produces
# plymouth-initrd with RDEPENDS on dracut, and dracut lives in
# meta-initramfs, which this build does not include ("Nothing RPROVIDES
# dracut" at build time). More to the point, this image's initramfs is
# oe-core's busybox initramfs-framework (core-image-minimal-initramfs.bbappend),
# not a systemd/dracut initrd, so there is nothing for plymouth to hook into
# there. The splash starts from the real root via plymouth-start.service
# (sysinit.target), a second or so after the kernel hands over. Keeping the
# initramfs untouched is also the fail-safe choice: nothing here can stop
# the root from being found and mounted.
PACKAGECONFIG:remove = "initrd"

# Build only the fallback themes. Ours (duduclaw) is a separate package;
# `text` is what plymouthd falls back to if the duduclaw theme cannot load
# (src/main.c show_default_splash: configured theme -> default.plymouth ->
# text -> built-in details), `details` is the verbose/serial view. The
# two-step plugin our theme uses is built regardless of this list
# (src/plugins/splash/meson.build has no option for it).
PLYMOUTH_THEMES = "text details"

# Compile-time background used by the text-mode fallbacks: the C1 dark
# background, so even a fallback splash is not the upstream brown.
PLYMOUTH_BACKGROUND_COLOR = "0x0b1e33"
PLYMOUTH_BACKGROUND_START_COLOR_STOP = "0x0b1e33"
PLYMOUTH_BACKGROUND_END_COLOR_STOP = "0x0b1e33"

# Point the distribution default at the duduclaw theme. plymouth installs
# ${datadir}/plymouth/plymouthd.defaults itself, so a second package cannot
# ship that path; editing it here is the one place that owns it. Fail the
# build if upstream changes the file's shape, rather than shipping a splash
# that silently stays on upstream's `spinner` default (which is not even
# built, see PLYMOUTH_THEMES above).
do_install:append() {
    defaults=${D}${datadir}/plymouth/plymouthd.defaults
    grep -q '^Theme=' "$defaults" || bbfatal "plymouthd.defaults has no Theme= line to point at duduclaw"
    sed -i 's/^Theme=.*/Theme=duduclaw/' "$defaults"
    grep -qx 'Theme=duduclaw' "$defaults" || bbfatal "failed to set Theme=duduclaw in plymouthd.defaults"
}
