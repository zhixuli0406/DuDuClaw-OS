# H3g migration #1: tighten $DUDUCLAW_HOME/system to 0700.
#
# WHY THIS NEEDS TO BE RETROACTIVE (not just fixed going forward): before
# this change, duduclaw-firstboot-provision.sh created
# $DUDUCLAW_HOME/system (holding device.key and machine-id) with a plain
# `mkdir -p`, leaving the directory itself at the process umask's default
# (typically 0755, group/other-readable) even though device.key inside it
# was always explicitly `chmod 600`. That gap let another local account on
# the box enumerate the directory's contents (filenames, sizes, mtimes —
# not device.key's bytes, which stayed protected) even though it could
# never read the key itself.
#
# firstboot-provision.sh itself was fixed to `chmod 700` the directory at
# creation time in the same change that added this migrator. But that fix
# only reaches devices provisioned by the CORRECTED script — and /data,
# unlike root, never rolls back and never gets replaced by an A/B update
# (see crates/duduclaw-core/src/data_migrations.rs for the full argument).
# A device already provisioned under the old script is running on a
# read-only root that will keep booting old *and* new images with the same
# already-0755 /data/duduclaw/system sitting there forever unless something
# forward-only closes the gap. This script is that something.
#
# Idempotent: chmod 700 on an already-700 directory is a no-op — safe to
# run every boot, safe to run twice in a row, safe to run on a device that
# already got it right from firstboot-provision.sh (nothing to correct,
# same end state either way).
set -euo pipefail

SYSTEM_DIR="${DUDUCLAW_HOME:-/data/duduclaw}/system"

echo "[migration 1787540626] tightening ${SYSTEM_DIR} to 0700 (device.key/machine-id live here)"

if [[ -d "$SYSTEM_DIR" ]]; then
    chmod 700 "$SYSTEM_DIR"
else
    # No system/ dir on this device yet is not this script's problem to
    # fix — duduclaw-firstboot-provision.sh owns creating it. Log and
    # succeed rather than fail a migration over a directory this script
    # was never responsible for making exist.
    echo "[migration 1787540626] ${SYSTEM_DIR} does not exist yet, nothing to do"
fi
