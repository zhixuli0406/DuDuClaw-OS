#!/usr/bin/env bash
# First-boot device identity + minimal gateway config, written to /data
# (the only writable partition — root is mounted read-only, see
# appliance/mkosi.repart/20-root-a.conf).
set -euo pipefail

DUDUCLAW_HOME=/data/duduclaw
SYSTEM_DIR=/data/duduclaw/system
mkdir -p "$DUDUCLAW_HOME" "$SYSTEM_DIR"
# $SYSTEM_DIR holds device.key (a device secret, already chmod 600 below)
# and machine-id — `mkdir -p` alone leaves the directory itself at the
# process umask's default (typically 0755, group/other-readable), which
# would let another local account enumerate its contents even though it
# can't read device.key's bytes. Tightened here for every install from this
# point forward; a device provisioned before this line existed is brought
# in line retroactively by the H3g migration
# (usr/share/duduclaw/migrations/1787540626.sh) instead of being silently
# left behind — see duduclaw_core::data_migrations for why /data changes
# need a forward-only migrator at all (A/B only rolls back root).
chmod 700 "$SYSTEM_DIR"

# --- machine-id persistence -------------------------------------------
# machine-id(5) recommends shipping /etc/machine-id empty in an image
# reused across many machines (see mkosi.extra/etc/machine-id) — systemd
# then bind-mounts a freshly generated ID over it at early boot and tries
# to commit it back to the real file if /etc is writable. Ours never is
# (read-only root), so nothing persists it across reboots on its own; this
# copies whatever ID this boot ended up with into /data once, on the
# device's actual first boot.
#
# KNOWN OPEN POINT: this does not yet guarantee STABILITY across reboots
# on its own — systemd's own machine-id generation appears to run very
# early (likely before any regular unit, possibly before local-fs-pre.target
# even fires), which is earlier than anywhere a bind-mount from this script
# could intercept it. So today every boot may still get a *freshly*
# generated transient ID via systemd's own bind-mount, while this file only
# tracks what the *first* boot happened to see. Needs verification on a
# real boot (or a QEMU smoke run) plus, if unstable, an initrd-level
# bind-mount hook run ahead of PID 1's own machine-id setup — tracked as an
# open item, not silently assumed to work.
if [[ ! -s "$SYSTEM_DIR/machine-id" ]]; then
    cp /etc/machine-id "$SYSTEM_DIR/machine-id"
fi

# --- device key placeholder ---------------------------------------------
# TODO: replace with real device identity/key generation once the gateway
# grows an appliance-aware command for it (there isn't one yet — this repo
# has no appliance-specific gateway code at all today). This just reserves
# the file + a random value so nothing downstream has to special-case "key
# not generated yet"; a future change swaps the generation method, not the
# path.
if [[ ! -s "$SYSTEM_DIR/device.key" ]]; then
    head -c 32 /dev/urandom | base64 > "$SYSTEM_DIR/device.key"
    chmod 600 "$SYSTEM_DIR/device.key"
fi

# --- gateway home + system user ownership --------------------------------
mkdir -p "$DUDUCLAW_HOME"
chown -R duduclaw:duduclaw "$DUDUCLAW_HOME"

# --- kiosk user home directory --------------------------------------------
# Same reasoning as the gateway home dir above: `useradd -d /data/duduclaw-
# kiosk` (postinst.d/20-users-and-units.sh) only recorded that path as
# the user's home field, it did not create it — root is read-only, and
# /data itself isn't populated until this first-real-boot step runs. Only
# needs to exist and be owned; Chromium creates its own --user-data-dir
# subdirectory under here on first launch (see duduclaw-kiosk-launch.sh).
# Harmless to run every boot even when duduclaw-kiosk.service never starts
# (headless boxes) — an unused, empty, correctly-owned directory costs
# nothing.
mkdir -p /data/duduclaw-kiosk
chown duduclaw-kiosk:duduclaw-kiosk /data/duduclaw-kiosk

# --- minimal config.toml ---------------------------------------------
# Byte-for-byte the same shape `write_minimal_config()` in
# crates/duduclaw-core/src/config.rs writes for a normal (non-appliance)
# first run, just with bind=0.0.0.0 instead of the desktop default of
# 127.0.0.1 — the appliance's whole point is being reachable from the LAN
# at http://duduclaw.local. Only written if config.toml doesn't already
# exist, so a later boot after the operator has edited it through the
# dashboard is never clobbered.
CONFIG_PATH="$DUDUCLAW_HOME/config.toml"
if [[ ! -f "$CONFIG_PATH" ]]; then
    cat > "${CONFIG_PATH}.tmp" <<'EOF'
# DuDuClaw configuration (auto-created by the appliance first-boot
# provisioning service). Finish setup in the dashboard — no need to edit
# this by hand.

[general]
log_level = "info"
default_language = "zh-TW"

[gateway]
bind = "0.0.0.0"
port = 18789
EOF
    mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    chown duduclaw:duduclaw "$CONFIG_PATH"
fi

# --- H3g /data migrations baseline (fresh-machine detection) -------------
# This is the ONE moment a device can be told, unambiguously, "this /data
# was never migrated forward from an older release" versus "this /data has
# been running for a while and genuinely needs whatever is pending" — this
# script only ever runs once, on the actual first boot (guarded by the
# unit's `ConditionPathExists=!.../system/.provisioned` and its own
# self-disabling ExecStartPost). A brand-new device's baked-in
# config/db/directory state already matches whatever shape this image's
# migrations would produce (they were written against THIS image), so
# replaying them would be redundant at best and, for a script written to
# transform an old shape, actively wrong at worst. Every migration script
# that ships in this image is therefore marked already-applied here, never
# executed. See crates/duduclaw-core/src/data_migrations.rs for the full
# mechanism and crates/duduclaw-cli/src/data_migrate.rs for the CLI/systemd
# front door that reads these markers on every later boot.
MIGRATIONS_SRC_DIR="${DUDUCLAW_MIGRATIONS_DIR:-/usr/share/duduclaw/migrations}"
MIGRATIONS_MARKER_DIR="$SYSTEM_DIR/migrations"
mkdir -p "$MIGRATIONS_MARKER_DIR"
if [[ -d "$MIGRATIONS_SRC_DIR" ]]; then
    for script in "$MIGRATIONS_SRC_DIR"/*.sh; do
        [[ -e "$script" ]] || continue   # glob didn't match anything: no migrations shipped yet
        touch "$MIGRATIONS_MARKER_DIR/$(basename "$script")"
    done
fi
chown -R duduclaw:duduclaw "$MIGRATIONS_MARKER_DIR"

touch "$SYSTEM_DIR/.provisioned"
