#!/usr/bin/env bash
# First-boot device identity + minimal gateway config, written to /data.
#
# Yocto port of the Debian appliance line's duduclaw-firstboot-provision.sh
# (appliance/mkosi.extra/usr/local/sbin/duduclaw-firstboot-provision.sh) --
# same script contract, same on-disk shape under /data, adapted for two
# real divergences from that line (both called out inline below, not
# silently papered over):
#
#   1. Root is NOT read-only here (duduclaw-image-data.bb's wks partition
#      2 has no ReadOnly= equivalent set -- this Yocto product line has not
#      made that hardening decision yet, unlike the Debian line's
#      appliance/mkosi.repart/20-root-a.conf). /data is still the right
#      place for this content regardless: it is the ONE partition this
#      line already treats as durable device state across a rebuild
#      (nothing about root=LABEL=root or the UKI changes across an image
#      rebuild preserves anything under root), and writing here now means
#      zero migration work whenever this line's root eventually does go
#      read-only.
#   2. This Yocto line has not yet created an unprivileged `duduclaw`
#      service user -- duduclaw-gateway.service
#      (recipes-duduclaw/duduclaw-cli/files/duduclaw-gateway.service) runs
#      as root today (that recipe's own header calls this out as
#      deliberate, deferred product-layer work). `duduclaw-kiosk` DOES
#      exist (recipes-duduclaw/duduclaw-shell's USERADD_PARAM). This script
#      therefore probes for the `duduclaw` account at runtime rather than
#      hardcoding `chown duduclaw:duduclaw` the way the Debian script does
#      -- a hardcoded chown to a nonexistent user would make `useradd`'s
#      own `chown` equivalent fail this whole script (set -e), which would
#      be strictly worse than today's total absence of /data. The moment a
#      future ticket adds that user, this script picks it up with zero
#      changes.
set -euo pipefail

DUDUCLAW_HOME=/data/duduclaw
SYSTEM_DIR=/data/duduclaw/system
mkdir -p "$DUDUCLAW_HOME" "$SYSTEM_DIR"
# $SYSTEM_DIR holds device.key (chmod 600 below) and machine-id -- tighten
# the directory itself so another local account can't even enumerate its
# contents, matching the Debian line's own H3g-motivated fix (that line's
# script comment has the full incident this defends against; the same
# defensive posture applies here even though no local unprivileged account
# other than duduclaw-kiosk exists on this line yet -- cheap to do right
# from the start rather than needing a forward-only migrator of our own
# later).
chmod 700 "$SYSTEM_DIR"

# --- gateway service-account detection -----------------------------------
# See divergence (2) above. `id -u` is POSIX and present on every image
# this recipe targets (base-files/shadow always ship it).
if id -u duduclaw >/dev/null 2>&1; then
    DUDUCLAW_OWNER="duduclaw:duduclaw"
else
    DUDUCLAW_OWNER="root:root"
    echo "duduclaw-firstboot-provision: no 'duduclaw' service user on this" \
         "image yet -- ${DUDUCLAW_HOME} stays root:root (duduclaw-gateway.service" \
         "also still runs as root; see that unit's own header). This is" \
         "consistent with this Yocto line's current security posture, not a" \
         "regression -- revisit together with the gateway's own user=root" \
         "decision, not by chown-ing this directory alone." >&2
fi

# --- machine-id persistence -------------------------------------------
# Same reasoning as the Debian line's script: systemd generates a fresh
# /etc/machine-id whenever the shipped one is empty (machine-id(5)), and
# nothing on this line persists that across a rebuilt image today (root is
# writable here, unlike Debian's line, but a rebuilt image is still a
# FRESH root each time -- there is no in-place upgrade path on this Yocto
# line yet, only "burn a new image"). Copies whatever ID this boot ended up
# with into /data once, on the device's actual first boot.
#
# KNOWN OPEN POINT (carried over verbatim from the Debian line's own script
# -- not independently re-verified on Yocto this round): whether this
# actually achieves cross-reboot STABILITY depends on exactly when
# systemd's own machine-id generation runs relative to this unit; flagged
# there as needing a real-boot check, same status here.
if [[ ! -s "$SYSTEM_DIR/machine-id" ]]; then
    cp /etc/machine-id "$SYSTEM_DIR/machine-id"
fi

# --- device key placeholder ---------------------------------------------
# Same placeholder-until-a-real-appliance-identity-command story as the
# Debian line's script -- see that file's own TODO for the follow-up this
# is waiting on (shared across both lines, not duplicated work). Format is
# a 64-char lowercase-hex string, NOT the Debian line's base64 -- a real
# QEMU boot of this exact script (Y9-1, 2026-08-27) caught the Debian
# line's `head -c 32 /dev/urandom | base64 > file` failing outright on
# this image: `head: invalid option -- 'c'` (this image's BusyBox is built
# without CONFIG_FEATURE_FANCY_HEAD, so `-c` isn't recognised) immediately
# followed by `base64: not found` (no base64 applet in this BusyBox build
# at all, confirmed with `busybox --list | grep base64` returning nothing)
# -- under `set -o pipefail` the pipeline's exit status was base64's 127,
# `set -e` killed the script right here, and EVERYTHING after this block
# (gateway home re-chown, /data/duduclaw-kiosk creation, config.toml,
# H3g migrations baseline, the final `.provisioned` stamp) silently never
# ran on the first boot that hit this -- confirmed by the missing files
# matching this exact script line for line, not inferred. `dd`/`sha256sum`/
# `cut` are all confirmed present and working on this same restricted
# BusyBox (unlike `head -c`/`base64`) -- `dd if=... bs=32 count=1` is the
# classic/POSIX dd invocation form, not a GNU-only extension, so this is
# expected to be robust on any busybox/coreutils combination this image
# family ships, not merely patched to work around today's specific build.
if [[ ! -s "$SYSTEM_DIR/device.key" ]]; then
    dd if=/dev/urandom bs=32 count=1 2>/dev/null | sha256sum | cut -d' ' -f1 > "$SYSTEM_DIR/device.key"
    chmod 600 "$SYSTEM_DIR/device.key"
fi

# --- journald FSS (Forward Secure Sealing) key generation ---------------
# WS-3/B2 (2026-09-01, DESIGN-os-security-line-2026-09.md §2 支柱二 B2).
# `Seal=yes` (recipes-duduclaw/duduclaw-journald/files/duduclaw.conf, same
# wave) makes journald WANT a sealing key, but does not generate one
# itself -- `journalctl --setup-keys` is a separate, one-time, one-shot
# admin action (systemd's own journalctl.xml: "generate a new key pair...
# The sealing key is stored in the journal data directory and shall
# remain on the host. The verification key should be stored externally").
# This is that one-time action, run automatically here because this line
# has no interactive operator at first boot to run it by hand.
#
# Idempotent: guarded by the verification key file's own existence, NOT
# by re-invoking `--setup-keys` and relying on ITS OWN idempotency --
# read journalctl's source directly before writing this
# (src/journal/journalctl-authenticate.c::action_setup_keys(), this
# line's pinned SRCREV): without `--force`, a second invocation after the
# sealing key file already exists on disk returns an EEXIST error and
# prints NOTHING to stdout -- re-running it harmlessly no-ops on the
# SEALING side, but would silently overwrite this script's own verify-key
# file with an EMPTY string if this script blindly captured stdout every
# boot without its own guard. Checking for our own output file first
# avoids ever calling the command a second time at all, which is simpler
# and more obviously correct than depending on that upstream failure mode
# staying empty-stdout-on-EEXIST across future systemd versions.
#
# STDOUT-ONLY KEY CAPTURE: confirmed by reading the same function -- when
# stdout is not a TTY (always true here, run non-interactively from a
# systemd unit) and JSON output is not requested, action_setup_keys()
# takes an early-return branch that ONLY calls `puts(key)` on stdout and
# skips the entire human-readable narrative/QR-code block (which would
# otherwise go to stderr) -- `$(...)` command substitution below captures
# exactly and only the key string, no parsing/stripping needed beyond
# what command substitution already does (trailing newline removal).
# `2>/dev/null` additionally discards the `log_info("Generating
# seed...")`-class progress lines systemd's own logging framework prints
# to stderr by default (not silenced by the stdout/TTY branch above,
# which only affects the narrative block).
#
# GCRYPT PREREQUISITE (verified, not assumed): this command hard-depends
# on systemd having been built with gcrypt support --
# recipes-core/systemd/systemd_%.bbappend now turns that on (same wave;
# it was OFF before this ticket, `journalctl --setup-keys` would have
# printed "Forward-secure sealing not available." and exited non-zero
# every single boot without that fix). If that build-time prerequisite
# ever regresses, the guard below degrades gracefully (empty $key,
# warning logged, script continues) rather than failing the whole
# first-boot provisioning run over a non-essential hardening feature.
FSS_VERIFY_KEY="$DUDUCLAW_HOME/journal-verify.key"
if [[ ! -s "$FSS_VERIFY_KEY" ]]; then
    fss_key="$(journalctl --setup-keys 2>/dev/null || true)"
    if [[ -n "$fss_key" ]]; then
        printf '%s\n' "$fss_key" > "${FSS_VERIFY_KEY}.tmp"
        chmod 600 "${FSS_VERIFY_KEY}.tmp"
        mv "${FSS_VERIFY_KEY}.tmp" "$FSS_VERIFY_KEY"
    else
        echo "duduclaw-firstboot-provision: journalctl --setup-keys produced no" \
             "key (gcrypt support missing, /var/log/journal not yet initialised," \
             "or a sealing key already exists from an earlier, non-idempotent-" \
             "guarded run) -- journal Seal=yes stays configured but effectively" \
             "unverifiable until this is investigated. Not treated as a fatal" \
             "first-boot error: FSS is defense-in-depth, not core device" \
             "identity." >&2
    fi
fi

# --- gateway home + service-account ownership -----------------------------
mkdir -p "$DUDUCLAW_HOME"
chown -R "$DUDUCLAW_OWNER" "$DUDUCLAW_HOME"

# --- kiosk user home directory --------------------------------------------
# duduclaw-kiosk's passwd entry already points --home-dir at this path
# (duduclaw-shell's USERADD_PARAM), but `useradd --no-create-home` (also
# set there, deliberately, since /data does not exist at package-install
# time) never creates it -- only needs to exist and be owned; duduclaw-comp/
# duduclaw-shell and fcitx5 create their own subdirectories under here on
# first launch. Harmless to run every boot even on a headless box that
# never starts duduclaw-kiosk.service.
#
# `-R` (WP2, 2026-08-29, installer-settings-integration design doc §3.2):
# the installer now pre-populates shell/oobe_state.json under this tree
# BEFORE first boot, as root (it writes directly onto the target disk's
# /data partition from the live environment -- see
# `duduclaw-os-install.sh`'s own §7). Without recursing, that file would
# stay root-owned forever and duduclaw-shell (running as duduclaw-kiosk)
# could not overwrite it on a later real OOBE run. This unit's own
# ConditionPathExists=!.provisioned only lets it fire once, so the
# recursive walk's cost is a non-issue.
mkdir -p /data/duduclaw-kiosk
chown -R duduclaw-kiosk:duduclaw-kiosk /data/duduclaw-kiosk

# --- minimal config.toml ---------------------------------------------
# Same shape `write_minimal_config()` in crates/duduclaw-core/src/config.rs
# writes for a normal first run, with bind=0.0.0.0 for the same
# LAN-reachability reason the Debian line's script states -- this Yocto
# line's duduclaw-gateway.service already forces DUDUCLAW_BIND=0.0.0.0 via
# its own env (Y5-4), so this file's [gateway] bind is redundant-but-
# consistent belt-and-braces, not load-bearing on its own the way it is on
# the Debian line (which has no such env var set). Only written if
# config.toml doesn't already exist, so a later boot after the operator has
# edited it through the dashboard is never clobbered.
CONFIG_PATH="$DUDUCLAW_HOME/config.toml"
if [[ ! -f "$CONFIG_PATH" ]]; then
    cat > "${CONFIG_PATH}.tmp" <<'EOF'
# DuDuClaw configuration (auto-created by the OS first-boot provisioning
# service). Finish setup in the dashboard -- no need to edit this by hand.

[general]
log_level = "info"
default_language = "zh-TW"

[gateway]
bind = "0.0.0.0"
port = 18789
EOF
    mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    chown "$DUDUCLAW_OWNER" "$CONFIG_PATH"
fi

# --- H3g /data migrations baseline (fresh-machine detection) -------------
# Identical mechanism to the Debian line's script -- see
# crates/duduclaw-core/src/data_migrations.rs (vendored byte-for-byte into
# this recipe's own duduclaw-cli-src/ snapshot) for the full design and
# that script's own comment for why a brand-new device must mark every
# shipped migration already-applied rather than ever replay one.
MIGRATIONS_SRC_DIR="${DUDUCLAW_MIGRATIONS_DIR:-/usr/share/duduclaw/migrations}"
MIGRATIONS_MARKER_DIR="$SYSTEM_DIR/migrations"
mkdir -p "$MIGRATIONS_MARKER_DIR"
if [[ -d "$MIGRATIONS_SRC_DIR" ]]; then
    for script in "$MIGRATIONS_SRC_DIR"/*.sh; do
        [[ -e "$script" ]] || continue   # glob didn't match anything: no migrations shipped yet
        touch "$MIGRATIONS_MARKER_DIR/$(basename "$script")"
    done
fi
chown -R "$DUDUCLAW_OWNER" "$MIGRATIONS_MARKER_DIR"

# --- Secure Boot factory-enroll downgrade (WS-3/SB-3, 2026-09-02) --------
# The factory loader.conf (recipes-core/images/duduclaw-image-ab/
# duduclaw-ab-loader.conf) ships `secure-boot-enroll force` UNCONDITIONALLY
# (see that file's own header for why this is provably inert -- not merely
# assumed safe -- on any image built without Secure Boot enrollment keys:
# systemd-boot's own secure_boot_discover_keys() silently no-ops when
# /loader/keys/ does not exist at all). On a device that DOES carry keys
# (classes/duduclaw-secure-boot.bbclass's DUDUCLAW_SB_ENROLL_KEYDIR ->
# /loader/keys/auto/), `force` is a STANDING "auto-enroll whatever I find
# under auto/" instruction -- correct for the very first boot (enrolling
# the factory PK/KEK/db with zero operator interaction), but wrong to leave
# in place forever: a later factory-reset or key-rotation flow that drops a
# DIFFERENT key set into auto/ should never be silently re-enrolled without
# an operator decision. This downgrades `force` to `off` exactly once,
# after this device's own first successful boot.
#
# Self-guarded by the loader.conf's OWN current content (grep, not merely
# this script's outer .provisioned stamp) -- stays correct even if some
# future image ships a loader.conf that never had `force` in it at all
# (a plain no-op), and is safe to re-run to completion if a previous first
# boot was interrupted mid-write (the `mv` below is the atomic commit
# point; a crash before it leaves the original file, matched by grep,
# untouched for the next boot to retry).
#
# ESP mount point is `/boot` on this line, not a guess -- confirmed by
# reading files/wic/duduclaw-ab-bootdisk.wks.in's own p1 line
# (`part /boot --source bootimg_efi ...`), the same convention every other
# image in this require chain (efi-uki-bootdisk.wks.in) already uses.
# duduclaw-firstboot-provision.service carries an explicit
# RequiresMountsFor=/boot (same wave) so this step never races the ESP
# mount, rather than relying on local-fs.target's ordinarily-earlier
# position in the boot sequence going untested.
#
# `grep -q`/`sed s///` (not `head -c`/`base64`, which this image's BusyBox
# build lacks -- see this script's own device-key block above for the
# confirmed-missing-applet incident) are default-enabled BusyBox applets in
# virtually every defconfig; NOT independently re-confirmed against this
# exact image's busybox config the way head -c/base64 were (no live boot
# available during this ticket) -- flagged rather than silently assumed,
# verify alongside the next real QEMU/hardware boot of this script.
ESP_LOADER_CONF=/boot/loader/loader.conf
if [[ -f "$ESP_LOADER_CONF" ]] && grep -q '^secure-boot-enroll force$' "$ESP_LOADER_CONF"; then
    sed 's/^secure-boot-enroll force$/secure-boot-enroll off/' "$ESP_LOADER_CONF" > "${ESP_LOADER_CONF}.tmp"
    mv "${ESP_LOADER_CONF}.tmp" "$ESP_LOADER_CONF"
fi

touch "$SYSTEM_DIR/.provisioned"
