#!/usr/bin/env bash
# ExecStart= for duduclaw-kiosk.service. Y3-1 "開機即殼" MVP -- a narrowed
# port of appliance/mkosi.extra/usr/local/sbin/duduclaw-kiosk-launch.sh's
# `run_comp_session` function only (comp is always present in this image,
# so the operator-override / cage / Chromium fallback ladder that script
# carries has nothing to fall back TO here -- there is no cage or chromium
# recipe in this image). See duduclaw-kiosk.service's own header comment
# for the full list of what was deliberately left out this round (fcitx5,
# D-Bus session bus, PipeWire/audio) and why each is safe to defer for a
# first boot-to-desktop verification.
set -euo pipefail
shopt -s nullglob

log() { echo "duduclaw-kiosk-launch: $*" >&2; }

SHELL_BIN=/usr/bin/duduclaw-shell
COMP_BIN=/usr/bin/duduclaw-comp
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/duduclaw-kiosk}"
KIOSK_HOME="${HOME:-/data/duduclaw-kiosk}"
SOCKET_WAIT_SECS="${DUDUCLAW_KIOSK_COMP_SOCKET_WAIT_SECS:-10}"

export XDG_SESSION_TYPE=wayland

# First Wayland socket in $XDG_RUNTIME_DIR, or empty. Same `-S` (is-a-socket)
# filter the Debian line's script uses, for the same reason: it excludes
# smithay's sibling `wayland-N.lock` regular file without having to
# pattern-match the name.
comp_socket_name() {
    local f
    for f in "$RUNTIME_DIR"/wayland-*; do
        [[ -S "$f" ]] || continue
        printf '%s' "${f##*/}"
        return 0
    done
    return 0
}

# No LIBGL_ALWAYS_SOFTWARE here -- same rule the Debian line's script
# documents: Mesa refuses to force software rendering on the process that
# owns the hardware ("Not allowed to force software rendering when API
# explicitly selects a hardware device"). WAYLAND_DISPLAY is explicitly
# unset for comp so it takes its "own the hardware" path rather than
# nesting as a client of something else.
log "starting duduclaw-comp (backend=${DUDUCLAW_COMP_BACKEND:-udev})"
env -u WAYLAND_DISPLAY \
    DUDUCLAW_COMP_BACKEND="${DUDUCLAW_COMP_BACKEND:-udev}" \
    "$COMP_BIN" &
comp_pid=$!

sock=""
for (( i = 0; i < SOCKET_WAIT_SECS * 10; i++ )); do
    kill -0 "$comp_pid" 2>/dev/null || break
    sock="$(comp_socket_name)"
    [[ -n "$sock" ]] && break
    sleep 0.1
done

if [[ -z "$sock" ]] || ! kill -0 "$comp_pid" 2>/dev/null; then
    log "duduclaw-comp produced no Wayland socket within ${SOCKET_WAIT_SECS}s (or exited first)"
    kill "$comp_pid" 2>/dev/null || true
    wait "$comp_pid" 2>/dev/null || true
    exit 1
fi
log "duduclaw-comp is listening on $sock (pid $comp_pid)"
export WAYLAND_DISPLAY="$sock"

log "starting duduclaw-shell as duduclaw-comp's client"
env DUDUCLAW_HOME="$KIOSK_HOME" "$SHELL_BIN" &
shell_pid=$!

# No comp+shell health-probe window here (the Debian script's
# COMP_SHELL_PROBE_SECS gate) -- that gate exists to decide whether to fall
# back to cage, which has nothing to fall back to in this image. If comp
# dies, the shell's Wayland connection drops and it exits on its own; `wait`
# below still observes that.
rc=0
wait "$shell_pid" || rc=$?
log "duduclaw-shell exited (status $rc) -- stopping duduclaw-comp"
kill "$comp_pid" 2>/dev/null || true
wait "$comp_pid" 2>/dev/null || true
exit "$rc"
