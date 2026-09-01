# duduclaw-secure-boot.bbclass — Secure Boot signing-chain wiring, host
# side (WS-3/SB-2 "sbsign(-native) available" / SB-3 "enrollment assets on
# the ESP"), 2026-09-02.
#
# This class is UNCONDITIONALLY inherited by duduclaw-image.bb (same
# placement as duduclaw-rescue-boot, one line up) — everything it DOES is
# itself gated on the two bitbake variables below being set, so inheriting
# it costs nothing on a build that never sets them. Read this file's own
# per-block comments for the exact "does nothing" argument at each point;
# the summary contract is:
#
#   UKI_SB_KEY / UKI_SB_CERT unset  -> DEPENDS unchanged, IMAGE_EFI_BOOT_FILES
#                                       unchanged, byte-identical to before
#                                       this class existed.
#   UKI_SB_KEY / UKI_SB_CERT set,
#   DUDUCLAW_SB_ENROLL_KEYDIR unset -> sbsigntool-native pulled in (do_uki /
#                                       do_uki_rescue can find `sbsign` on
#                                       PATH), no /loader/keys/ shipped —
#                                       signed UKIs, manual enrollment only.
#   all three set                   -> + PK.auth/KEK.auth/db.auth staged to
#                                       /loader/keys/auto/ for factory
#                                       auto-enroll (see
#                                       recipes-core/images/duduclaw-image-ab/
#                                       duduclaw-ab-loader.conf's own
#                                       `secure-boot-enroll force` line and
#                                       duduclaw-firstboot-provision.sh's
#                                       downgrade-to-off step).
#
# --- Why sbsigntool-native, not systemd-sbsign -----------------------
# See recipes-support/sbsigntool/sbsigntool_0.9.5.bb's own header for the
# full three-point evidence trail (oe-core's uki.bbclass comment + ukify's
# own default signtool inference + systemd-boot-native's deltask
# do_configure/do_compile making a native systemd-sbsign build
# architecturally the wrong shape here). This class only needs to know the
# CONCLUSION: with UKI_SB_KEY/UKI_SB_CERT set and no --signtool override
# (uki.bbclass's do_uki and duduclaw-rescue-boot.bbclass's do_uki_rescue
# both call ukify exactly this way, unmodified), ukify picks `sbsign` by
# default — so `sbsigntool-native` on PATH is both necessary and
# sufficient; no UKI_CONFIG_FILE / `--signtool=` wiring is needed anywhere
# in this layer.
#
# DEPENDS is per-RECIPE in bitbake, not global — do_uki/do_uki_rescue run
# as tasks of THIS image recipe (via uki.bbclass / duduclaw-rescue-boot.bbclass,
# both inherited at the image-recipe level), so `sbsign` needs to be on
# THIS recipe's own native-sysroot PATH, i.e. in THIS recipe's own DEPENDS
# — separately from recipes-core/systemd/systemd-boot_%.bbappend's own
# DEPENDS:append, which exists because systemd-boot's do_deploy (a task of
# the systemd-boot RECIPE, not this one) needs the identical tool in ITS
# OWN native-sysroot PATH to sign the systemd-boot EFI binary itself. Two
# separate recipes, two separate DEPENDS edits, same underlying tool.
DEPENDS:append = "${@ ' sbsigntool-native' if d.getVar('UKI_SB_KEY') else ''}"

# --- Secure Boot enrollment assets (PK.auth / KEK.auth / db.auth) ------
#
# Absolute build-host directory (produced by meta-duduclaw/scripts/
# sb-keygen.sh, OUTSIDE bitbake's SRC_URI/fetcher entirely — these are
# per-build-environment key material, not a versioned layer source) holding
# the four-file set that script's own contract documents:
# {PK,KEK,db}.{key,crt}+{PK,KEK,db}.auth+GUID.txt. This class only ever
# reads the three *.auth files (the signed EFI authenticated-variable
# payloads systemd-boot enrolls) — the *.key/*.crt pair is a SEPARATE
# concern (UKI_SB_KEY/UKI_SB_CERT above, consumed directly by ukify at
# native-build time, never staged into any deployed image artifact).
#
# Empty by default: unset means "no enrollment assets on the ESP", which is
# also exactly what a pre-this-ticket image already did (no /loader/keys/
# directory at all) — see the IMAGE_EFI_BOOT_FILES:append guard below.
DUDUCLAW_SB_ENROLL_KEYDIR ?= ""

# WHY THE ON-ESP DIRECTORY NAME IS "auto", NOT "duduclaw" (a real, load-
# bearing correction against the naively-expected `keys/<vendor-name>/`
# layout): read directly from the pinned systemd source (SRCREV
# b3d8fc43e9cb531d958c17ef2cd93b374bc14e8a) before writing this --
# src/boot/boot.c's secure_boot_discover_keys() only ever auto-invokes
# secure_boot_enroll_at() for a `\loader\keys\<NAME>` directory when
# `strcaseeq16(dirent->FileName, u"auto")` — i.e. `secure-boot-enroll
# force`/`if-safe` unattended auto-enrollment ONLY fires for the directory
# literally (case-insensitively) named `auto`. Any OTHER directory name
# still gets a boot-menu ENTRY ("Enroll Secure Boot keys: <name>"), but
# only ever enrolls if a human presses a key and selects it — which defeats
# this ticket's entire "factory auto-enroll, zero operator interaction"
# goal (recipes-core/images/duduclaw-image-ab/duduclaw-ab-loader.conf's
# `secure-boot-enroll force`). `auto` it is.
#
# Filenames are exact and case-sensitive (same source, src/boot/
# secure-boot.c's sb_vars[] table): `db.auth` (lowercase), `KEK.auth`,
# `PK.auth` (both uppercase) -- not a DuDuClaw convention, systemd's own.
# All three are `required: true` in that same table (`dbx.auth` is the one
# optional revocation-list slot this class does not stage) -- confirmed by
# the same read, which is why do_deploy_duduclaw_sb_keys below bb.fatal()s
# on a PARTIAL set rather than silently shipping an incomplete `auto/`
# directory that would fail to enroll at boot with no build-time signal.
DUDUCLAW_SB_ENROLL_ESP_DIR = "loader/keys/auto"

# Not the normal sstate-cached shape: DUDUCLAW_SB_ENROLL_KEYDIR is an
# external build-HOST path, invisible to bitbake's task-signature hashing
# (it hashes this TASK's own function text + declared vardeps, never the
# byte content of files reached via a bare shell `install` from an
# arbitrary path). Without [nostamp], a key-rotation re-run of
# sb-keygen.sh that regenerates the *.auth files in place, with the
# bitbake variable value itself unchanged, could sstate-hit and silently
# ship YESTERDAY's enrollment keys. [nostamp] forces a real re-copy on
# every build instead -- three small file installs, cheap insurance against
# a materially bad failure mode for security-relevant artifacts.
do_deploy_duduclaw_sb_keys[nostamp] = "1"
do_deploy_duduclaw_sb_keys[dirs] = "${DEPLOY_DIR_IMAGE}/duduclaw-sb-keys"

do_deploy_duduclaw_sb_keys() {
    if [ -z "${DUDUCLAW_SB_ENROLL_KEYDIR}" ]; then
        # Disabled -- matches IMAGE_EFI_BOOT_FILES:append's own guard below,
        # nothing else to do.
        exit 0
    fi
    if [ ! -d "${DUDUCLAW_SB_ENROLL_KEYDIR}" ]; then
        bbwarn "DUDUCLAW_SB_ENROLL_KEYDIR=${DUDUCLAW_SB_ENROLL_KEYDIR} does not exist -- skipping Secure Boot enrollment asset staging (image ships with no /loader/keys/ at all, same as if this variable were never set)."
        exit 0
    fi

    missing=""
    for f in PK.auth KEK.auth db.auth; do
        if [ ! -f "${DUDUCLAW_SB_ENROLL_KEYDIR}/$f" ]; then
            missing="$missing $f"
        fi
    done
    if [ -n "$missing" ]; then
        # Partial set is worse than no set at all: systemd-boot's own
        # secure_boot_enroll_at() loads all three sb_vars[] entries before
        # enrolling ANY of them (this class's own header comment has the
        # source citation) -- a partial /loader/keys/auto/ would fail to
        # enroll at BOOT time, with zero signal at build time. Fail loudly
        # here instead, where a human is actually looking.
        bbfatal "DUDUCLAW_SB_ENROLL_KEYDIR=${DUDUCLAW_SB_ENROLL_KEYDIR} is missing:${missing} -- systemd-boot enrolls PK.auth+KEK.auth+db.auth as an atomic set (secure-boot.c's own required-files check) or not at all. Provide all three, or unset DUDUCLAW_SB_ENROLL_KEYDIR to ship no enrollment assets."
    fi

    for f in PK.auth KEK.auth db.auth; do
        install -m 0444 "${DUDUCLAW_SB_ENROLL_KEYDIR}/$f" "${DEPLOY_DIR_IMAGE}/duduclaw-sb-keys/$f"
    done
}
addtask deploy_duduclaw_sb_keys before do_image_wic

# Staged into a dedicated duduclaw-sb-keys/ subdirectory of DEPLOY_DIR_IMAGE
# (not the flat DEPLOY_DIR_IMAGE root every other deploy task in this layer
# uses) purely so three files all named PK.auth/KEK.auth/db.auth across
# potentially multiple call sites can never collide with anything else ever
# deployed there -- cheap namespacing, not a functional requirement.
#
# wic's own IMAGE_EFI_BOOT_FILES install step is a plain OVERWRITING
# `install -m 0644 -D <DEPLOY_DIR_IMAGE>/<src> <hdddir>/<dst>` for every
# "src;dst" pair (verified against wic's own bootimg-efi.py source by
# classes/duduclaw-rescue-boot.bbclass's own header, same mechanism reused
# here) -- a MISSING src file makes that install command fail the whole
# do_image_wic task, which is exactly why this line is conditional on the
# same DUDUCLAW_SB_ENROLL_KEYDIR variable as the staging task above: if it
# is unset, do_deploy_duduclaw_sb_keys exits 0 without producing any files,
# and IMAGE_EFI_BOOT_FILES must not reference them either.
#
# Built entirely inside the python expression (d.getVar() calls, not a
# nested ${DUDUCLAW_SB_ENROLL_ESP_DIR} left for a second bitbake expansion
# pass) deliberately -- whether bitbake re-scans a ${@...} block's OWN
# return value for further ${VAR} expansion is not something this ticket
# wanted to depend on being true; resolving the variable in Python makes
# the output unambiguous either way.
IMAGE_EFI_BOOT_FILES:append = "${@ (lambda esp: ' duduclaw-sb-keys/PK.auth;%s/PK.auth duduclaw-sb-keys/KEK.auth;%s/KEK.auth duduclaw-sb-keys/db.auth;%s/db.auth' % (esp, esp, esp))(d.getVar('DUDUCLAW_SB_ENROLL_ESP_DIR')) if d.getVar('DUDUCLAW_SB_ENROLL_KEYDIR') else ''}"
