#!/bin/sh
# DuDuClaw OS — Entry B boot audit marker.
#
# Authority: commercial/docs/DESIGN-maintenance-mode-2026-08.md §3.4. Run
# automatically by duduclaw-rescue-audit.service, root-owned, BEFORE the
# rescue shell starts.
#
# WS-3/B3 (2026-09-01, DESIGN-os-security-line-2026-09.md §2 支柱二 B3):
# primary write target is now /data/duduclaw/audit/rescue/ — /data exists
# on this line as of Y8-1/Y9-1 (the original 2026-08-26 comment here, now
# out of date, said it did not; superseded, not silently left stale). This
# closes two real gaps at once, checked not assumed:
#   (1) durability — /data survives an A/B slot switch/re-flash (root does
#       not — the update mechanism replaces root wholesale), so a rescue
#       boot marker written to root was forensic evidence that could itself
#       be wiped by the very update mechanism a future investigation might
#       be trying to audit.
#   (2) writability — duduclaw-rescue-root-lock.service (same target,
#       Before=this unit) remounts `/` read-only BEFORE this script runs;
#       on the OLD /var/log/duduclaw/ target (root-resident, no /var
#       overlay on this line yet) every mkdir/touch below would have hit
#       EROFS. /data is a separately-mounted partition, unaffected by
#       root's own read-only remount, so writes here still succeed under
#       the exact same ordering that would break the old path.
#
# FALLBACK, not a hard requirement: /data could still be genuinely absent
# (disk fault serious enough to need rescue mode in the first place) or
# mounted-but-unwritable (full, or mounted ro for its own reasons) — the
# owning .service unit's RequiresMountsFor=/data only guarantees the mount
# UNIT resolved, not that a write will succeed. Rather than let `set -e`
# hard-fail the whole unit (and lose the marker entirely, the exact
# failure mode B3 exists to close) when /data doesn't pan out, this script
# tries /data first and falls back to the pre-B3 root path — degrading
# audibly (a distinct log line so the fallback itself is visible to
# whoever reads the journal later), not silently, per this project's own
# "誠實回報" convention: an empty/degraded result must say so, never
# masquerade as the primary path having worked.
set -e

PRIMARY_DIR="/data/duduclaw/audit/rescue"
FALLBACK_DIR="/var/log/duduclaw"
LOG_FILE="rescue-boot-audit.jsonl"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"

if mkdir -p "${PRIMARY_DIR}" 2>/dev/null && chmod 0700 "${PRIMARY_DIR}" 2>/dev/null; then
	LOG_DIR="${PRIMARY_DIR}"
else
	# /data unavailable or unwritable — fall back to the old root path.
	# `|| true` on the mkdir/chmod pair below: if THIS also fails (root is
	# read-only per the ordering finding above, and /data was also a bust)
	# there is nowhere left to write and the marker is genuinely lost —
	# logged to the journal either way so the gap itself is on record even
	# when the file cannot be.
	logger -t duduclaw-rescue "WARNING: /data/duduclaw/audit/rescue unavailable, falling back to ${FALLBACK_DIR} (degraded — see duduclaw-rescue-audit.sh)" 2>/dev/null || true
	mkdir -p "${FALLBACK_DIR}" 2>/dev/null && chmod 0700 "${FALLBACK_DIR}" 2>/dev/null || true
	LOG_DIR="${FALLBACK_DIR}"
fi

LOG_PATH="${LOG_DIR}/${LOG_FILE}"
touch "${LOG_PATH}"
chmod 0600 "${LOG_PATH}"

printf '{"event":"entry_b_rescue_boot","booted_at":"%s","boot_id":"%s","audit_dir":"%s"}\n' \
	"${TS}" "${BOOT_ID}" "${LOG_DIR}" >>"${LOG_PATH}"

# Best-effort tamper-evidence: ext4's append-only attribute means even a
# LATER root process cannot truncate/edit prior lines, only append new
# ones — silently skipped if chattr is unavailable or the filesystem
# doesn't support it (defense-in-depth nicety, not a hard requirement of
# this ticket; the primary control is still "only root-owned automatic
# code writes here, the rescue account itself never touches this
# directory at all" — duduclaw-rescue is not in any group with write
# access to /data/duduclaw or /var/log/duduclaw).
chattr +a "${LOG_PATH}" 2>/dev/null || true

logger -t duduclaw-rescue "Entry B rescue mode booted at ${TS} (boot_id=${BOOT_ID}, audit_dir=${LOG_DIR})" 2>/dev/null || true
