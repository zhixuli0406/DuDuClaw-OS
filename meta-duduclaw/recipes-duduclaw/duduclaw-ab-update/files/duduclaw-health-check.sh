#!/usr/bin/env bash
# DuDuClaw OS boot health gate — Yocto port (Y8-1, 2026-08-27), verbatim
# body copy of the Debian appliance line's
# appliance/mkosi.extra/usr/local/sbin/duduclaw-health-check.sh (only this
# header changed). The script itself is distro-agnostic: it depends on
# nothing but bash/curl/awk/date/mktemp, all already present in this
# Yocto image, and talks to the gateway/sysd over the same HTTP-on-loopback
# and Unix-socket protocols regardless of which base OS packaged them —
# porting it here required zero logic changes, only re-verifying its
# assumptions still hold on this line (they do: duduclaw-sysd.service's
# RuntimeDirectory=duduclaw here matches this script's own
# DUDUCLAW_SYSD_SOCKET default of /run/duduclaw/sysd.sock, and
# duduclaw-health-check.service on this line sets the same
# DUDUCLAW_HOME=/data/duduclaw this script defaults to).
#
# WHAT THIS DECIDES: whether *this* boot gets blessed. The unit that runs it
# (duduclaw-health-check.service) is RequiredBy=boot-complete.target, and
# systemd-bless-boot.service only runs once boot-complete.target is reached.
# So exit 0 here => the boot counter in the UKI's filename is cleared and the
# running version becomes permanent; exit non-zero => nothing clears the
# counter, the next boot decrements it, and after TriesLeft boots sd-boot
# picks the previous entry. There is no other consumer of this exit code.
#
# WHICH DIRECTION TO ERR: a false FAILURE is worse than a false success here,
# because it retires a version that was actually fine (and, on the factory
# image, marks the only entry there is as bad). Hence the generous budget
# (DUDUCLAW_HEALTH_TIMEOUT, default 180s) and hence every probe answers
# "healthy" only on positive evidence but is given the full budget to
# produce it.
#
# WHAT IS CHECKED, AND WHY EXACTLY THESE TWO
#   1. gateway GET /healthz => 200 and "ok":true. This is the only signal in
#      the whole system that means "really alive": the handler also reports
#      the cron/heartbeat schedulers' last tick and returns 503 when either
#      has stalled (crates/duduclaw-gateway/src/server.rs::healthz_handler —
#      born from the 2026-08 incident where HTTP kept answering for days
#      while every schedule was silently dead). `systemctl is-active` cannot
#      see that; a Restart=always service in a crash loop never reaches
#      `failed` either.
#   2. duduclaw-sysd's unix socket accepts a connection. That is the ability
#      to recover itself — without it the box can neither update nor roll
#      back, which is precisely the state that must not be blessed.
#
# WHAT IS DELIBERATELY *NOT* CHECKED
#   * Network reachability. Rolling back cannot fix a unplugged cable or a
#     dead upstream, and a rollback triggered by the environment retires a
#     good image for nothing. Only regressions the new image itself caused
#     should roll back.
#   * The compositor / shell / kiosk session. This Yocto line's own "開機即
#     殼" work does run a graphical kiosk under QEMU (duduclaw-comp/-shell,
#     unlike the Debian line's headless-first shape) — but gating boot
#     health on the display would still be wrong for the same underlying
#     reason the Debian line's comment gives: a real value-prop of this
#     appliance is unattended headless operation, and duduclaw-kiosk.service
#     is a clean skip with no display attached, so any box running headless
#     would become permanently unblessable if this were a hard gate.
#   * systemd-boot-check-no-failures. upstream's own man page says it is
#     "probably not suitable for deployment in most scenarios"; zero failed
#     units is necessary-but-not-sufficient and would add false failures
#     (any unrelated unit failing would retire the OS version).
#
# Full argument: commercial/docs/DESIGN-ab-update-rollback-2026-08.md §3.
set -uo pipefail

BUDGET="${DUDUCLAW_HEALTH_TIMEOUT:-180}"
POLL_INTERVAL="${DUDUCLAW_HEALTH_POLL_INTERVAL:-3}"
SYSD_SOCK="${DUDUCLAW_SYSD_SOCKET:-/run/duduclaw/sysd.sock}"
CONFIG="${DUDUCLAW_HOME:-/data/duduclaw}/config.toml"

log() { echo "[health-check] $*"; }

# Gateway port: config.toml [gateway] port wins, 18789 is the built-in
# default (duduclaw_core::config::gateway_port_for_home). Parsed
# section-aware — a bare `grep port` would happily pick up an `[odoo]` or
# `[relay]` port and probe the wrong listener.
resolve_port() {
    local from_config=""
    if [[ -r "$CONFIG" ]]; then
        from_config="$(awk '
            /^[[:space:]]*\[/ { section=$0; gsub(/[[:space:]]/, "", section) }
            section=="[gateway]" && /^[[:space:]]*port[[:space:]]*=/ {
                v=$0; sub(/.*=[[:space:]]*/, "", v); gsub(/[^0-9]/, "", v);
                if (v != "") { print v; exit }
            }' "$CONFIG" 2>/dev/null)"
    fi
    if [[ "$from_config" =~ ^[0-9]+$ ]] && (( from_config > 0 && from_config < 65536 )); then
        echo "$from_config"
    else
        echo 18789
    fi
}

PORT="$(resolve_port)"
HEALTH_URL="http://127.0.0.1:${PORT}/healthz"

# Returns 0 only on HTTP 200 with "ok":true. A 503 (stalled scheduler) and a
# connection refusal are both "not yet / not healthy" and keep the loop going
# until the budget runs out.
LAST_HEALTH_NOTE="no probe yet"
probe_gateway() {
    local body code
    body="$(mktemp)" || { LAST_HEALTH_NOTE="mktemp failed"; return 1; }
    code="$(curl -sS --max-time 5 -o "$body" -w '%{http_code}' "$HEALTH_URL" 2>/dev/null)"
    if [[ "$code" != "200" ]]; then
        LAST_HEALTH_NOTE="http=${code:-none} body=$(head -c 200 "$body" 2>/dev/null | tr -d '\n')"
        rm -f "$body"
        return 1
    fi
    # Compact serde_json output, so this substring is exactly the field —
    # not a prefix of some longer key (`"ok":` is only ever produced by the
    # healthz handler's own `ok` field).
    if grep -qF '"ok":true' "$body"; then
        LAST_HEALTH_NOTE="http=200 ok=true"
        rm -f "$body"
        return 0
    fi
    LAST_HEALTH_NOTE="http=200 but ok!=true: $(head -c 200 "$body" 2>/dev/null | tr -d '\n')"
    rm -f "$body"
    return 1
}

# The socket FILE existing proves nothing — a crashed daemon can leave its
# socket behind. So this actually connects and reads the answer.
#
# curl speaks HTTP at a daemon that speaks line-delimited JSON. `--http0.9`
# is what makes that useful instead of merely tolerable: without it curl
# aborts with "Received HTTP/0.9 when not allowed" (exit 1) and throws the
# reply away; with it, the daemon's own structured refusal comes back as the
# body. On this Yocto line duduclaw-sysd.service has no --allowed-uid
# configured at all yet (see that unit's own header comment), so the
# expected reply here is duduclaw-sysd's fail-closed "unauthorized" JSON for
# every peer including root — a positive proof the daemon is alive, parsing
# and answering, which is exactly what the gate needs to know. Cheaper and
# more honest than inferring liveness from an error code.
#
# Two tiers, deliberately: a missing socket or a refused connect is the only
# thing that FAILS. A connection that succeeds but produces no recognisable
# reply still passes, with a weaker note in the journal — a future sysd that
# hangs up on an unauthorized peer without answering must not start rolling
# back healthy machines.
LAST_SYSD_NOTE="no probe yet"
probe_sysd() {
    if [[ ! -S "$SYSD_SOCK" ]]; then
        LAST_SYSD_NOTE="socket $SYSD_SOCK missing (duduclaw-sysd is not running: \
its RuntimeDirectory is removed with the service)"
        return 1
    fi
    local reply rc
    reply="$(curl -sS --max-time 5 --http0.9 --unix-socket "$SYSD_SOCK" http://localhost/ 2>&1)"
    rc=$?
    if (( rc == 7 )); then
        LAST_SYSD_NOTE="socket present but connect refused (curl 7) — stale socket, no listener"
        return 1
    fi
    if (( rc == 0 )) && [[ "$reply" == *'"ok":'* ]]; then
        LAST_SYSD_NOTE="daemon answered the probe ($(printf '%.60s' "$reply"))"
        return 0
    fi
    LAST_SYSD_NOTE="connected (curl rc=$rc) but no structured reply: $(printf '%.80s' "$reply")"
    return 0
}

log "budget=${BUDGET}s gateway=$HEALTH_URL sysd=$SYSD_SOCK"

started="$(date +%s)"
deadline=$(( started + BUDGET ))
attempt=0
while :; do
    attempt=$(( attempt + 1 ))
    if probe_gateway && probe_sysd; then
        log "PASS after $(( $(date +%s) - started ))s / ${attempt} attempt(s): ${LAST_HEALTH_NOTE}; sysd: ${LAST_SYSD_NOTE}"
        log "this boot is eligible for blessing (boot-complete.target may proceed)"
        exit 0
    fi
    now="$(date +%s)"
    if (( now >= deadline )); then
        log "FAIL after $(( now - started ))s / ${attempt} attempt(s)"
        log "  gateway: ${LAST_HEALTH_NOTE}"
        log "  sysd:    ${LAST_SYSD_NOTE}"
        log "this boot will NOT be blessed; if boot counting is armed the next"
        log "boot decrements the counter and sd-boot eventually falls back."
        exit 1
    fi
    sleep "$POLL_INTERVAL"
done
