#!/bin/sh
# DuDuClaw OS — scheduled quick secaudit self-scan.
#
# WS-3/自掃 timer (2026-09-01, DESIGN-os-security-line-2026-09.md §2
# secaudit 遷入 D2': "systemd timer 排程自掃（quick profile 掃 /data 可寫
# 執行面...）"; 拍板 D4: "預設開、每日 quick、範圍=/data 可寫執行面").
#
# Scope for THIS pass: /data/duduclaw only ("D4 拍板『/data 可寫執行面』
# ——用 /data/duduclaw 起步並文件化範圍收斂留 P1"). This is deliberately
# narrower than a whole-disk scan — skills/compat.d declarations/agent
# workdirs/anything else an agent or operator can write onto this
# appliance all live under this tree; the read-only /usr base is not the
# threat model a self-scan needs to cover repeatedly (it cannot change
# between scans without an A/B update, which has its own signature
# verification). Narrowing further (or wider) is explicitly left to a P1
# follow-up, not decided here.
#
# `--profile quick` (not `deep`): the CLI's own help text is explicit —
# quick is "scanners only" (semgrep/gitleaks/cargo-audit orchestration),
# no AI deep-audit step, hence no LLM/agent/network dependency at all.
# This is what makes an UNCONDITIONAL daily timer safe to ship on a
# machine that may be offline (拍板 D4's own "離線機自動降級 quick" note —
# this script only ever requests quick, so there is no "downgrade" branch
# to implement here: it never asks for more).
set -e

SCAN_PATH="/data/duduclaw"
REPORT_DIR="/data/duduclaw/secaudit/reports"

# Belt-and-braces: duduclaw-secaudit-scan.service already carries
# ConditionPathExists=/data/duduclaw (skips the whole unit cleanly on an
# image with no /data partition), but mkdir -p here is what actually
# creates REPORT_DIR itself the first time this ever runs — not assumed
# to pre-exist just because SCAN_PATH does.
mkdir -p "${REPORT_DIR}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_PATH="${REPORT_DIR}/scheduled-${TS}.json"

# `--save` additionally writes a duplicate, dashboard-discoverable copy
# under <DUDUCLAW_HOME>/secaudit/reports/ (the CLI's own convention, per
# --help: "Also save a timestamped copy of the report... read by the
# dashboard") — kept on top of --report (not instead of it) so this
# script's own explicit, timestamped ${REPORT_PATH} always exists at a
# name this unit itself controls, regardless of whatever naming --save's
# own internal timestamp format produces; the dashboard's existing three
# secaudit RPCs already read the --save copy, this script does not need
# to know or match its exact filename.
#
# Exit-code translation, NOT a bare `exec` — per the CLI's own --help
# contract: 0 = no finding at/above --fail-on, 1 = at least one does, 2 =
# a genuine infra error (bad repo path, unwritable --report/--save path).
# This is a background REPORTING run, not a CI pass/fail gate — a normal
# High-severity finding is exactly the expected, routine output this
# timer exists to produce (consumed downstream by the report file /
# dashboard / D2's SecurityEvent hookup, not by systemd unit state), so
# exit 1 must NOT make this unit report as "failed" (that would mean
# every ordinary finding shows up as a service failure in `systemctl
# status`/journal noise, and could trip any future OnFailure= monitoring
# for a condition that isn't actually infrastructure trouble). Exit 2
# (infra error) is a real problem with the scan mechanism itself and DOES
# propagate as a unit failure.
set +e
/usr/bin/duduclaw secaudit "${SCAN_PATH}" \
    --profile quick \
    --report "${REPORT_PATH}" \
    --save
rc=$?
set -e
if [ "${rc}" -eq 2 ]; then
    exit 1
fi
exit 0
