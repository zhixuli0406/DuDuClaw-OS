# A/B update chain, Yocto side (Y8-1, 2026-08-27) — enable the two systemd
# tools the whole design in
# commercial/docs/DESIGN-ab-update-rollback-2026-08.md depends on:
# systemd-sysupdate (root-slot writes + version bookkeeping) and
# systemd-bless-boot (boot counting / Automatic Boot Assessment). Both were
# found MISSING from this Yocto build by direct forensic evidence, not by
# reading PACKAGECONFIG defaults and guessing — the exact same "G0/G1" shape
# the Debian appliance line hit first (see that design doc's §1.5-§1.7), but
# a DIFFERENT root cause: this is systemd 259.5's own meson build gating
# starving on missing PACKAGECONFIG flags, not a Debian-packaging split.
#
# EVIDENCE (2026-08-27, against the already-built duduclaw-qemux86-64
# sstate): `pkgdata/duduclaw-qemux86-64/runtime/systemd`'s own FILES: list
# has `bootctl` + `boot-complete.target` + `systemd-boot-check-no-failures`
# (all unconditionally built or gated only on HAVE_BLKID, which is already
# true) but ZERO occurrences of "bless" or "sysupdate" anywhere, and no
# `systemd-repart` binary/package either. Traced to the actual cause by
# reading the pinned systemd source tree (SRCREV
# b3d8fc43e9cb531d958c17ef2cd93b374bc14e8a, i.e. the real v259.5 meson.build/
# meson_options.txt, fetched from the builder's own git2 download cache —
# not assumed from memory):
#
#   * `src/bless-boot/meson.build`: systemd-bless-boot + its generator both
#     declare `'conditions': ['HAVE_BLKID', 'ENABLE_BOOTLOADER']`.
#     HAVE_BLKID is already true (that's why bootctl, which ALSO requires
#     only HAVE_BLKID, already builds). ENABLE_BOOTLOADER is
#     `get_option('bootloader').require(pyelftools.found() and
#     get_option('efi') and efi_arch != '').allowed()` — and `efi` is a
#     plain `type: boolean` option (meson.build's own `option('efi', type:
#     boolean, ...)`), default false, only ever flipped true by THIS
#     recipe's `PACKAGECONFIG[efi] = "-Defi=true -Dbootloader=enabled,..."`.
#     Confirmed via `bitbake-getvar -r systemd PACKAGECONFIG`: "efi" is NOT
#     in the resolved list, because the base recipe's default PACKAGECONFIG
#     only pulls "efi" in via `bb.utils.filter('DISTRO_FEATURES', '...efi
#     ...', d)` — and this distro's DISTRO_FEATURES (duduclaw-os.conf +
#     init-manager-systemd.inc) never actually contains the literal token
#     "efi" (only MACHINE_FEATURES does, via
#     duduclaw-qemux86-64.conf's `MACHINE_FEATURES:append = " efi"` — a
#     DIFFERENT bitbake variable the systemd recipe's filter never reads).
#     The image still boots via UKI+systemd-boot regardless, because sd-boot
#     itself is the separate systemd-boot_259.5.bb recipe, cross-compiled
#     with its own hardcoded `-Defi=true -Dbootloader=true` — completely
#     independent of the MAIN systemd package's own PACKAGECONFIG. That is
#     why "the machine boots fine" was never evidence that bless-boot would
#     be present.
#
#   * `src/sysupdate/meson.build`: systemd-sysupdate requires
#     `'ENABLE_SYSUPDATE'`, which needs `get_option('sysupdate')` (a
#     `type: feature` option with NO PACKAGECONFIG mapping at all in the
#     base recipe — added below) AND `ENABLE_IMPORTD==1` AND
#     `HAVE_OPENSSL==1` AND `HAVE_LIBFDISK==1`. ENABLE_IMPORTD itself needs
#     `get_option('importd')` (PACKAGECONFIG[importd] exists but is not in
#     the default set) AND HAVE_LIBCURL/HAVE_OPENSSL/HAVE_ZLIB/HAVE_XZ all
#     true. HAVE_LIBFDISK resolves on its own (`fdisk` meson option
#     defaults to 'auto', and util-linux — already a hard DEPENDS of this
#     recipe — provides libfdisk unconditionally, so no new PACKAGECONFIG
#     is needed for that one link in the chain).
#
# FIX: turn on exactly the PACKAGECONFIG flags this dependency chain needs,
# nothing more. `repart` is included too even though this Y8-1 wave's own
# A/B design does not put systemd-repart in the hot update path (sysupdate
# alone handles slot writes, per the corrected H3d/H3f design already
# ported from the Debian line) — it is the mechanism the Debian design doc
# names for growing `/data` to fill a real disk larger than the factory
# image (§ "GrowFileSystem" attribute), which this Yocto wks now also sets
# on its own /data partition (see files/wic/duduclaw-ab-bootdisk.wks.in);
# wiring an on-target `repart.d/` drop-in to actually exercise it is left as
# a followup (not yet done — see the Y8-1 handoff notes), but the BINARY
# needs to exist in the image for that followup to be possible at all, and
# it costs nothing extra: PACKAGECONFIG[repart] already requires openssl,
# which sysupdate needs anyway.
#
# `journal-upload`, despite its name, is what actually maps to
# `-Dlibcurl=enabled` in the base recipe (`PACKAGECONFIG[journal-upload] =
# "-Dlibcurl=enabled,-Dlibcurl=disabled,curl"`) — there is no
# differently-named flag for "just the libcurl feature detection", so this
# is the correct (if confusingly-named) flag to add for ENABLE_IMPORTD's
# HAVE_LIBCURL requirement. Its side effect (systemd-journal-upload/-remote
# tools become buildable) is harmless — this image does not enable or
# install those services.
#
# `sysupdate` PACKAGECONFIG does not exist in the base recipe at all
# (verified: `grep -i sysupdate systemd_259.5.bb` has zero hits before this
# append) — bitbake's PACKAGECONFIG mechanism does not require a flag to be
# pre-declared, so this .bbappend both DEFINES it and activates it.
PACKAGECONFIG[sysupdate] = "-Dsysupdate=enabled,-Dsysupdate=disabled"

PACKAGECONFIG:append = " efi openssl importd journal-upload zlib xz repart sysupdate"

# PARTIALLY VERIFIED BY AN ACTUAL REBUILD (2026-08-27): `bitbake -c
# write_wks_template duduclaw-image-ab` was run in the shared builder
# (triggers the full recipe dependency graph, including this systemd
# rebuild); systemd's own `do_configure` task SUCCEEDED and its meson
# configure-summary log
# (work/x86-64-v3-poky-linux/systemd/259.5/temp/log.do_configure) confirms
# every gate in the dependency chain resolved exactly as derived above:
#     efi: true   importd: enabled   libcurl: enabled   openssl: enabled
#     xz: enabled   zlib: enabled   bootloader: enabled   repart: enabled
#     sysupdate: enabled
# This is meson's OWN dependency-resolution engine confirming
# ENABLE_BOOTLOADER / ENABLE_SYSUPDATE would be true — the exact
# preconditions `src/bless-boot/meson.build` and `src/sysupdate/meson.build`
# gate the actual executables on. `do_compile` was then deliberately
# interrupted (SIGKILL to the bitbake worker) partway through, NOT because
# of an error, but because the same bitbake run's dependency graph had
# started fetching an unrelated, large git source (duduclaw-shell's
# zed-industries/zed `gpui_apple` submodule, needed for the full
# duduclaw-image-ab package set, nothing to do with this systemd change)
# and the shared builder's disk had already dropped from 5.9G to 3.8G free
# — past this project's 6G red line — during that one task run. So: the
# meson CONFIGURE step (the highest-risk point — where a genuinely missing
# dependency would hard-fail) is now real, first-hand-verified evidence,
# but the actual compiled binaries were never produced or packaged in this
# session. Confirm with a clean `bitbake systemd` (on a builder with more
# headroom, or a scoped `bitbake systemd -c populate_sysroot` that doesn't
# drag in the rest of the image graph) before the first real QEMU A/B test.
#
# One more thing this fix does NOT cover, flagged rather than silently
# assumed: `-Defi=true -Dbootloader=enabled` may also newly enable other
# systemd-boot-adjacent units this image has never run before (e.g.
# boot-loader random-seed generation, `bootctl`'s TPM/measured-boot-adjacent
# code paths) — this recipe change is additive by design intent, but that
# intent has not been confirmed against a real boot log. Re-run the
# existing Y1-1/Y2-x QEMU boot-to-login-prompt check after this lands, not
# just the AB-specific tests, to catch any regression in the
# already-verified baseline boot chain.
