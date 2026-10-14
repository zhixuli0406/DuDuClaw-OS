#!/bin/sh
# Move root-only device state out of the gateway's home (rootless gateway,
# 2026-10-15). Run by duduclaw-home-owner.service (ExecStartPre), as root,
# before `systemd-tmpfiles` hands everything under /data/duduclaw to uid
# 1000 and before any uid-1000 process starts.
#
# While the gateway ran as root, three root consumers kept their state
# inside /data/duduclaw:
#   system/random-seed  written by duduclaw-persist-seed.service, fed to
#                       /dev/urandom by the initramfs persist module
#   system/machine-id   created by that initramfs module and bind-mounted
#                       onto /etc/machine-id
#   audit/rescue/       Entry B rescue-boot audit log
# Left there, the tmpfiles `Z` line would make them owned by uid 1000, so
# any AI employee could rewrite /etc/machine-id for the next boot or edit
# the rescue audit trail. All three consumers now use /data/system/... and
# this script carries an existing file over once.
#
# Only a file or directory that is still owned by root moves. Before this
# release that tree was root-only (system/ was 0700 root), so a root-owned
# entry is genuine; anything owned by another uid was created after the
# home became uid 1000's and is left where it is (tmpfiles then treats it
# like any other file in the home). Symlinks are never followed or moved,
# and nothing moves if any directory on the way (/data/duduclaw,
# .../system, .../audit) is a symlink. A destination that already exists
# wins (a root writer may have recreated it first); the root-owned source
# is then parked as /data/system/legacy/<name>.<epoch> instead of being
# left where tmpfiles would hand it to uid 1000.
#
# Not fatal on any single item: a failure is logged and the remaining items
# are still tried, because a missed relocation only means that one consumer
# starts fresh (new seed, new machine-id), which is safe. The script exits
# non-zero if anything failed so the unit shows it.
set -u

log() { echo "relocate-root-state: $*" >&2; }

status=0

# parents_are_real PATH: every directory between /data and PATH's parent
# is a real directory, not a symlink.
parents_are_real() {
    p=$(dirname "$1")
    while [ "$p" != "/data" ] && [ "$p" != "/" ]; do
        if [ -L "$p" ]; then
            return 1
        fi
        p=$(dirname "$p")
    done
    return 0
}

# move_root_owned SRC DST
move_root_owned() {
    src=$1
    dst=$2
    if ! parents_are_real "$src"; then
        log "a directory above $src is a symlink; not touching it"
        return 0
    fi
    if [ -L "$src" ]; then
        log "$src is a symlink; not following or moving it"
        return 0
    fi
    [ -e "$src" ] || return 0
    owner=$(stat -c %u "$src" 2>/dev/null) || {
        log "cannot stat $src; skipped"
        status=1
        return 0
    }
    if [ "$owner" != 0 ]; then
        log "$src is owned by uid $owner, not root; left in place"
        return 0
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        parked="/data/system/legacy/$(basename "$src").$(date +%s)"
        if mkdir -p /data/system/legacy && chmod 0700 /data/system/legacy && mv "$src" "$parked"; then
            log "$dst already exists; parked the old $src as $parked"
        else
            log "$dst already exists and $src could not be parked"
            status=1
        fi
        return 0
    fi
    if ! mkdir -p "$(dirname "$dst")"; then
        log "cannot create $(dirname "$dst"); $src left in place"
        status=1
        return 0
    fi
    # Same filesystem (/data), so mv is a rename(2): atomic, and a symlink
    # at the destination is replaced rather than followed.
    if mv "$src" "$dst"; then
        log "moved $src -> $dst"
    else
        log "mv $src -> $dst failed"
        status=1
    fi
}

# Nothing to do on an image without the legacy tree (fresh install, or an
# image without a /data partition).
[ -d /data ] || exit 0

if [ -L /data/system ]; then
    log "/data/system is a symlink; refusing to write through it"
    exit 1
fi
mkdir -p /data/system
chmod 0755 /data/system

move_root_owned /data/duduclaw/system/random-seed /data/system/random-seed
move_root_owned /data/duduclaw/system/machine-id  /data/system/machine-id
move_root_owned /data/duduclaw/audit/rescue       /data/system/audit/rescue

exit "$status"
