#!/usr/bin/env bash
# duduclaw-flatpak-kiosk-verify.sh — Y3-2 "first light" verification that
# DuDuClaw OS's Yocto-built environment can run Flatpak-packaged apps under a
# plain systemd SYSTEM service (no logind session). This is a standalone
# VERIFICATION script, not the production kiosk launcher: duduclaw-comp/
# duduclaw-shell have no Yocto recipe yet (Y2-3 status table), so there is
# no real compositor to hand Chromium a Wayland socket. It runs Chromium's
# own --headless=new path instead, exactly matching the already-validated
# methodology in research/native-os-2026-08/flatpak-carrier-2026-08.md §2
# (the same flags, the same dbus-run-session wrapper, the same "systemd
# service not manual shell" discipline) — first light for the mechanism,
# not for the pixels.
#
# Ticket: Y3-2. See meta-duduclaw/recipes-duduclaw/duduclaw-flatpak-kiosk-
# verify/duduclaw-flatpak-kiosk-verify.bb for the systemd unit this runs
# under and duduclaw-polkit-flatpak/ for the OS-side permission rule that
# lets this run without an interactive polkit prompt.
#
# Y14-B (2026-08-27) — two changes on top of the Y3-2/Y6-3/Y13-1 baseline:
#
# 1. FIXED A REAL BUG: the offline-repo remote-add below used to pass
#    `--gpg-verify-summary=false`, which is NOT and never has been a
#    `flatpak remote-add` command-line option (checked against this layer's
#    own pinned flatpak SRCREV — meta-openembedded/meta-oe/recipes-extended/
#    flatpak/flatpak_1.17.6.bb, SRCREV 9b21874f1a175a9b7c79175a221fa043
#    e202ca73 — via `app/flatpak-builtins-remote-add.c`'s GOptionEntry
#    arrays: only `--no-gpg-verify` exists, and it flips BOTH the
#    `gpg-verify` AND `gpg-verify-summary` config keys to false together;
#    there is no flag to set them independently). Y13-1's real QEMU run
#    caught this live: `error: Unknown option --gpg-verify-summary=false`,
#    which made `remote-add` fail, which made the whole offline-repo path a
#    silent no-op that fell through to the live network `flathub` remote
#    below — meaning a real zero-network first boot could not install
#    Chromium at all. Fixed to `--no-gpg-verify`, which IS real,
#    IS accepted by this exact flatpak version, and is also the only way to
#    satisfy this remote's actual requirement: `gen-flatpak-offline-repo.sh`
#    runs `flatpak build-update-repo` with no `--gpg-sign`, so the summary
#    it produces is genuinely unsigned — leaving the CLI default
#    (`gpg-verify-summary=true`) would make every install here fail with
#    "GPG verification enabled, but no summary found" regardless of the
#    remote-add bug, offline or online, zero network or not. Honest
#    security note carried forward unchanged from Y6-3/Y13-1: this also
#    disables per-commit GPG verification (there is no flatpak CLI surface
#    to keep `gpg-verify=true` while only relaxing `gpg-verify-summary` —
#    the only other option, `remote-modify`, has the identical gap; the
#    narrower split would require hand-editing the underlying OSTree remote
#    config file outside of any documented flatpak CLI surface, which this
#    recipe deliberately does not do). This offline repo's real trust
#    anchor is the image build pipeline that produced it (see the
#    offline-repo recipe's own INHIBIT_PACKAGE_STRIP/byte-for-byte-
#    passthrough comment), not a runtime GPG check against a local file://
#    path with no network attacker in the loop.
# 2. LibreOffice (`org.libreoffice.LibreOffice`) added alongside Chromium —
#    Y13-1 grepped the whole meta-duduclaw layer and found LibreOffice had
#    NEVER been added to any recipe (the earlier assumption that it already
#    shipped was wrong, not a regression). It goes through the exact same
#    offline-repo-then-network-fallback path as Chromium (see APP_IDS below)
#    and gets its own functional launch check (LibreOffice --cat, the
#    productivity-suite analogue of Chromium's --dump-dom: real headless
#    document processing with observable output, not just a process that
#    exits 0).

set -uo pipefail

log() { echo "duduclaw-flatpak-kiosk-verify: $*" >&2; }

# Directory comes from the systemd unit's LogsDirectory=, writable by the
# unprivileged User= that unit runs this script as (plain /var/log is
# root:root 0755 and would not be).
RESULT_FILE=/var/log/duduclaw-flatpak-kiosk-verify/duduclaw-flatpak-kiosk-verify.result
INSTALLATION=verify
INSTALL_PATH=/var/lib/duduclaw-flatpak-verify
PROFILE_DIR="$INSTALL_PATH/chromium-profile"
# LIBREOFFICE_PROFILE_DIR is deliberately a SUBDIRECTORY of
# LIBREOFFICE_TEST_DIR, not a sibling under $INSTALL_PATH -- the `flatpak
# run --filesystem=` override further down grants access to exactly ONE
# directory tree, and this script must not depend on org.libreoffice.
# LibreOffice's own Flathub manifest happening to declare broader access
# (e.g. `--filesystem=home`) that may or may not resolve to anything
# writable for this nologin service account's unset/empty $HOME.
LIBREOFFICE_TEST_DIR="$INSTALL_PATH/libreoffice-verify"
LIBREOFFICE_PROFILE_DIR="$LIBREOFFICE_TEST_DIR/profile"
DASHBOARD_URL="http://127.0.0.1:18789/"
CHROMIUM_APP_ID="${DUDUCLAW_VERIFY_APP_ID:-org.chromium.Chromium}"
LIBREOFFICE_APP_ID="${DUDUCLAW_VERIFY_LIBREOFFICE_APP_ID:-org.libreoffice.LibreOffice}"
# Every app this script installs + verifies, in the order they should be
# attempted. Both go through the identical offline/network install loop
# below; each then gets its OWN functional launch check further down (a
# browser and a productivity suite cannot share one check).
APP_IDS=("$CHROMIUM_APP_ID" "$LIBREOFFICE_APP_ID")

# Conservative floor: refuse to even attempt a real live-network install
# below this much free space on the partition the named installation lives
# on. Real measured footprint (this recipe's own gen-flatpak-offline-repo.sh
# run, 2026-08-27, both apps + shared runtime in one repo): Chromium ~2.4G +
# LibreOffice ~1.1G (LibreOffice reuses the SAME org.freedesktop.Platform/
# 25.08 runtime Chromium already needs — no second runtime download) =
# ~3.5G uncompressed OSTree objects. This floor covers a from-scratch live
# download of BOTH apps plus margin for ostree/flatpak's own working set on
# top of that. This is a disk-safety gate, not a functional requirement of
# flatpak itself — see the recipe's IMAGE_ROOTFS_EXTRA_SPACE comment for why
# it can be tight on a QEMU dev image.
MIN_FREE_KB_FOR_APPS=$((5 * 1024 * 1024))

: > "$RESULT_FILE"
record() {
    echo "$1" | tee -a "$RESULT_FILE" >&2
}

mkdir -p "$INSTALL_PATH" "$PROFILE_DIR" "$LIBREOFFICE_PROFILE_DIR" "$LIBREOFFICE_TEST_DIR"

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

# ── Offline preload repo (Y6-3, GPG flag fixed Y14-B) ────────────────────
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
# with zero network at first boot still gets a working offline fallback for
# EVERY app in APP_IDS out of this, not just Chromium. `--no-gpg-verify`
# (not the never-valid `--gpg-verify-summary=false` this script used to
# pass — see this file's Y14-B header comment for the full one-hand-sourced
# explanation of why that flag never existed and why `--no-gpg-verify` is
# the actually-correct fix, not a downgrade of intent).
OFFLINE_REPO_DIR=/opt/duduclaw-flatpak-offline-repo
declare -A offline_used=()
for app_id in "${APP_IDS[@]}"; do
    offline_used["$app_id"]=0
done

if [[ -d "$OFFLINE_REPO_DIR/objects" ]]; then
    if ! flatpak --installation="$INSTALLATION" remote-list | grep -qw flathub-offline; then
        log "adding flathub-offline remote ($OFFLINE_REPO_DIR)"
        flatpak --installation="$INSTALLATION" remote-add --if-not-exists \
            --no-gpg-verify \
            flathub-offline "file://$OFFLINE_REPO_DIR" 2>&1 | tee -a "$RESULT_FILE" >&2
    fi
    if flatpak --installation="$INSTALLATION" remote-list | grep -qw flathub-offline; then
        record "PASS flathub-offline-remote-present"
        for app_id in "${APP_IDS[@]}"; do
            if flatpak --installation="$INSTALLATION" info "$app_id" >/dev/null 2>&1; then
                record "PASS flatpak-install-offline $app_id (already present)"
                offline_used["$app_id"]=1
            else
                log "installing $app_id from offline repo (zero network, local copy only)"
                if flatpak --installation="$INSTALLATION" install -y --noninteractive \
                    flathub-offline "$app_id" 2>&1 | tee -a "$RESULT_FILE" >&2; then
                    record "PASS flatpak-install-offline $app_id"
                    offline_used["$app_id"]=1
                else
                    record "FAIL flatpak-install-offline $app_id (falling back to network path below for this app)"
                fi
            fi
        done
    else
        record "FAIL remote-add-flathub-offline (falling back to network path below for every app)"
    fi
else
    record "SKIP flathub-offline-repo-absent path=$OFFLINE_REPO_DIR"
fi

# Apps the offline path did not cover (repo absent, remote-add failed, or
# that specific app's offline install failed) still get a live-network
# attempt below — per-app, not all-or-nothing, so one app's offline success
# is never held hostage by another app's offline failure.
remaining_app_ids=()
for app_id in "${APP_IDS[@]}"; do
    if [[ "${offline_used[$app_id]}" -ne 1 ]]; then
        remaining_app_ids+=("$app_id")
    fi
done

if [[ "${#remaining_app_ids[@]}" -gt 0 ]]; then
    # ── Flathub remote (network path — the ticket explicitly allows 側載或網路
    # for this milestone; only reached for apps the offline repo above did
    # not cover) ──────────────────────────────────────────────────────────
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
    if [[ -z "$free_kb" || "$free_kb" -lt "$MIN_FREE_KB_FOR_APPS" ]]; then
        record "SKIP apps-install-disk-budget free_kb=${free_kb:-unknown} floor_kb=$MIN_FREE_KB_FOR_APPS apps=${remaining_app_ids[*]}"
        record "PARTIAL — see result file: mechanism (D-Bus + named install + remote) verified, live fetch skipped for disk safety"
        exit 0
    fi
    record "PASS disk-budget free_kb=$free_kb"

    # ── Install (or reuse) each remaining app ────────────────────────────
    for app_id in "${remaining_app_ids[@]}"; do
        if ! flatpak --installation="$INSTALLATION" info "$app_id" >/dev/null 2>&1; then
            log "installing $app_id (this downloads real content — see disk-budget gate above)"
            if ! flatpak --installation="$INSTALLATION" install -y --noninteractive \
                flathub "$app_id" 2>&1 | tee -a "$RESULT_FILE" >&2; then
                record "FAIL flatpak-install $app_id"
                exit 1
            fi
        fi
        record "PASS flatpak-install $app_id"
    done
fi

# ── Chromium: --kiosk launch against the real dashboard ─────────────────
# --headless=new/--disable-gpu/--no-sandbox: this milestone has no
# compositor to hand Chromium a real display (comp/shell not yet built on
# this line) — same headless substitution the research spike used to prove
# the mechanism (dbus wiring, argv passthrough, sandbox/profile behavior)
# independent of GPU/display availability. --kiosk and --user-data-dir=
# are the two flags actually named in the ticket; --dump-dom gives a
# deterministic, scriptable success signal (non-empty rendered DOM) instead
# of just an exit code, which --kiosk alone would not.
log "launching $CHROMIUM_APP_ID --kiosk against $DASHBOARD_URL"
dom_output="$(flatpak --installation="$INSTALLATION" run "$CHROMIUM_APP_ID" \
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

# ── LibreOffice: headless --cat real-document-processing check (Y14-B) ──
# Chromium's functional bar is "rendered a real page's DOM"; LibreOffice
# has no DOM to dump, so the equivalent bar here is "actually processed a
# real document and produced real output" — `--cat` (soffice's own flag,
# per LibreOffice's official start_parameters help page: "Applies filter
# 'txt:Text' ... and dump text content to console (implies --headless)")
# feeds a known input file through LibreOffice's real text-filter pipeline
# and prints the result to stdout, which this script then checks for the
# exact marker string — a stronger signal than `--version` (which would
# only prove the binary starts, not that it can actually process a
# document) or a bare exit-code check (which `--headless --cat` on a
# missing/unreadable file can still return 0 for in some LibreOffice
# versions).
#
# `--filesystem=$LIBREOFFICE_TEST_DIR` on `flatpak run` (documented flatpak
# CLI option, NOT the xdg-desktop-portal path this milestone deliberately
# excludes — see duduclaw-image-flatpak.bb's own comment for why) grants
# the sandbox read/write access to exactly this one host directory so the
# input file is actually visible inside the sandbox without a portal.
# `-env:UserInstallation=file://...` (LibreOffice's own documented
# bootstrap-variable syntax, same start_parameters help page) redirects
# LibreOffice's user profile into that same directory — this service
# account has no real, writable $HOME (`--no-create-home`, `/sbin/nologin`
# in duduclaw-flatpak-kiosk-verify.bb's USERADD_PARAM), and LibreOffice's
# default profile location resolution would otherwise fail or wander into
# an unwritable path.
libreoffice_marker="DUDUCLAW_LIBREOFFICE_VERIFY_MARKER_$$"
libreoffice_input="$LIBREOFFICE_TEST_DIR/verify-input.txt"
printf '%s\n' "$libreoffice_marker" > "$libreoffice_input"

log "launching $LIBREOFFICE_APP_ID --cat against $libreoffice_input"
cat_output="$(flatpak --installation="$INSTALLATION" run \
    --filesystem="$LIBREOFFICE_TEST_DIR" \
    "$LIBREOFFICE_APP_ID" \
    "-env:UserInstallation=file://$LIBREOFFICE_PROFILE_DIR" \
    --cat "$libreoffice_input" 2>>"$RESULT_FILE")"
run_rc=$?

if [[ $run_rc -ne 0 ]]; then
    record "FAIL libreoffice-cat-run rc=$run_rc"
    exit 1
fi

if [[ -z "$cat_output" ]]; then
    record "FAIL libreoffice-cat-run empty-output"
    exit 1
fi

# Require the EXACT marker back out, not just "some non-empty output" —
# the same "did it actually process THIS input, not silently no-op or echo
# a cached/stale result" bar as Chromium's not-the-empty-skeleton check
# above.
if [[ "$cat_output" != *"$libreoffice_marker"* ]]; then
    record "FAIL libreoffice-cat-run marker-not-found output_bytes=${#cat_output}"
    exit 1
fi

record "PASS libreoffice-cat-run output_bytes=${#cat_output}"
record "OVERALL PASS"
exit 0
