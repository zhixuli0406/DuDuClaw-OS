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
# tools become buildable) turned out NOT to be harmless as originally
# asserted here: the services DO ship and systemd's enable-all preset
# activates systemd-journal-upload, which crash-loops without an upload
# URL — masked by duduclaw-journald.bb since VER-RO round 3 (2026-09-02),
# see that recipe's do_install comment.
#
# `sysupdate` PACKAGECONFIG does not exist in the base recipe at all
# (verified: `grep -i sysupdate systemd_259.5.bb` has zero hits before this
# append) — bitbake's PACKAGECONFIG mechanism does not require a flag to be
# pre-declared, so this .bbappend both DEFINES it and activates it.
PACKAGECONFIG[sysupdate] = "-Dsysupdate=enabled,-Dsysupdate=disabled"

# `gcrypt` PACKAGECONFIG — WS-3/B2 (2026-09-01, DESIGN-os-security-line-
# 2026-09.md §2 支柱二 B2, journald FSS/Seal=yes). Same "flag does not exist
# in the base recipe at all" shape as `sysupdate` above, verified the same
# way (`grep -n gcrypt systemd_259.5.bb` before this append: the ONLY hit is
# a stray comment — "# Sign the journal for anti-tampering" — sitting above
# the unrelated PACKAGECONFIG[gshadow] line, an apparent leftover from an
# upstream refactor that dropped the explicit oe-core PACKAGECONFIG[gcrypt]
# toggle at some point; no functioning flag survived it). The underlying
# systemd BUILD SUPPORT is real and unaffected by that oe-core packaging
# gap — read directly from this line's own pinned systemd source
# (SRCREV b3d8fc43e9cb531d958c17ef2cd93b374bc14e8a): meson_options.txt
# still declares `option('gcrypt', type: 'feature', ...)`, and meson.build's
# own `have = libgcrypt.found() and libgpg_error.found(); conf.set10(
# 'HAVE_GCRYPT', have)` gates journald's Forward Secure Sealing entirely —
# `src/journal/journalctl-authenticate.c::action_setup_keys()` (the code
# behind `journalctl --setup-keys`) is wrapped in `#if HAVE_GCRYPT` / `#else
# return log_error_errno(SYNTHETIC_ERRNO(EOPNOTSUPP), "Forward-secure
# sealing not available.")` — without this, `Seal=yes` in journald.conf
# would be silently unenforceable and duduclaw-firstboot-provision.sh's own
# key-generation step (same wave) would fail every boot. oe-core's own
# meson.bbclass sets no `-Dauto_features=disabled` default (checked, not
# assumed — grepped MESONOPTS directly), so meson's own 'feature'-type
# default (`auto`) would have silently resolved to disabled anyway since
# nothing pulls `libgcrypt` into this recipe's DEPENDS today — defining the
# flag explicitly (rather than only adding `libgcrypt` to DEPENDS and
# hoping auto-detection catches it) keeps this deterministic and
# self-documenting, same reasoning `sysupdate` above already established.
# `libgcrypt` itself is a plain oe-core recipe (meta/recipes-support/
# libgcrypt/libgcrypt_1.12.1.bb on this line's pinned branch — confirmed
# present, no new layer needed), and its own RDEPENDS/DEPENDS on
# libgpg-error is standard oe-core packaging, not something this bbappend
# needs to name separately.
PACKAGECONFIG[gcrypt] = "-Dgcrypt=enabled,-Dgcrypt=disabled,libgcrypt"

# `cryptsetup`/`tpm2` — trust chain P1 wave TPM (2026-09-02, DESIGN-os-
# trust-chain-2026-09.md §4 + 2026-09-02 拍板紀錄 T5/T6/T7). UNLIKE
# `sysupdate`/`gcrypt` above, BOTH flags already exist verbatim in the
# base recipe (`grep -n "PACKAGECONFIG\[cryptsetup\]\|PACKAGECONFIG\[tpm2\]"
# systemd_259.5.bb` before this append — two real hits, not zero) — this
# append only ACTIVATES them, it does not define them:
#
#   PACKAGECONFIG[cryptsetup] = "-Dlibcryptsetup=enabled,...,cryptsetup,,cryptsetup"
#   PACKAGECONFIG[tpm2]       = "-Dtpm2=enabled,...,tpm2-tss,tpm2-tss libtss2 libtss2-tcti-device"
#
# Confirms this wave's own task-brief premise ("systemd 259.5 目前編譯旗標
# -TPM2 -LIBCRYPTSETUP") from the recipe source directly, not by trusting
# the brief's own wording. `cryptsetup`'s DEPENDS points at the `cryptsetup`
# recipe (cross-compiled target build, providing libcryptsetup.so + headers
# via sysroot — the SAME recipe classes/duduclaw-verity.bbclass's own
# `DEPENDS:append` already pulls in as `cryptsetup-native` for a DIFFERENT
# purpose; this is the target-side link dependency, not a duplicate). Its
# RDEPENDS ("cryptsetup") lands on the MAIN `systemd` package — the
# `cryptsetup`/`veritysetup` CLI *binaries* on target are a SEPARATE
# concern already solved by duduclaw-verity.bbclass's own
# `IMAGE_INSTALL:append`.
#
# `tpm2`'s DEPENDS is the recipe literally named `tpm2-tss` — VERIFIED
# this does NOT resolve inside any layer this project currently pins
# (openembedded-core / meta-openembedded / meta-virtualization / meta-
# yocto — `find . -iname "tpm2-tss*.bb"` across every checked-out layer:
# zero hits, before assuming "PACKAGECONFIG exists" meant "buildable").
# classes/duduclaw-tpm.bbclass's own header documents the fix (a new
# `meta-security`/`meta-tpm` sublayer pin, only added by the
# `meta-duduclaw/kas/tpm-luks.yml` overlay — NOT this base recipe file,
# which must stay layer-agnostic).
#
# CONSEQUENTLY, unlike every other flag on the PACKAGECONFIG:append line
# below, `cryptsetup`/`tpm2` are NOT unconditionally appended — self-
# gated on DUDUCLAW_TPM_ENABLE instead, same pattern classes/
# duduclaw-verity.bbclass's own `DEPENDS:append`/`IMAGE_INSTALL:append`
# python-conditionals use. Unconditionally appending `tpm2` here would
# make `bitbake systemd` — and therefore EVERY image in this layer's
# `require` chain, not just the TPM wave's own test line — fail outright
# with "Nothing PROVIDES 'tpm2-tss'" on any kas config that has not ALSO
# composed `tpm-luks.yml`, exactly the "off ≠ byte-identical" regression
# classes/duduclaw-verity.bbclass's own header convention ("off = byte-
# identical to a build where this class were never inherited at all")
# exists to prevent. An unset/off build's PACKAGECONFIG list is untouched
# below and `tpm2-tss` is never even looked up.
PACKAGECONFIG:append = " efi openssl importd journal-upload zlib xz repart sysupdate gcrypt"
PACKAGECONFIG:append = "${@ ' cryptsetup tpm2' if d.getVar('DUDUCLAW_TPM_ENABLE') == '1' else ''}"

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
