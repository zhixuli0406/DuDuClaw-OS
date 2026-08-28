#!/usr/bin/env bash
# duduclaw-steam-kiosk-verify.sh — Y5-2 verification that Steam's Flatpak
# reaches its own login screen as a real Wayland client of
# duduclaw-kiosk.service (the actual compositor+shell pair this OS boots
# into), completing the four-layer chain Y4-2 traced and fixed by hand in a
# live QEMU session:
#   1. root refusal            -> runs as duduclaw-flatpak-verify (unit's User=)
#   2. XDG_RUNTIME_DIR ownership -> this unit's own RuntimeDirectory= (formal)
#   3. steam-devices udev rule -> duduclaw-steam-devices recipe (formal)
#   4. zenity/no-X11 crash     -> PATH-injected stub, see below
#
# Ticket: Y5-2. See duduclaw-flatpak-kiosk-verify.bb for the systemd unit
# this runs under (shares its identity/state dir with the older Y3-2
# headless-Chromium check, does not replace it).

set -uo pipefail

log() { echo "duduclaw-steam-kiosk-verify: $*" >&2; }

RESULT_FILE=/var/log/duduclaw-steam-kiosk-verify/duduclaw-steam-kiosk-verify.result
INSTALLATION=verify
INSTALL_PATH=/var/lib/duduclaw-flatpak-verify
APP_ID="${DUDUCLAW_STEAM_VERIFY_APP_ID:-com.valvesoftware.Steam}"
KIOSK_RUNTIME_DIR=/run/duduclaw-kiosk
# /opt, NOT /usr/local/libexec -- a live QEMU run found `flatpak run
# --filesystem=` unconditionally refuses any path rooted under /usr
# ("Path \"/usr\" is reserved by Flatpak"), independent of the target's own
# permissions. See duduclaw-flatpak-kiosk-verify.bb's do_install comment for
# the full writeup; keep this literal path in sync with that recipe's own
# install path.
ZENITY_STUB_DIR=/opt/duduclaw-steam-stubs
SOCKET_WAIT_SECS="${DUDUCLAW_STEAM_VERIFY_SOCKET_WAIT_SECS:-30}"
LOGIN_WAIT_SECS="${DUDUCLAW_STEAM_VERIFY_LOGIN_WAIT_SECS:-180}"
# Same floor and rationale as duduclaw-flatpak-kiosk-verify.sh's own
# MIN_FREE_KB_FOR_APPS (renamed from MIN_FREE_KB_FOR_CHROMIUM in Y14-B when
# LibreOffice joined that script's own disk-safety gate) -- Y4-2 measured
# Steam + all its pulled-in runtimes (Compat.i386, GL32, codecs-extra) at
# ~2.8GB total.
MIN_FREE_KB_FOR_STEAM=$((3 * 1024 * 1024))

: > "$RESULT_FILE"
record() {
    echo "$1" | tee -a "$RESULT_FILE" >&2
}

# ── D-Bus session bus (identical wrapper pattern to the Chromium check;
# see that script's own comment for why this is load-bearing, not optional).
if [[ -z "${DUDUCLAW_STEAM_VERIFY_DBUS_ACTIVE:-}" ]]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        record "FAIL dbus-run-session-missing"
        exit 1
    fi
    export DUDUCLAW_STEAM_VERIFY_DBUS_ACTIVE=1
    log "re-exec under dbus-run-session"
    exec dbus-run-session -- "$0" "$@"
fi
record "PASS dbus-run-session-active DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unset}"

# ── Layer 2, formalized: this unit's own RuntimeDirectory= already set
# XDG_RUNTIME_DIR to our OWN dir (/run/duduclaw-flatpak-verify), separate
# from duduclaw-kiosk's -- verify it actually landed, since a silently-unset
# XDG_RUNTIME_DIR would resurrect exactly the D-Bus ownership crash Y4-2 hit.
if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" ]]; then
    record "FAIL xdg-runtime-dir-missing (expected the unit's own RuntimeDirectory=, got '${XDG_RUNTIME_DIR:-unset}')"
    exit 1
fi
record "PASS xdg-runtime-dir-own XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

# ── Wait for duduclaw-kiosk.service's Wayland socket. Same "-S" (is-a-
# socket) filter duduclaw-kiosk-launch.sh's own comp_socket_name() uses, for
# the same reason: excludes smithay's sibling `wayland-N.lock` regular file
# without pattern-matching the name. Deliberately does NOT hardcode
# "wayland-1" (Y4-2's manual session happened to land on that name, but
# nothing guarantees it -- comp picks the first free display number, which
# depends on what else, if anything, is already running).
kiosk_socket_path() {
    local f
    shopt -s nullglob
    for f in "$KIOSK_RUNTIME_DIR"/wayland-*; do
        [[ -S "$f" ]] || continue
        printf '%s' "$f"
        return 0
    done
    return 0
}

sock=""
for (( i = 0; i < SOCKET_WAIT_SECS * 10; i++ )); do
    sock="$(kiosk_socket_path)"
    [[ -n "$sock" ]] && break
    sleep 0.1
done

if [[ -z "$sock" ]]; then
    record "FAIL kiosk-wayland-socket-not-found dir=$KIOSK_RUNTIME_DIR wait_secs=$SOCKET_WAIT_SECS (is duduclaw-kiosk.service up?)"
    exit 1
fi
record "PASS kiosk-wayland-socket-found sock=$sock"

# Absolute path, NOT the bare socket basename -- Y4-2's real finding:
# wl_display_connect() resolving a bare name consults OUR OWN
# XDG_RUNTIME_DIR (a different directory from duduclaw-kiosk's), so only the
# absolute-path form actually reaches the compositor's socket cross-user.
export WAYLAND_DISPLAY="$sock"
export XDG_SESSION_TYPE=wayland

# ── Named installation + flathub remote (idempotent, mirrors the Chromium
# check's own logic verbatim -- both units share the SAME named
# installation, see the .service file's StateDirectory= comment).
if ! flatpak --installation="$INSTALLATION" remotes >/dev/null 2>&1; then
    record "FAIL named-installation-not-registered ($INSTALLATION)"
    exit 1
fi
record "PASS named-installation-registered"

if ! flatpak --installation="$INSTALLATION" remote-list | grep -qw flathub; then
    log "adding flathub remote"
    if ! flatpak --installation="$INSTALLATION" remote-add --if-not-exists \
        flathub https://flathub.org/repo/flathub.flatpakrepo 2>&1 | tee -a "$RESULT_FILE" >&2; then
        record "FAIL remote-add-flathub"
        exit 1
    fi
fi
record "PASS flathub-remote-present"

free_kb=$(df -Pk "$INSTALL_PATH" | awk 'NR==2 {print $4}')
if [[ -z "$free_kb" || "$free_kb" -lt "$MIN_FREE_KB_FOR_STEAM" ]]; then
    record "SKIP steam-install-disk-budget free_kb=${free_kb:-unknown} floor_kb=$MIN_FREE_KB_FOR_STEAM"
    record "PARTIAL — mechanism (D-Bus + socket + named install + remote) verified, live Steam fetch skipped for disk safety"
    exit 0
fi
record "PASS disk-budget free_kb=$free_kb"

if ! flatpak --installation="$INSTALLATION" info "$APP_ID" >/dev/null 2>&1; then
    log "installing $APP_ID (this downloads real content — see disk-budget gate above)"
    if ! flatpak --installation="$INSTALLATION" install -y --noninteractive \
        flathub "$APP_ID" 2>&1 | tee -a "$RESULT_FILE" >&2; then
        record "FAIL flatpak-install $APP_ID"
        exit 1
    fi
fi
record "PASS flatpak-install $APP_ID"

# ── Layer 3 (steam-devices udev rule) sanity echo -- not authoritative
# (the rule is a HOST-side fact, this only checks what our own process can
# see), but a genuinely-denied /dev/uinput would make check_device_perms()
# fail regardless, so a quick own-process access check here gives an early,
# specific signal instead of only finding out from Steam's own crash.
if [[ -e /dev/uinput ]]; then
    if [[ -r /dev/uinput && -w /dev/uinput ]]; then
        record "PASS uinput-access-from-verify-process (duduclaw-steam-devices udev rule + input group membership both effective)"
    else
        record "FAIL uinput-access-from-verify-process (udev rule not applied, or group membership missing — check_device_perms() WILL crash Steam's wrapper)"
    fi
else
    record "SKIP uinput-not-present (uinput kernel module not loaded on this machine — cannot pre-check, Steam's own wrapper will report definitively)"
fi

# ── Layer 4 (zenity bypass): expose the stub directory read-only and put it
# FIRST on PATH for this one `flatpak run` invocation only -- see
# duduclaw-zenity-stub's own header comment for the full "why not
# STEAM_ZENITY, why not XWayland" writeup. --filesystem=/--env= here are
# session-scoped additions the CALLER of `flatpak run` is always allowed to
# make, independent of the app's own manifest permissions.
if [[ ! -x "$ZENITY_STUB_DIR/zenity" ]]; then
    record "FAIL zenity-stub-missing path=$ZENITY_STUB_DIR/zenity"
    exit 1
fi
record "PASS zenity-stub-present path=$ZENITY_STUB_DIR/zenity"

# ── Launch. Backgrounded and left running on purpose (Type=oneshot +
# RemainAfterExit=yes in the unit does not kill remaining cgroup processes
# just because ExecStart's own process exits) -- the whole point is to
# leave Steam sitting at its login screen for external inspection
# (operator-driven QEMU QMP screendump, or a follow-up OCR pass), not to
# tear it down the instant this script's own polling window ends.
log "launching $APP_ID (backgrounded, PATH-injected zenity stub active)"
env PATH="$ZENITY_STUB_DIR:$PATH" \
    flatpak --installation="$INSTALLATION" run \
    --filesystem="$ZENITY_STUB_DIR:ro" \
    --env=PATH="$ZENITY_STUB_DIR:/app/bin:/usr/bin" \
    "$APP_ID" \
    >>"$RESULT_FILE" 2>&1 &
steam_launch_pid=$!
record "PASS steam-launched-backgrounded launcher_pid=$steam_launch_pid"

# ── Evidence collection window. "軟渲染慢是預期" per the ticket -- this is
# a bounded, best-effort POLL, not a hard gate: a timeout here is recorded
# as its own honest PARTIAL/FAIL line, never silently upgraded to PASS.
#
# steamwebhelper is Steam's own embedded CEF process that actually PAINTS
# its UI (including the login screen) -- its existence is real, well-known,
# strong process-level evidence that Steam got past bootstrap/wrapper
# crashes and is rendering something, independent of what that something
# looks like pixel-for-pixel. This script can only see PROCESSES and LOGS
# from inside the guest -- it explicitly does NOT attempt a screenshot
# (that is a host-side QEMU QMP `screendump` action, orthogonal to
# anything a guest-side script can do) and says so plainly below rather
# than implying more than it actually checked.
login_screen_evidence="NONE"
for (( i = 0; i < LOGIN_WAIT_SECS; i++ )); do
    if pgrep -u duduclaw-flatpak-verify -f steamwebhelper >/dev/null 2>&1; then
        login_screen_evidence="steamwebhelper-process"
        break
    fi
    if ! kill -0 "$steam_launch_pid" 2>/dev/null; then
        # The wrapper's own launcher process already exited. Not
        # necessarily a failure (bin_steam.sh execve()s the real binary,
        # replacing this pid) -- but if steamwebhelper never showed up
        # either, that is worth its own explicit line below, not silence.
        break
    fi
    sleep 1
done

case "$login_screen_evidence" in
    steamwebhelper-process)
        record "PASS steamwebhelper-process-detected wait_secs<=$LOGIN_WAIT_SECS (strong evidence Steam's UI, including its login screen, is rendering)"
        record "NOTE pixel-level confirmation (e.g. a QEMU QMP screendump showing the actual \"Sign in to Steam\" UI) is a HOST-side action outside this script's reach — see the TODO doc's Y5-2 row for that evidence"
        record "OVERALL PASS"
        ;;
    *)
        record "FAIL steamwebhelper-process-not-detected wait_secs=$LOGIN_WAIT_SECS"
        record "OVERALL FAIL — see ${RESULT_FILE} above for exactly which of the four known layers (or a new one) this run stopped at"
        ;;
esac

exit 0
