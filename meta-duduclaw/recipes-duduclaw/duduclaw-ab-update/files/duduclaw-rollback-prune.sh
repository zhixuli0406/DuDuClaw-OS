#!/usr/bin/env bash
# Delete ESP boot entries older than the rollback floor, once the running
# entry has passed the boot health gate (rootless gateway, 2026-10-15).
#
# Why: duduclaw-sysd's --min-rollback-version stops a requested rollback,
# but systemd-boot's automatic boot assessment has its own path back: an
# entry that is not yet blessed and fails its boot tries makes sd-boot fall
# back to the previous entry. Before the first rootless image is blessed
# that fallback is wanted (the new image may be broken). After it is
# blessed, an older entry is a way back to a gateway that runs as root, so
# it goes. The trade-off is deliberate: no return to a pre-rootless image,
# by any path, once a rootless one has proved it boots.
#
# Runs from duduclaw-rollback-prune.service, ordered after
# boot-complete.target (which the health gate is RequiredBy) and after
# systemd-bless-boot.service. Deletes only entries that:
#   - live in <ESP>/EFI/Linux and are named duduclaw-os_<version>[+...].efi
#     (the shape systemd-sysupdate writes; the rescue UKI,
#     duduclaw-os-rescue.efi, never matches);
#   - have a version that parses and is strictly lower than the floor;
#   - are not the running entry's version.
# It does nothing at all when the floor file is missing or does not parse,
# when the running entry cannot be identified, or when the running entry is
# itself below the floor. Version comparison mirrors duduclaw-sysd's
# rollback_floor.rs: up to four numeric parts, then a "-suffix" ranks below
# the bare release (1.73.4-y1-bringup < 1.73.4), "+meta" is ignored.
set -uo pipefail

# The two overrides exist for the script's own tests; production units
# never set them.
FLOOR_FILE=${DUDUCLAW_PRUNE_FLOOR_FILE:-/usr/lib/duduclaw/min-rollback-version}
EFIVARS=${DUDUCLAW_PRUNE_EFIVARS:-/sys/firmware/efi/efivars}
LOADER_GUID=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f

log() { echo "duduclaw-rollback-prune: $*" >&2; }

# ver_key VERSION -> prints "n1 n2 n3 n4 rel" (rel=1 release, 0 pre-release),
# or fails if VERSION does not parse.
ver_key() {
    local raw=${1#[vV]} core pre=1 sep i n
    [[ -n $raw && ${#raw} -le 32 ]] || return 1
    if [[ $raw =~ ^([0-9.]+)([-+])([A-Za-z0-9.-]+)$ ]]; then
        core=${BASH_REMATCH[1]}
        sep=${BASH_REMATCH[2]}
        [[ $sep == - ]] && pre=0
    elif [[ $raw =~ ^[0-9.]+$ ]]; then
        core=$raw
    else
        return 1
    fi
    [[ $core != *. && $core != .* && $core != *..* ]] || return 1
    local -a parts
    IFS=. read -r -a parts <<< "$core"
    (( ${#parts[@]} >= 1 && ${#parts[@]} <= 4 )) || return 1
    local out=""
    for i in 0 1 2 3; do
        n=${parts[$i]:-0}
        [[ $n =~ ^[0-9]{1,9}$ ]] || return 1
        out+="$((10#$n)) "
    done
    echo "${out}${pre}"
}

# key_lt A B -> 0 if A < B (both already validated keys "n1 n2 n3 n4 rel")
key_lt() {
    local -a a b
    read -r -a a <<< "$1"
    read -r -a b <<< "$2"
    local i
    for i in 0 1 2 3 4; do
        (( a[i] < b[i] )) && return 0
        (( a[i] > b[i] )) && return 1
    done
    return 1
}

# entry_version FILENAME -> version part of duduclaw-os_<v>[+tries...].efi
entry_version() {
    local name=$1 v
    [[ $name =~ ^duduclaw-os_(.+)\.efi$ ]] || return 1
    v=${BASH_REMATCH[1]}
    # strip a boot counter suffix (+LEFT or +LEFT-DONE)
    if [[ $v =~ ^(.+)\+[0-9]+(-[0-9]+)?$ ]]; then
        v=${BASH_REMATCH[1]}
    fi
    echo "$v"
}

[[ -r $FLOOR_FILE ]] || { log "no rollback floor configured; nothing to do"; exit 0; }
floor=$(tr -d '[:space:]' < "$FLOOR_FILE")
floor_key=$(ver_key "$floor") || { log "floor '$floor' does not parse; refusing to delete anything"; exit 1; }

sel_var="$EFIVARS/LoaderEntrySelected-$LOADER_GUID"
[[ -r $sel_var ]] || { log "cannot read LoaderEntrySelected; running entry unknown, deleting nothing"; exit 0; }
# efivar layout: 4 attribute bytes, then a NUL-terminated UTF-16LE string.
running_id=$(dd if="$sel_var" bs=1 skip=4 2>/dev/null | tr -d '\000')
running_ver=$(entry_version "$running_id") || {
    log "running entry '$running_id' is not a duduclaw-os_<version>.efi entry; deleting nothing"
    exit 0
}
running_key=$(ver_key "$running_ver") || { log "running version '$running_ver' does not parse; deleting nothing"; exit 0; }
if key_lt "$running_key" "$floor_key"; then
    log "running entry $running_ver is below the floor $floor; deleting nothing"
    exit 0
fi

esp=$(bootctl --print-esp-path 2>/dev/null) || esp=/boot
dir="$esp/EFI/Linux"
[[ -d $dir && ! -L $dir ]] || { log "$dir not found; nothing to do"; exit 0; }

status=0
shopt -s nullglob
for path in "$dir"/duduclaw-os_*.efi; do
    name=${path##*/}
    [[ -f $path && ! -L $path ]] || continue
    v=$(entry_version "$name") || continue
    [[ $v == "$running_ver" ]] && continue
    key=$(ver_key "$v") || { log "keeping $name: version '$v' does not parse"; continue; }
    if key_lt "$key" "$floor_key"; then
        if rm -f -- "$path"; then
            log "deleted $name (version $v is below the rollback floor $floor)"
        else
            log "failed to delete $name"
            status=1
        fi
    fi
done
sync
exit "$status"
