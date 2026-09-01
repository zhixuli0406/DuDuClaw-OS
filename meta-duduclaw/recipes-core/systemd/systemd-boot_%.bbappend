# DuDuClaw OS — sign the systemd-boot EFI binary itself, WS-3/SB-2/SB-3
# (2026-09-02).
#
# WHY THIS FILE, NOT A HOOK IN duduclaw-secure-boot.bbclass: firmware
# validates the FIRST thing it loads off the ESP against the enrolled `db`
# — that is systemd-boot's own binary (\EFI\BOOT\BOOTX64.EFI, the UEFI-spec
# fallback loader path), not any UKI. uki.bbclass already signs the UKI
# (UKI_SB_KEY/UKI_SB_CERT, unmodified oe-core behavior); the same key must
# also sign the systemd-boot binary or Secure Boot simply refuses to chain-
# load it at all, no matter how correctly the UKI itself is signed.
#
# WHERE the raw systemd-boot binary actually lands, verified firsthand
# (not assumed): recipes-core/systemd/systemd-boot_259.5.bb's own
# do_deploy() -- `install ${B}/src/boot/systemd-boot*.efi ${DEPLOYDIR}` --
# always deploys under the literal `systemd-boot*.efi` glob regardless of
# EFI_PROVIDER (this recipe's own PN, distinct from `${SYSTEMD_BOOT_IMAGE}`,
# which is a DIFFERENT, provider-conditional name only that recipe's own
# do_install/FILES: use for the target-rootfs package). wic's bootimg-efi
# plugin then picks THAT file up with its own hardcoded glob and copies it
# onto the ESP as \EFI\BOOT\BOOTX64.EFI -- confirmed by reading
# scripts/lib/wic/plugins/source/bootimg-efi.py's do_prepare_partition
# (systemd-boot branch: `for mod in [x for x in os.listdir(kernel_dir) if
# x.startswith("systemd-")]: cp ... EFI/BOOT/<name-with-prefix-stripped>`),
# cross-checked against two independent, actively-maintained poky forks
# (digi-embedded/poky and CESARBR/poky) rather than a single source, since
# this project's OWN pinned openembedded-core checkout does not vendor
# scripts/lib/wic at all (wic is a poky-combo-repo artifact, not an oe-core
# one -- confirmed by checking openembedded-core's own upstream GitHub
# mirror directly: no scripts/lib/wic directory exists there either, this
# is not a gap specific to this project's builder). NOT independently
# re-verified against THIS line's own SRCREV-pinned wic source (that source
# is not reachable from this ticket's read-only recon container at all) --
# flagged honestly rather than silently assumed current; the mechanism
# itself (glob-copy by "systemd-" prefix, entirely separate from the
# generic IMAGE_EFI_BOOT_FILES src;dst path duduclaw-secure-boot.bbclass
# and duduclaw-rescue-boot.bbclass both use for everything else) has been
# structurally stable across every fork checked and is corroborated by
# openembedded-core/meta/conf/image-uefi.conf carrying NO default
# IMAGE_EFI_BOOT_FILES entry for EFI_BOOT_IMAGE at all -- if the generic
# mechanism were what shipped the bootloader binary, some default would
# have to name it there, and none does.
#
# CONSEQUENCE: IMAGE_EFI_BOOT_FILES cannot be used to substitute a signed
# replacement for this file (there is no src;dst pair to intercept) -- the
# only place to act is INSIDE DEPLOY_DIR_IMAGE, after systemd-boot's own
# do_deploy produces the unsigned binary and before do_image_wic's glob-copy
# reads it. do_deploy:append() is exactly that seam, in the same recipe
# that produced the file, using the same ${DEPLOYDIR} the base do_deploy()
# already writes into -- no new task, no cross-recipe file reach-around.
#
# DEPENDS is per-recipe (see duduclaw-secure-boot.bbclass's own header for
# the full "why two separate DEPENDS edits" reasoning) -- this recipe's own
# do_deploy needs `sbsign` on ITS OWN native-sysroot PATH, independently of
# whatever the image recipe's DEPENDS already pulls in.
DEPENDS:append = "${@ ' sbsigntool-native' if d.getVar('UKI_SB_KEY') else ''}"

# Run-time guard (not a ${@...}-conditional function definition) mirrors
# duduclaw-secure-boot.bbclass's own contract: UKI_SB_KEY/UKI_SB_CERT unset
# -> this block is a shell no-op, byte-identical output to this recipe
# without this .bbappend at all. Checking in shell rather than skipping the
# function definition entirely at parse time keeps this a single, always-
# present function body -- simpler to read than a second conditionally-
# injected bitbake-level function.
do_deploy:append() {
    if [ -z "${UKI_SB_KEY}" ] || [ -z "${UKI_SB_CERT}" ]; then
        # Disabled -- byte-identical to this recipe without this .bbappend
        # at all (no file touched, no sbsign invocation).
        exit 0
    fi

    for f in ${DEPLOYDIR}/systemd-boot*.efi; do
        [ -e "$f" ] || continue   # glob didn't match: nothing to sign
        # sbsign refuses to be trusted to overwrite its own input safely
        # mid-write (classic sbsigntools' own default output name is
        # "<input>.signed", never the input path itself -- see
        # recipes-support/sbsigntool/files/0003-*.patch's own context,
        # vendored from meta-secure-core, for the upstream CLI shape this
        # mirrors: `sbsign --key K --cert C <in> --output <out>`) --
        # sign to a temp file, then atomically replace the original so
        # wic's own later glob-copy (which matches on the ORIGINAL
        # filename, not a new one) finds the signed bytes under the exact
        # name it already expects.
        sbsign --key "${UKI_SB_KEY}" --cert "${UKI_SB_CERT}" "$f" --output "$f.signed"
        mv "$f.signed" "$f"
    done
}
