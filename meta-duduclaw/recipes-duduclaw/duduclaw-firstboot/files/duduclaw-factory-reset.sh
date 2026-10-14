#!/usr/bin/env bash
# DuDuClaw OS factory reset, root side (rootless gateway, 2026-10-15).
#
# Contract (shared with duduclaw-sysd's FactoryReset verb, which writes the
# marker and reboots):
#   marker   /data/system/factory-reset.pending, exactly one line,
#            `clear_network=0` or `clear_network=1` (one trailing newline
#            allowed, nothing else)
#   when     at boot, before duduclaw-firstboot-provision, duduclaw-home-owner,
#            duduclaw-data-migrate, duduclaw-podman, the gateway and the kiosk
#            (see duduclaw-factory-reset.service)
#   actions  1. empty /data/duduclaw and /data/duduclaw-kiosk (the
#               directories stay, their contents go)
#            2. remove /data/system/containers/duduclaw (rootless image and
#               container store; files there belong to subordinate uids)
#            3. clear_network=1: empty /data/system/iwd (saved Wi-Fi
#               networks and passphrases)
#            4. remove /data/system/machine-id, so the next boot gets a new
#               machine identity, as it did when machine-id still lived in
#               the gateway home (moved out on 2026-10-15)
#            5. re-enable duduclaw-firstboot-provision.service
#            6. delete the marker, last
#   failure  a malformed marker (missing line, extra content, not a regular
#            file, too large) wipes nothing and the marker stays, so the
#            device keeps working on its current data and the failure is in
#            the journal. A wipe that fails part-way also keeps the marker,
#            so the next boot tries again. Either way the unit exits non-zero.
#
# Why this runs at boot and not inside the gateway: the gateway runs as uid
# 1000 and cannot remove the subuid-owned container store or root-owned
# state, and a wipe while the gateway and its containers are running would
# race their writes. At this point in boot no uid-1000 or kiosk process
# exists yet.
#
# Symlinks are never followed:
#   - every target directory must itself be a real directory, not a symlink
#     (refused otherwise);
#   - nothing may be mounted at or below a target (refused otherwise), which
#     is what `rm --one-file-system` would protect; busybox rm (this
#     image's rm, VIRTUAL-RUNTIME_base-utils=busybox) has no such flag;
#   - contents are enumerated with a bash glob (dotglob, nullglob), which
#     lists directory entries without resolving them, then removed with
#     `rm -rf -- <entry>`. Both busybox and GNU rm unlink a symlink entry
#     itself and never descend through a symlink while recursing. A bash
#     glob also keeps a name containing a newline as one word, unlike
#     parsing `find` output (busybox find has no -delete or -print0 users
#     here).
set -uo pipefail
shopt -s dotglob nullglob

MARKER=/data/system/factory-reset.pending
MAX_MARKER_BYTES=64

log() { echo "duduclaw-factory-reset: $*" >&2; }

# mounted_at_or_below DIR -> 0 if anything is mounted at DIR or beneath it.
# Mount points in /proc/self/mountinfo (field 5) escape spaces as \040; the
# targets here have no spaces, and a prefix match on the escaped form is
# still correct for them.
mounted_at_or_below() {
    local dir=$1 mp
    while read -r _ _ _ _ mp _; do
        if [[ $mp == "$dir" || $mp == "$dir"/* ]]; then
            return 0
        fi
    done < /proc/self/mountinfo
    return 1
}

# check_target DIR -> 0 if DIR may be operated on (absent counts as "nothing
# to do", reported through the return code 2).
check_target() {
    local dir=$1
    if [[ -L $dir ]]; then
        log "refusing: $dir is a symlink"
        return 1
    fi
    if [[ ! -e $dir ]]; then
        log "$dir does not exist, nothing to remove"
        return 2
    fi
    if [[ ! -d $dir ]]; then
        log "refusing: $dir is not a directory"
        return 1
    fi
    if mounted_at_or_below "$dir"; then
        log "refusing: something is mounted at or below $dir"
        return 1
    fi
    return 0
}

# wipe_contents DIR: remove everything inside DIR, keep DIR itself.
wipe_contents() {
    local dir=$1 entry rc=0 left
    check_target "$dir"
    case $? in
        0) ;;
        2) return 0 ;;
        *) return 1 ;;
    esac
    for entry in "$dir"/*; do
        if ! rm -rf -- "$entry"; then
            log "failed to remove $entry"
            rc=1
        fi
    done
    left=("$dir"/*)
    if (( ${#left[@]} != 0 )); then
        log "$dir still has ${#left[@]} entries after the wipe"
        rc=1
    fi
    (( rc == 0 )) && log "emptied $dir"
    return "$rc"
}

# remove_tree DIR: remove DIR and everything inside it.
remove_tree() {
    local dir=$1
    check_target "$dir"
    case $? in
        0) ;;
        2) return 0 ;;
        *) return 1 ;;
    esac
    if rm -rf -- "$dir" && [[ ! -e $dir && ! -L $dir ]]; then
        log "removed $dir"
        return 0
    fi
    log "failed to remove $dir"
    return 1
}

# --- 1. read and validate the marker -------------------------------------
if [[ ! -e $MARKER && ! -L $MARKER ]]; then
    log "no $MARKER, nothing to do"
    exit 0
fi
if [[ -L $MARKER || ! -f $MARKER ]]; then
    log "refusing: $MARKER is not a regular file; nothing wiped, marker kept"
    exit 1
fi
size=$(stat -c %s "$MARKER" 2>/dev/null) || size=-1
if (( size < 0 || size > MAX_MARKER_BYTES )); then
    log "refusing: $MARKER has unexpected size ($size bytes); nothing wiped, marker kept"
    exit 1
fi
# Read raw bytes; the trailing `x` keeps command substitution from
# stripping newlines, so "clear_network=1\n\n" is rejected, not accepted.
raw=$(cat -- "$MARKER" && printf x) || {
    log "refusing: cannot read $MARKER; nothing wiped, marker kept"
    exit 1
}
raw=${raw%x}
case $raw in
    "clear_network=0" | $'clear_network=0\n') clear_network=0 ;;
    "clear_network=1" | $'clear_network=1\n') clear_network=1 ;;
    *)
        log "refusing: $MARKER is malformed (expected one line clear_network=0 or clear_network=1); nothing wiped, marker kept"
        exit 1
        ;;
esac
log "factory reset requested (clear_network=$clear_network)"

# --- 2. wipe ---------------------------------------------------------------
failed=0
wipe_contents /data/duduclaw || failed=1
wipe_contents /data/duduclaw-kiosk || failed=1
remove_tree /data/system/containers/duduclaw || failed=1
if (( clear_network == 1 )); then
    wipe_contents /data/system/iwd || failed=1
else
    log "clear_network=0: keeping saved networks in /data/system/iwd"
fi
if [[ -L /data/system/machine-id ]]; then
    log "refusing: /data/system/machine-id is a symlink"
    failed=1
elif ! rm -f -- /data/system/machine-id; then
    log "failed to remove /data/system/machine-id"
    failed=1
fi

if (( failed != 0 )); then
    log "wipe incomplete; marker kept so the next boot retries"
    exit 1
fi

# --- 3. first-boot provisioning runs again ----------------------------------
# It runs on this very boot anyway: the gateway Requires= it (10-data.conf),
# this unit is ordered before it, and its ConditionPathExists=!.provisioned
# is true now that the home is empty. Enabling it again covers the next
# boots on a writable root, where its own ExecStartPost disabled it. On the
# read-only-root edition the enablement symlink is part of the image and
# was never removed, and `systemctl enable` cannot write /etc; that case is
# reported, not treated as a failure.
if systemctl is-enabled --quiet duduclaw-firstboot-provision.service; then
    log "duduclaw-firstboot-provision.service is already enabled"
elif systemctl enable duduclaw-firstboot-provision.service; then
    log "re-enabled duduclaw-firstboot-provision.service"
else
    log "could not re-enable duduclaw-firstboot-provision.service (read-only /etc?); it still runs this boot through the gateway's Requires="
fi

# --- 4. marker last ----------------------------------------------------------
if ! rm -f -- "$MARKER"; then
    log "wipe done but could not delete $MARKER; the next boot will wipe again"
    exit 1
fi
sync
log "factory reset complete"
exit 0
