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
#
# Y6-1 (2026-08-26) closes two of those three deferrals: D-Bus session bus
# (fcitx5 needs one to register its control interface on) and fcitx5 itself
# (the D3/D3-f/W7-3 Debian-line Chinese-input work, ported onto this base --
# see recipes-support/{fcitx5,fcitx5-chewing,libchewing,extra-cmake-modules}/
# for the four self-authored recipes this needed).
#
# Y7-3 (2026-08-26) closes the third: PipeWire/audio (start_audio_session
# below), a verbatim port of the Debian line's own D5 function
# (appliance/mkosi.extra/usr/local/sbin/duduclaw-kiosk-launch.sh) -- same
# scope split D5 itself had from D3's IME work, just closed in a later
# ticket on this line instead.
set -euo pipefail
shopt -s nullglob

log() { echo "duduclaw-kiosk-launch: $*" >&2; }

# ── D-Bus session bus (Y6-1) ──────────────────────────────────────────────
# fcitx5 registers a D-Bus control interface (org.fcitx.Fcitx5, per its own
# ENABLE_DBUS=On default -- see fcitx5_5.1.12.bb) and its own IPC layer
# (which `fcitx5-remote` talks to) also runs over this same session bus.
# Mirrors the Debian appliance line's exact `dbus-run-session` re-exec
# pattern verbatim (appliance/mkosi.extra/usr/local/sbin/
# duduclaw-kiosk-launch.sh lines ~121-134) rather than inventing a
# different mechanism for the same problem: re-exec this whole script
# under `dbus-run-session`, guarded by an env var so the re-exec only
# happens once. Fail-open like every other optional dependency in this
# script: no `dbus-run-session` binary (package missing from a stripped-down
# image variant) logs a warning and continues without a bus rather than
# refusing to boot -- fcitx5 itself already fails open the same way further
# down (missing binary -> log + continue, not `set -e` abort).
if [[ -z "${DUDUCLAW_KIOSK_DBUS_ACTIVE:-}" && "${DUDUCLAW_KIOSK_DBUS:-1}" != "0" ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        export DUDUCLAW_KIOSK_DBUS_ACTIVE=1
        log "re-exec under dbus-run-session (session bus for fcitx5)"
        exec dbus-run-session -- "$0" "$@"
    fi
    log "WARNING: dbus-run-session not found -- no session bus; fcitx5 will run without D-Bus control"
fi

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

# ── Audio: PipeWire + WirePlumber (Y7-3, 2026-08-26, verbatim port of the
# Debian appliance line's D5 `start_audio_session`) ───────────────────────
# This kiosk is a plain systemd SYSTEM service (User=duduclaw-kiosk,
# duduclaw-kiosk.service) with no logind session, so there is no
# `systemd --user` manager to activate pipewire.service/wireplumber.service
# the way the upstream OE recipes install them -- exactly the same reason
# the D-Bus session bus above has to be started by hand. So they are
# started here too, as ordinary background children of this script, which
# also means systemd's default KillMode=control-group tears them down with
# the session.
#
# Started BEFORE any compositor, for every session shape this script might
# grow later (matching D5's own reasoning verbatim): PipeWire only needs
# $XDG_RUNTIME_DIR (already created at 0700 by duduclaw-kiosk.service's own
# RuntimeDirectory=) and, for WirePlumber, the session bus started by the
# dbus-run-session re-exec at the top of this file -- neither depends on
# comp/shell being up, and comp/shell do not depend on audio being up
# either.
#
# Fail-open on every branch, same contract as the fcitx5 block below: a box
# with no audio hardware, or an image built without these packages, must
# still reach a working screen. The shell reports the resulting state
# honestly rather than pretending -- crates/duduclaw-shell/src/audio/ fails
# to an explicit "audio unavailable" backend on Linux (NOT to its demo
# backend), and 系統設定 › 聲音 runs its own probe, so a missing daemon
# surfaces as 「音訊服務未啟動」 instead of a slider that moves and changes
# nothing.
#
# WirePlumber is started AFTER PipeWire's client socket exists rather than
# in parallel: it is a PipeWire client, and starting it against a socket
# that is not there yet just makes it retry-or-exit for no reason. The wait
# is bounded and non-fatal -- past the budget it starts anyway and reports
# its own failure to the journal, because a stuck wait here would delay the
# whole screen coming up.
AUDIO_WAIT_SECS="${DUDUCLAW_KIOSK_AUDIO_WAIT_SECS:-5}"

start_audio_session() {
    local i

    if [[ "${DUDUCLAW_KIOSK_AUDIO:-1}" == "0" ]]; then
        log "audio disabled via DUDUCLAW_KIOSK_AUDIO=0 -- 音量控制不可用"
        return 0
    fi
    if ! command -v pipewire >/dev/null 2>&1; then
        log "note: pipewire not installed -- 音量控制不可用"
        return 0
    fi
    if [[ -S "$RUNTIME_DIR/pipewire-0" ]]; then
        log "note: PipeWire socket already present at $RUNTIME_DIR/pipewire-0 -- not starting a second daemon"
        return 0
    fi

    log "starting PipeWire"
    pipewire >/dev/null 2>&1 &

    for (( i = 0; i < AUDIO_WAIT_SECS * 10; i++ )); do
        [[ -S "$RUNTIME_DIR/pipewire-0" ]] && break
        sleep 0.1
    done
    if [[ ! -S "$RUNTIME_DIR/pipewire-0" ]]; then
        log "WARNING: PipeWire produced no socket within ${AUDIO_WAIT_SECS}s -- starting WirePlumber anyway"
    fi

    if command -v wireplumber >/dev/null 2>&1; then
        log "starting WirePlumber (PipeWire session manager; ships wpctl, which the shell drives)"
        wireplumber >/dev/null 2>&1 &
    else
        log "note: wireplumber not installed -- PipeWire is running but has no session manager, so there will be no default sink"
    fi
}

# ── fcitx5 configuration seed (Y6-1, ported from the Debian appliance
# line's D3-d/D3-f/W7-3 rounds) ───────────────────────────────────────────
# Content below is a DELIBERATE, verbatim port of appliance/mkosi.extra/
# usr/local/sbin/duduclaw-kiosk-launch.sh's own `seed_fcitx5_config` --
# every choice here already paid for a real operator-facing bug on the
# Debian line and is not being re-derived from scratch:
#   - keyboard-us as Items/0, chewing as Items/1 (D3-f/P0-2): fcitx5's
#     AltTriggerKeys default (Shift_L) switches between item 0 and the
#     current IM. With chewing as item 0 there was nothing for a bare
#     Shift to switch TO, so the only English left was Shift+letter, which
#     libchewing commits as UPPERCASE -- "英文不管怎麼打都是大寫，沒辦法切換
#     成小寫". `ActiveByDefault=True` below is what keeps 開機即中文 despite
#     chewing no longer being item 0 -- via Behavior, not item order.
#   - AltTriggerKeys=  (emptied, W7-3): a bare Shift press-and-release is
#     also the first half of every Shift+letter chord -- with the default
#     Shift_L trigger still active, typing a single capital letter (ASCII
#     field) or holding Shift through a capital mid-password both
#     misfired the IM-switch gesture. VM-reproduced on the Debian line via
#     QMP-injected bare Shift + `fcitx5-remote -n` state reads. Ctrl+Space
#     (TriggerKeys, left at fcitx5's own default) remains the manual
#     toggle everywhere crates/duduclaw-shell's ime_focus.rs does not
#     proactively switch the IM on focus.
#   - TogglePreedit= (emptied): fcitx5's own default binds this to
#     Ctrl+Alt+P, which visually detaches the composition box from the
#     text field on a stray keypress with zero discoverable way back --
#     confirmed on the Debian line via a real VM screenshot.
#   - Vertical candidate list (D3-f/P1-1): BOTH classicui.conf's `Vertical
#     Candidate List` AND chewing.conf's own `CandidateLayout` are needed,
#     not redundant -- chewing expresses its own preference, which wins
#     over classicui's when both engines share a candidate window.
#     fcitx5's addon conf files are flat `Key=Value` with NO section
#     header (confirmed against fcitx5's own conf/notifications.conf on
#     the Debian line -- a `[Classic User Interface]` wrapper was silently
#     ignored the first time this was tried there).
#
# Re-seeding is version-gated (FCITX5_SEED_VERSION), not every-boot, for
# the same reason as the Debian line: fcitx5 rewrites `profile` itself
# whenever the operator switches engine, and stomping that on every boot
# would make their choice un-keepable. MUST run while fcitx5 is NOT
# running yet (this function is only ever called before `fcitx5 -d` below)
# -- fcitx5 saves its in-memory profile on shutdown, so a seed written
# next to a live fcitx5 gets silently overwritten within seconds (measured
# on the Debian line's D3-f round).
#
# Version starts at 1 here (not continuing the Debian line's counter at 3)
# -- this is a separate image lineage with no prior seed history of its
# own to stay compatible with; the CONTENT below already reflects
# everything all three Debian-line rounds (D3-d/D3-f/W7-3) learned.
FCITX5_SEED_VERSION=1

seed_fcitx5_config() {
    local conf_dir marker
    conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"
    marker="$conf_dir/.duduclaw-seed"

    if [[ -r "$marker" ]] && [[ "$(cat "$marker" 2>/dev/null)" == "$FCITX5_SEED_VERSION" ]]; then
        return 0
    fi
    if ! mkdir -p "$conf_dir/conf" 2>/dev/null; then
        # Y8-2 (2026-08-27): this Yocto line has no /data provisioning at
        # all today -- grep-confirmed zero .mount unit, zero systemd-repart
        # config, zero tmpfiles.d entry for /data anywhere in
        # meta-duduclaw, and `/` itself is root:root 0755 -- so
        # $HOME=/data/duduclaw-kiosk (this package's own USERADD_PARAM
        # --home-dir) is not a race that sometimes wins, it is a
        # permanently unwritable path for the unprivileged duduclaw-kiosk
        # user on every current boot (live-reproduced: `mkdir -p
        # /data/duduclaw-kiosk/.config/fcitx5/conf` as that user fails with
        # "Permission denied", not ENOENT-then-retry).
        #
        # A first attempt at this fix tried writing a *runtime* fallback
        # seed to /etc/xdg/fcitx5 (fcitx5's own XDG_CONFIG_DIRS
        # system-default tier) right here -- WRONG, caught by re-testing
        # as the actual duduclaw-kiosk user rather than trusting an
        # earlier root-shell test: `/etc/xdg` is root:root 0755 same as
        # `/`, so that mkdir fails with the exact same Permission denied,
        # it would have been silent dead code repeating the bug one
        # directory over. The actual fix has to live at BUILD time, not
        # here: duduclaw-shell_1.62.0.bb's do_install now ships this same
        # profile/config/conf content pre-baked, root-owned 0644, at
        # ${sysconfdir}/xdg/fcitx5/ -- files fcitx5 already reads via the
        # standard XDG_CONFIG_DIRS cascade with zero runtime write
        # required (read-only access is all "other" needs). Live-verified
        # on a QEMU clone with $HOME left deliberately unwritable:
        # fcitx5-remote -n reports "chewing" as the active default engine
        # immediately after fcitx5 starts. The moment /data really is
        # mounted on some future boot, this function's branch above
        # starts succeeding again and reseeds the per-user tier, which
        # then wins over that baked-in system default per ordinary XDG
        # precedence -- no special-case migration code needed, and
        # nothing left to do here except log the honest degraded state.
        log "note: could not create $conf_dir -- 中文輸入設定使用建置期烤入的 /etc/xdg/fcitx5 系統預設（開機即中文/直式候選字仍生效，僅使用者個人化設定無法持久化）"
        return 0
    fi
    # Y9-1 (2026-08-27) update: the /data provisioning this comment
    # predicted has landed -- files/wic/duduclaw-data-bootdisk.wks.in +
    # recipes-duduclaw/duduclaw-firstboot ship a real /data partition,
    # mounted+grown+first-boot-provisioned, on duduclaw-image-data.bb and
    # everything requiring it (duduclaw-image-flatpak.bb as of this same
    # ticket). duduclaw-firstboot-provision.sh creates and chowns
    # /data/duduclaw-kiosk to this exact user before duduclaw-kiosk.service
    # ever starts (ordering: kiosk After=...duduclaw-gateway.service, which
    # itself now Requires=duduclaw-firstboot-provision.service via a
    # gateway.service.d drop-in -- see that drop-in's own header), so THIS
    # function's mkdir above is expected to succeed on those images with no
    # further code change, exactly as the paragraph above predicted. Not yet
    # independently re-verified against a live duduclaw-image-data QEMU boot
    # as running duduclaw-kiosk (Y9-1's own QEMU verification targeted the
    # provisioning layer itself, headless -- see that ticket's handoff notes
    # for exactly which layer of verification was reached). Plain
    # duduclaw-image.bb (no /data partition at all) still degrades exactly as
    # described below -- this addendum does not change that image.
    #
    # The same reasoning covers libchewing's own user-dictionary persistence
    # (chewing_capi::io's "Failed to load user dict: Permission denied",
    # Y8-2's own drive-by finding, a sibling of this exact bug under a
    # different fcitx5-managed path) -- it is not this function's code, but
    # the identical "was $HOME writable" precondition governs it, and Y9-1's
    # fix reaches it the same way, with no separate code path of its own.


    cat > "$conf_dir/profile" <<'FCITX5_PROFILE'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=chewing

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=chewing
Layout=

[GroupOrder]
0=Default
FCITX5_PROFILE

    cat > "$conf_dir/config" <<'FCITX5_CONFIG'
[Behavior]
ActiveByDefault=True
ShareInputState=All

[Hotkey]
TogglePreedit=
AltTriggerKeys=
FCITX5_CONFIG

    printf 'Vertical Candidate List=True\n' > "$conf_dir/conf/classicui.conf"
    printf 'CandidateLayout=Vertical\n' > "$conf_dir/conf/chewing.conf"

    printf '%s' "$FCITX5_SEED_VERSION" > "$marker"
    log "seeded fcitx5 config (v$FCITX5_SEED_VERSION): keyboard-us/chewing order, 開機即中文, Ctrl+Space 切中英（Shift 已停用防誤觸）, 直式候選字"
}

# Audio starts before comp, matching D5's own ordering -- see
# start_audio_session's own comment block above for why.
start_audio_session

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

# ── fcitx5 (Y6-1) ─────────────────────────────────────────────────────────
# Must start after comp's socket exists (fcitx5 is a Wayland client, same
# as duduclaw-shell) and before duduclaw-shell, so the shell's text-input-v3
# handler has an input method to talk to on its very first focus event --
# same ordering constraint and same reasoning as the Debian appliance
# line's D3-d comment ("fcitx5 must come up after comp's socket exists and
# before the shell").
if command -v fcitx5 >/dev/null 2>&1; then
    seed_fcitx5_config
    # XMODIFIERS is the one variable fcitx5's own wiki documents as always
    # required. GTK_IM_MODULE/QT_IM_MODULE are deliberately NOT set here,
    # same reasoning as the Debian line: on Wayland they route input around
    # text-input-v3 instead of through it.
    export XMODIFIERS=@im=fcitx
    fcitx5 -d --replace >/dev/null 2>&1 \
        || log "WARNING: fcitx5 failed to start -- 中文輸入不可用"
else
    log "note: fcitx5 not installed -- 中文輸入不可用"
fi

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
