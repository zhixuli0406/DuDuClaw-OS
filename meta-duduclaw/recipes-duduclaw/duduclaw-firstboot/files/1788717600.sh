# Migration 1788717600: move the Windows RemoteApp registry out of the 0700
# gateway home.
#
# WHY: as of the AI-runtimes wave (2026-09-05/06) duduclaw-gateway runs the
# bundled vendor AI CLIs with HOME=/data/duduclaw, so that directory holds
# their OAuth tokens and duduclaw-firstboot-provision.sh makes it 0700. The
# RemoteApp registry `duduclaw compat windows-vm app-add` used to write at
# /data/duduclaw/windows-vm/apps.toml (0644, deliberately cross-user
# readable) is read by duduclaw-shell as the duduclaw-kiosk user, and a 0700
# parent blocks that read regardless of the file's own mode -- every pinned
# Windows app would silently disappear from the Launcher. New machines write
# it to /data/system/windows-vm/apps.toml (gateway env
# DUDUCLAW_WINDOWS_VM_APPS_DIR, 20-home.conf); this migrator moves an
# existing registry there on machines provisioned before the change.
#
# Idempotent: nothing to do when the old file is absent; never overwrites a
# registry that already exists at the new path (an operator may have
# re-pinned apps after the update) -- in that case the old file is left in
# place and reported, not deleted.
set -euo pipefail
OLD="${DUDUCLAW_HOME:-/data/duduclaw}/windows-vm/apps.toml"
NEW_DIR="/data/system/windows-vm"
NEW="${NEW_DIR}/apps.toml"
if [[ ! -f "$OLD" ]]; then
    echo "[migration 1788717600] ${OLD} does not exist, nothing to do"
    exit 0
fi
if [[ -e "$NEW" ]]; then
    echo "[migration 1788717600] ${NEW} already exists; leaving ${OLD} untouched"
    exit 0
fi
echo "[migration 1788717600] moving ${OLD} -> ${NEW}"
install -d -m 0755 -o root -g root "$NEW_DIR"
mv "$OLD" "$NEW"
chmod 0644 "$NEW"
