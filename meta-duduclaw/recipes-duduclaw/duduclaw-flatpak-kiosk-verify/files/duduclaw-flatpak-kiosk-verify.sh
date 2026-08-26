#!/usr/bin/env bash
# duduclaw-flatpak-kiosk-verify.sh — Y3-2 "first light" verification that
# DuDuClaw OS's Yocto-built environment can run a Flatpak-packaged Chromium
# under a plain systemd SYSTEM service (no logind session), pointed at the
# gateway dashboard, using the --kiosk flag. This is a standalone
# VERIFICATION script, not the production kiosk launcher: duduclaw-comp/
# duduclaw-shell have no Yocto recipe yet (Y2-3 status table), so there is
# no real compositor to hand this Chromium instance a Wayland socket. It
# runs Chromium's own --headless=new path instead, exactly matching the
# already-validated methodology in
# research/native-os-2026-08/flatpak-carrier-2026-08.md §2 (the same flags,
# the same dbus-run-session wrapper, the same "systemd service not manual
# shell" discipline) — first light for the mechanism, not for the pixels.
#
# Ticket: Y3-2. See meta-duduclaw/recipes-duduclaw/duduclaw-flatpak-kiosk-
# verify/duduclaw-flatpak-kiosk-verify.bb for the systemd unit this runs
# under and duduclaw-polkit-flatpak/ for the OS-side permission rule that
# lets this run without an interactive polkit prompt.

set -uo pipefail

log() { echo "duduclaw-flatpak-kiosk-verify: $*" >&2; }

# Directory comes from the systemd unit's LogsDirectory=, writable by the
# unprivileged User= that unit runs this script as (plain /var/log is
# root:root 0755 and would not be).
RESULT_FILE=/var/log/duduclaw-flatpak-kiosk-verify/duduclaw-flatpak-kiosk-verify.result
INSTALLATION=verify
INSTALL_PATH=/var/lib/duduclaw-flatpak-verify
PROFILE_DIR="$INSTALL_PATH/chromium-profile"
DASHBOARD_URL="http://127.0.0.1:18789/"
APP_ID="${DUDUCLAW_VERIFY_APP_ID:-org.chromium.Chromium}"
# Conservative floor: refuse to even attempt the real Chromium install
# below this much free space on the partition the named installation lives
# on (research spike measured Chromium's install footprint at 2.4GB; this
# leaves margin for ostree/flatpak's own working set on top of that). This
# is a disk-safety gate, not a functional requirement of flatpak itself —
# see the recipe's IMAGE_ROOTFS_EXTRA_SPACE comment for why it can be
# tight on a QEMU dev image.
MIN_FREE_KB_FOR_CHROMIUM=$((3 * 1024 * 1024))

: > "$RESULT_FILE"
record() {
    echo "$1" | tee -a "$RESULT_FILE" >&2
}

mkdir -p "$INSTALL_PATH" "$PROFILE_DIR"

# ── D-Bus session bus ────────────────────────────────────────────────────
# Load-bearing, not optional — research spike §1.3/§2.2: a zero-D-Bus
# `flatpak run` fails outright (exit 1, "Cannot autolaunch D-Bus without
# X11 $DISPLAY"), confirmed by a NEGATIVE control in the same spike. This
# unit is a plain systemd SYSTEM service (Type=oneshot, no User= session,
# no logind) — exactly the "無 logind 的 systemd 服務" shape the Y3-2
# ticket calls out. Re-exec the ENTIRE script under dbus-run-session so
# every flatpak call below shares one session bus, mirroring
# appliance/mkosi.extra/usr/local/sbin/duduclaw-kiosk-launch.sh's own
# wrapper (the research doc's explicit recommendation: reuse this exact
# pattern verbatim, not reinvent it).
if [[ -z "${DUDUCLAW_VERIFY_DBUS_ACTIVE:-}" ]]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        record "FAIL dbus-run-session-missing"
        exit 1
    fi
    export DUDUCLAW_VERIFY_DBUS_ACTIVE=1
    log "re-exec under dbus-run-session"
    exec dbus-run-session -- "$0" "$@"
fi
record "PASS dbus-run-session-active DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unset}"

# ── Named installation ───────────────────────────────────────────────────
# /etc/flatpak/installations.d/${INSTALLATION}.conf ships from this
# recipe's do_install (Path=/var/lib/duduclaw-flatpak-verify — deliberately
# NOT /data/flatpak: this Yocto line has no /data persistent partition yet,
# H3-line A/B+/data work is appliance-line-specific and not ported here —
# tracked as follow-up once the Yocto line grows its own atomic-update
# storage layout).
if ! flatpak --installation="$INSTALLATION" remotes >/dev/null 2>&1; then
    record "FAIL named-installation-not-registered ($INSTALLATION)"
    exit 1
fi
record "PASS named-installation-registered"

# ── Offline preload repo (Y6-3) ──────────────────────────────────────────
# meta-duduclaw/recipes-duduclaw/duduclaw-flatpak-offline-repo/ bakes a
# pre-normalized OSTree repo into this fixed path at IMAGE BUILD time (see
# that recipe + its own gen-flatpak-offline-repo.sh, sitting next to the
# .bb file, for how it is produced: a real Flathub pull, ref-promoted from
# `<remote>:<ref>` remote-tracking form to real head refs, then
# `flatpak build-update-repo` — the exact replacement validated in
# research/native-os-2026-08/flatpak-carrier-2026-08.md §2.3/§2.4 for the
# (confirmed still-broken as of flatpak 1.16.6 AND 1.18.1, see the Y3-2
# handoff notes' "sid-test" spike) sideload-repos mechanism, which never
# actually falls back to local content — it always tries summary.idx over
# the network first and gives up instead of looking at sideload dirs).
# This is tried BEFORE the network flathub remote below, as an ordinary
# second `file://` remote on the SAME named installation — a real machine
# with zero network at first boot still gets a working Chromium kiosk
# fallback out of this. `gpg-verify-summary=false` because this repo's
# summary is regenerated locally (unsigned); individual commit objects are
# still whatever GPG state they carried from the original Flathub pull —
# see the offline-repo recipe's own header for the honest "not positively
# verified" caveat carried over from the research doc's §6 item 3.
OFFLINE_REPO_DIR=/opt/duduclaw-flatpak-offline-repo
offline_used=0
if [[ -d "$OFFLINE_REPO_DIR/objects" ]]; then
    if ! flatpak --installation="$INSTALLATION" remote-list | grep -qw flathub-offline; then
        log "adding flathub-offline remote ($OFFLINE_REPO_DIR)"
        flatpak --installation="$INSTALLATION" remote-add --if-not-exists \
            --gpg-verify-summary=false \
            flathub-offline "file://$OFFLINE_REPO_DIR" 2>&1 | tee -a "$RESULT_FILE" >&2
    fi
    if flatpak --installation="$INSTALLATION" remote-list | grep -qw flathub-offline; then
        record "PASS flathub-offline-remote-present"
        if flatpak --installation="$INSTALLATION" info "$APP_ID" >/dev/null 2>&1; then
            record "PASS flatpak-install-offline $APP_ID (already present)"
            offline_used=1
        else
            log "installing $APP_ID from offline repo (zero network, local copy only)"
            if flatpak --installation="$INSTALLATION" install -y --noninteractive \
                flathub-offline "$APP_ID" 2>&1 | tee -a "$RESULT_FILE" >&2; then
                record "PASS flatpak-install-offline $APP_ID"
                offline_used=1
            else
                record "FAIL flatpak-install-offline $APP_ID (falling back to network path below)"
            fi
        fi
    else
        record "FAIL remote-add-flathub-offline (falling back to network path below)"
    fi
else
    record "SKIP flathub-offline-repo-absent path=$OFFLINE_REPO_DIR"
fi

if [[ "$offline_used" -ne 1 ]]; then
    # ── Flathub remote (network path — the ticket explicitly allows 側載或網路
    # for this milestone; only reached when the offline repo above is absent
    # or failed) ─────────────────────────────────────────────────────────
    if ! flatpak --installation="$INSTALLATION" remote-list | grep -qw flathub; then
        log "adding flathub remote"
        if ! flatpak --installation="$INSTALLATION" remote-add --if-not-exists \
            flathub https://flathub.org/repo/flathub.flatpakrepo 2>&1 | tee -a "$RESULT_FILE" >&2; then
            record "FAIL remote-add-flathub"
            exit 1
        fi
    fi
    record "PASS flathub-remote-present"

    # ── Disk-safety gate before a multi-GB live download ────────────────
    free_kb=$(df -Pk "$INSTALL_PATH" | awk 'NR==2 {print $4}')
    if [[ -z "$free_kb" || "$free_kb" -lt "$MIN_FREE_KB_FOR_CHROMIUM" ]]; then
        record "SKIP chromium-install-disk-budget free_kb=${free_kb:-unknown} floor_kb=$MIN_FREE_KB_FOR_CHROMIUM"
        record "PARTIAL — see result file: mechanism (D-Bus + named install + remote) verified, live Chromium fetch skipped for disk safety"
        exit 0
    fi
    record "PASS disk-budget free_kb=$free_kb"

    # ── Install (or reuse) the app ───────────────────────────────────────
    if ! flatpak --installation="$INSTALLATION" info "$APP_ID" >/dev/null 2>&1; then
        log "installing $APP_ID (this downloads real content — see disk-budget gate above)"
        if ! flatpak --installation="$INSTALLATION" install -y --noninteractive \
            flathub "$APP_ID" 2>&1 | tee -a "$RESULT_FILE" >&2; then
            record "FAIL flatpak-install $APP_ID"
            exit 1
        fi
    fi
    record "PASS flatpak-install $APP_ID"
fi

# ── --kiosk launch against the real dashboard ────────────────────────────
# --headless=new/--disable-gpu/--no-sandbox: this milestone has no
# compositor to hand Chromium a real display (comp/shell not yet built on
# this line) — same headless substitution the research spike used to prove
# the mechanism (dbus wiring, argv passthrough, sandbox/profile behavior)
# independent of GPU/display availability. --kiosk and --user-data-dir=
# are the two flags actually named in the ticket; --dump-dom gives a
# deterministic, scriptable success signal (non-empty rendered DOM) instead
# of just an exit code, which --kiosk alone would not.
log "launching $APP_ID --kiosk against $DASHBOARD_URL"
dom_output="$(flatpak --installation="$INSTALLATION" run "$APP_ID" \
    --headless=new --disable-gpu --no-sandbox \
    --kiosk \
    --user-data-dir="$PROFILE_DIR" \
    --dump-dom "$DASHBOARD_URL" 2>>"$RESULT_FILE")"
run_rc=$?

if [[ $run_rc -ne 0 ]]; then
    record "FAIL chromium-kiosk-run rc=$run_rc"
    exit 1
fi

if [[ -z "$dom_output" ]]; then
    record "FAIL chromium-kiosk-run empty-dom"
    exit 1
fi

# A dashboard page (even pre-JS-hydration) is expected to at least carry
# its own <html>/<head> skeleton — this is the same "did it actually
# render something, not just exit 0" bar the research spike used for
# about:blank (`<html><head></head><body></body></html>`). We additionally
# require the DOM NOT be that literal empty-page string, since that would
# mean Chromium reached --dump-dom successfully but never actually loaded
# $DASHBOARD_URL (e.g. gateway not listening yet).
if [[ "$dom_output" == "<html><head></head><body></body></html>" ]]; then
    record "FAIL chromium-kiosk-run dashboard-not-loaded (got the empty-page skeleton, same as about:blank)"
    exit 1
fi

record "PASS chromium-kiosk-run dom_bytes=${#dom_output}"
record "OVERALL PASS"
exit 0
