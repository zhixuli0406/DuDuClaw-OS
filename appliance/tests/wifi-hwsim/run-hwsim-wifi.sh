#!/usr/bin/env bash
# D4a-9 — closed-loop Wi-Fi walkthrough against simulated radios.
#
# Runs INSIDE a DuDuClaw OS VM (or any Debian box with the same packages), as
# root. Drives the real gateway RPC surface end to end with no Wi-Fi hardware:
#
#   mac80211_hwsim radio0 -> hostapd, WPA2-PSK AP
#   mac80211_hwsim radio1 -> iwd, the client the gateway controls
#
#   scan -> connect -> status -> forget, over BOTH entry points:
#     * POST /api/first-run/network/*  (the OOBE pre-auth path the shell uses)
#     * network.* over the /ws RPC     (the dashboard path; the only one with
#                                       wifi_forget)
#   ...then a credential-persistence check: the .psk must be backed by the
#   DATA partition, and iwd must reconnect by itself after a restart. That last
#   part is the regression guard for the A/B-update failure documented in
#   commercial/docs/DESIGN-network-settings-2026-08.md section 4.2 — the one
#   that would take a Wi-Fi-only box permanently offline after an OS update.
#
# Test-only packages (hostapd / iw / iproute2) are NOT in the shipping image by
# decision G-②. Inject them into a COPY of the raw disk first — see
# inject-test-packages.sh in this directory.
#
# Usage (inside the VM):
#     ./run-hwsim-wifi.sh
# Environment overrides: WIFI_CI_PORT, WIFI_CI_HOME, WIFI_CI_SSID, WIFI_CI_PSK
#
# Exit code 0 = every check passed. Non-zero = at least one FAIL line above the
# summary. Every check prints PASS/FAIL on its own line so serial-console
# output can be graded mechanically.

set -uo pipefail

PORT="${WIFI_CI_PORT:-28789}"
CI_HOME="${WIFI_CI_HOME:-/data/wifi-ci-home}"
SSID="${WIFI_CI_SSID:-DuDuClaw-CI}"
PSK="${WIFI_CI_PSK:-ci-passw0rd}"
ADMIN_PW="wifi-ci-admin-pw"
BASE="http://127.0.0.1:${PORT}"
CONF_DIR=/etc/duduclaw-wifi-ci
IWD_DROPIN=/etc/systemd/system/iwd.service.d/10-wifi-ci-iface.conf
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASSES=0
FAILURES=0
GATEWAY_PID=""

step() { echo; echo "=== $* ==="; }
pass() { PASSES=$((PASSES + 1)); echo "PASS: $*"; }
fail() { FAILURES=$((FAILURES + 1)); echo "FAIL: $*"; }
# Reads one field out of a JSON document on stdin. python3 is in the image;
# jq is not. Prints nothing (and succeeds) when the path is absent, so callers
# compare against the empty string rather than having to trap an exit code.
jget() { python3 -c '
import json, sys
doc = json.load(sys.stdin)
for key in sys.argv[1:]:
    if doc is None:
        break
    doc = doc.get(key) if isinstance(doc, dict) else None
print("" if doc is None else (json.dumps(doc, ensure_ascii=False) if isinstance(doc, (dict, list)) else doc))
' "$@" 2>/dev/null; }

cleanup() {
    step "cleanup"
    [[ -n "$GATEWAY_PID" ]] && kill "$GATEWAY_PID" 2>/dev/null
    pkill hostapd 2>/dev/null
    rm -f "$IWD_DROPIN"
    rmdir /etc/systemd/system/iwd.service.d 2>/dev/null
    systemctl daemon-reload 2>/dev/null
    systemctl restart iwd 2>/dev/null
    rm -rf "$CI_HOME"
    echo "cleanup done (the scratch gateway home, hostapd, and the iwd drop-in are gone;"
    echo " credentials joined during this run were forgotten in step 8)"
}
trap cleanup EXIT

# ── 0. preflight ─────────────────────────────────────────────────────────
step "0 preflight"
[[ "$(id -u)" == "0" ]] || { echo "must run as root"; exit 2; }
for bin in hostapd iw curl python3 /usr/local/bin/duduclaw /usr/libexec/iwd; do
    if [[ -x "$bin" ]] || command -v "$bin" >/dev/null 2>&1; then
        echo "found: $bin"
    else
        echo "MISSING: $bin — see inject-test-packages.sh"; exit 2
    fi
done

# ── 1. simulated radios ──────────────────────────────────────────────────
step "1 mac80211_hwsim (2 radios)"
# iwd must NOT be running unrestricted when the radios appear: it would take
# over BOTH phys, and later re-binding it tears the AP interface down to
# managed mode behind hostapd's back (live run 2026-08-23 — the AP came up,
# then silently died when step 3 restarted iwd; every scan saw nothing).
systemctl stop iwd 2>/dev/null
modprobe -r mac80211_hwsim 2>/dev/null
sleep 1
if modprobe mac80211_hwsim radios=2; then pass "hwsim loaded"; else fail "hwsim modprobe"; exit 1; fi
sleep 2
iw dev | grep -E "Interface"
# Interface names are NOT stable across reloads (live run 2026-08-23: a box
# whose udev had already seen hwsim once handed out wlan2/wlan3, and the
# original wlan0/wlan1 assumption killed hostapd before anything ran) — so
# detect the two radios instead of assuming. phy NUMBERS keep incrementing
# too, so nothing below may key off phyN either.
mapfile -t HWSIM_IFS < <(iw dev | awk '/Interface/{print $2}' | grep -v '^hwsim' | sort | head -2)
AP_IF="${HWSIM_IFS[0]:-}"
CLIENT_IF="${HWSIM_IFS[1]:-}"
if [[ -z "$AP_IF" || -z "$CLIENT_IF" ]]; then
    fail "could not find two hwsim interfaces"; iw dev; exit 1
fi
# iwd manages PHYs, not interface names: on takeover it DELETES the kernel's
# default interface and creates its own (a fresh name — live run 2026-08-23
# saw wlan1 come back as wlan9), so an `-i <name>` whitelist can never match
# and iwd ends up managing nothing ("No default interface for wiphy N").
# Restrict by phy instead.
CLIENT_PHY="phy$(iw dev "$CLIENT_IF" info | awk '/wiphy/{print $2}')"
if [[ "$CLIENT_PHY" == "phy" ]]; then fail "could not resolve $CLIENT_IF's phy"; exit 1; fi
echo "AP_IF=$AP_IF CLIENT_IF=$CLIENT_IF CLIENT_PHY=$CLIENT_PHY"

# ── 3. iwd restricted to the client radio ────────────────────────────────
step "2 iwd bound to $CLIENT_PHY only"
# Without -i, iwd claims EVERY phy including the one hostapd is beaconing on,
# silently taking the AP down and leaving the client with nothing to find.
mkdir -p /etc/systemd/system/iwd.service.d
cat > "$IWD_DROPIN" <<EOF
[Service]
ExecStart=
ExecStart=/usr/libexec/iwd -p $CLIENT_PHY
EOF
systemctl daemon-reload
systemctl restart iwd
sleep 3
if [[ "$(systemctl is-active iwd)" == "active" ]]; then pass "iwd active"; else fail "iwd not active"; systemctl status iwd --no-pager | tail -20; exit 1; fi

# ── 2. AP on the first hwsim radio ───────────────────────────────────────────────────────
step "3 hostapd WPA2-PSK AP on $AP_IF"
# Config deliberately NOT in /tmp: a reboot wipes it and `hostapd -B` then
# fails silently (it only says so in its own log), which once made a whole
# measurement round read as "neither backend connected".
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/hostapd.conf" <<EOF
interface=$AP_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=1
wpa=2
wpa_passphrase=$PSK
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
ip link set "$AP_IF" down 2>/dev/null || iw dev "$AP_IF" set type managed 2>/dev/null
if hostapd -B -t "$CONF_DIR/hostapd.conf" > "$CONF_DIR/hostapd.log" 2>&1; then
    sleep 4
    if iw dev "$AP_IF" info | grep -q "type AP"; then pass "AP up on channel 1"; else fail "$AP_IF is not in AP mode"; fi
else
    fail "hostapd failed to start"; tail -5 "$CONF_DIR/hostapd.log"; exit 1
fi


# ── 4. scratch gateway (fresh, therefore UNCLAIMED) ──────────────────────
step "4 scratch gateway on :$PORT"
# A fresh home is what makes /api/first-run/* live: those routes require
# loopback + unclaimed + appliance, and go inert the moment an admin password
# is set. The production gateway on :18789 is left untouched.
rm -rf "$CI_HOME"; mkdir -p "$CI_HOME"
DUDUCLAW_HOME="$CI_HOME" DUDUCLAW_APPLIANCE=1 DUDUCLAW_PORT="$PORT" DUDUCLAW_BIND=127.0.0.1 \
    /usr/local/bin/duduclaw run --yes > "$CONF_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!
for _ in $(seq 1 40); do
    curl -fsS "$BASE/health" >/dev/null 2>&1 && break
    sleep 1
done
if curl -fsS "$BASE/health" >/dev/null 2>&1; then pass "gateway responding"; else fail "gateway never came up"; tail -30 "$CONF_DIR/gateway.log"; exit 1; fi
claimable="$(curl -fsS "$BASE/api/first-run/status" | jget claimable)"
if [[ "$claimable" == "True" || "$claimable" == "true" ]]; then pass "instance is unclaimed (first-run routes live)"; else fail "instance reports claimable=$claimable"; fi

# ── 5. OOBE path: scan ───────────────────────────────────────────────────
step "5 first-run scan"
scan="$(curl -fsS -X POST -H 'Content-Type: application/json' -d '{"rescan":true}' "$BASE/api/first-run/network/scan")"
echo "$scan"
if [[ "$(echo "$scan" | jget ok)" == "True" || "$(echo "$scan" | jget ok)" == "true" ]]; then pass "scan ok"; else fail "scan: $(echo "$scan" | jget code)"; fi
if echo "$scan" | grep -qF "\"$SSID\""; then pass "scan found $SSID"; else fail "scan did not list $SSID"; fi

# ── 6. OOBE path: connect ────────────────────────────────────────────────
step "6 first-run connect"
conn="$(curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"ssid": sys.argv[1], "psk": sys.argv[2]}))' "$SSID" "$PSK")" \
    "$BASE/api/first-run/network/connect")"
echo "$conn"
if [[ "$(echo "$conn" | jget ok)" == "True" || "$(echo "$conn" | jget ok)" == "true" ]]; then pass "connect ok"; else fail "connect: $(echo "$conn" | jget code) / $(echo "$conn" | jget message)"; fi
echo "--- AP-side corroboration (the client really associated) ---"
iw dev "$AP_IF" station dump | head -6
grep -iE "AP-STA-CONNECTED" "$CONF_DIR/hostapd.log" | tail -2

# Negative case: a wrong password must classify as wrong_password, not as a
# generic failure. This is the single most user-visible classification in the
# nine-way error table, so it gets its own assertion.
step "6b first-run connect with a WRONG password"
# The stored credential from step 6 must go first: iwd treats a known
# network as known — Network.Connect() uses the SAVED psk and never asks
# the agent, so a wrong-password attempt right after a successful join
# "succeeds" with the old key and proves nothing (live run 2026-08-23).
# There is deliberately no first-run forget route, so drop the .psk file
# the way an operator-less test may: iwd watches its state dir inotify-style.
rm -f /var/lib/iwd/*.psk
sleep 2
bad="$(curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"ssid": sys.argv[1], "psk": "definitely-not-it"}))' "$SSID")" \
    "$BASE/api/first-run/network/connect")"
echo "$bad"
if [[ "$(echo "$bad" | jget code)" == "wrong_password" ]]; then pass "wrong password classifies as wrong_password"; else fail "wrong password classified as '$(echo "$bad" | jget code)'"; fi
# Re-join with the right one so the rest of the run has a live connection.
curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"ssid": sys.argv[1], "psk": sys.argv[2]}))' "$SSID" "$PSK")" \
    "$BASE/api/first-run/network/connect" >/dev/null

# ── 7. OOBE path: status ─────────────────────────────────────────────────
step "7 first-run status"
st="$(curl -fsS "$BASE/api/first-run/network/status")"
echo "$st"
if [[ "$(echo "$st" | jget result wifi state)" == "connected" ]]; then pass "wifi.state=connected"; else fail "wifi.state=$(echo "$st" | jget result wifi state)"; fi
if [[ "$(echo "$st" | jget result wifi ssid)" == "$SSID" ]]; then pass "wifi.ssid=$SSID"; else fail "wifi.ssid=$(echo "$st" | jget result wifi ssid)"; fi
# The test AP has no DHCP server and no upstream, so no address and
# internet != online are the CORRECT answers here. What matters is that the
# link layer and the IP layer are reported separately rather than collapsed
# into one "failed" — that separation is the whole point of iwd + networkd.
echo "note: ip.addresses / internet are expected to be empty / offline on this"
echo "      AP-only test bench; the assertion is that they are reported apart"
echo "      from wifi.state, not that they are online."

# ── 8. dashboard path: claim, login, then network.* over /ws ─────────────
step "8 dashboard RPC (scan / status / forget)"
curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"password\":\"$ADMIN_PW\"}" "$BASE/api/first-run/claim" >/dev/null
jwt="$(curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "{\"email\":\"admin@local\",\"password\":\"$ADMIN_PW\"}" "$BASE/api/login" | jget access_token)"
if [[ -n "$jwt" ]]; then pass "admin token obtained"; else fail "login produced no access_token"; fi

# The first-run routes must go inert the moment the instance is claimed.
after_claim="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"rescan":false}' "$BASE/api/first-run/network/scan")"
if [[ "$after_claim" == "403" ]]; then pass "first-run network routes went inert after claim (403)"; else fail "first-run scan still answered $after_claim after claim"; fi

if [[ -n "$jwt" ]]; then
    ws() { python3 "$HERE/ws_rpc.py" --url "ws://127.0.0.1:${PORT}/ws" --jwt "$jwt" "$@"; }
    out="$(ws network.status '{}')" && pass "network.status ok" || fail "network.status: $out"
    echo "$out"
    out="$(ws network.wifi_scan '{"rescan":false}')" && pass "network.wifi_scan ok" || fail "network.wifi_scan: $out"
    out="$(ws network.wifi_forget "$(python3 -c 'import json,sys; print(json.dumps({"ssid": sys.argv[1]}))' "$SSID")")" \
        && pass "network.wifi_forget ok" || fail "network.wifi_forget: $out"
    if ls /var/lib/iwd/*.psk >/dev/null 2>&1; then fail "a .psk survived forget"; else pass "forget removed the stored credential"; fi
    out="$(ws network.wifi_forget '{"ssid":"no-such-network-anywhere"}')" \
        && fail "forgetting an unknown SSID reported success" \
        || { echo "$out" | grep -q not_found && pass "unknown SSID forget -> not_found" || fail "unknown SSID forget -> $out"; }
fi

# ── 9. credentials live on the DATA partition (A/B-update guard) ─────────
step "9 credential persistence"
curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"ssid": sys.argv[1], "psk": sys.argv[2]}))' "$SSID" "$PSK")" \
    "$BASE/api/first-run/network/connect" >/dev/null 2>&1
# ^ inert after claim; rejoin over the dashboard path instead.
if [[ -n "${jwt:-}" ]]; then
    python3 "$HERE/ws_rpc.py" --url "ws://127.0.0.1:${PORT}/ws" --jwt "$jwt" network.wifi_connect \
        "$(python3 -c 'import json,sys; print(json.dumps({"ssid": sys.argv[1], "psk": sys.argv[2]}))' "$SSID" "$PSK")" >/dev/null
fi
sleep 2
findmnt -no SOURCE,TARGET /var/lib/iwd || echo "(no bind mount — this is the pre-D4a-2 layout)"
if [[ -e "/data/network/iwd/${SSID}.psk" ]]; then pass "credential landed on /data/network/iwd"; else fail "no credential under /data/network/iwd"; fi
backing="$(findmnt -no SOURCE -T "/data/network/iwd/${SSID}.psk" 2>/dev/null)"
echo "backing device: ${backing:-<unknown>}"
perms="$(stat -c '%a %U:%G' /data/network/iwd 2>/dev/null)"
if [[ "$perms" == "700 root:root" ]]; then pass "credential directory is 700 root:root"; else fail "credential directory perms: $perms"; fi

step "9b reconnect after an iwd restart (no password re-entry)"
systemctl restart iwd
sleep 10
state="$(python3 "$HERE/ws_rpc.py" --url "ws://127.0.0.1:${PORT}/ws" --jwt "${jwt:-}" network.status '{}' 2>/dev/null | jget wifi state)"
if [[ "$state" == "connected" ]]; then pass "auto-reconnected from the persisted credential"; else fail "state after restart: ${state:-<none>}"; fi
# Leave no credential behind on the test box.
[[ -n "${jwt:-}" ]] && python3 "$HERE/ws_rpc.py" --url "ws://127.0.0.1:${PORT}/ws" --jwt "$jwt" network.wifi_forget \
    "$(python3 -c 'import json,sys; print(json.dumps({"ssid": sys.argv[1]}))' "$SSID")" >/dev/null 2>&1

# ── summary ──────────────────────────────────────────────────────────────
step "SUMMARY"
echo "passed: $PASSES   failed: $FAILURES"
[[ "$FAILURES" == "0" ]] && echo "HWSIM_WIFI_RESULT=PASS" || echo "HWSIM_WIFI_RESULT=FAIL"
exit $((FAILURES > 0))
