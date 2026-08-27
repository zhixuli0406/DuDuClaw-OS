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
mkdir -p /data/duduclaw-kiosk
chown duduclaw-kiosk:duduclaw-kiosk /data/duduclaw-kiosk

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

touch "$SYSTEM_DIR/.provisioned"
