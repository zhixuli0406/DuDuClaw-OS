#!/bin/sh
# DuDuClaw OS — Entry B boot audit marker.
#
# Authority: commercial/docs/DESIGN-maintenance-mode-2026-08.md §3.4. Run
# automatically by duduclaw-rescue-audit.service, root-owned, BEFORE the
# rescue shell starts — see that unit's own comment for why this must not
# depend on the operator cooperating, and for the honest limit on where
# this currently writes to (local rootfs, not a `/data`-equivalent
# partition, which does not exist yet on this Yocto line).
set -e

LOG_DIR="/var/log/duduclaw"
LOG_FILE="${LOG_DIR}/rescue-boot-audit.jsonl"

mkdir -p "${LOG_DIR}"
chmod 0700 "${LOG_DIR}"
touch "${LOG_FILE}"
chmod 0600 "${LOG_FILE}"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"

printf '{"event":"entry_b_rescue_boot","booted_at":"%s","boot_id":"%s"}\n' \
	"${TS}" "${BOOT_ID}" >>"${LOG_FILE}"

# Best-effort tamper-evidence: ext4's append-only attribute means even a
# LATER root process cannot truncate/edit prior lines, only append new
# ones — silently skipped if chattr is unavailable or the filesystem
# doesn't support it (defense-in-depth nicety, not a hard requirement of
# this ticket; the primary control is still "only root-owned automatic
# code writes here, the rescue account itself never touches this file at
# all" — duduclaw-rescue is not in any group with write access to
# /var/log/duduclaw).
chattr +a "${LOG_FILE}" 2>/dev/null || true

logger -t duduclaw-rescue "Entry B rescue mode booted at ${TS} (boot_id=${BOOT_ID})" 2>/dev/null || true
