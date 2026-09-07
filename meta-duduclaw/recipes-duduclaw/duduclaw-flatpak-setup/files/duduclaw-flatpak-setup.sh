#!/bin/bash
# duduclaw-flatpak-setup.sh -- make the `data` Flatpak installation usable
# on every boot: create /data/flatpak, seed the sandbox override, register
# the shipped offline repo (`flathub-offline`, file:///opt/...) and the
# network Flathub remote (`flathub`). Ported from the frozen mkosi line's
# /usr/local/sbin/duduclaw-flatpak-setup.sh, plus the offline remote the
# Yocto line's duduclaw-flatpak-offline-repo recipe ships (the same remote
# name and --no-gpg-verify rationale duduclaw-flatpak-kiosk-verify.sh
# documents: the repo is built with `build-update-repo` and no --gpg-sign,
# so summary verification would reject every install).
#
# Idempotent and fail-open: every step is `--if-not-exists` or guarded by
# a stamp; a boot without network only skips the flathub step and retries
# next boot. Never touches the rootfs (refuses when /data is not mounted).
set -euo pipefail
INSTALLATION=data
INSTALL_PATH=/data/flatpak
OFFLINE_REPO_DIR=/opt/duduclaw-flatpak-offline-repo
OFFLINE_REMOTE=flathub-offline
FLATHUB_URL=https://flathub.org/repo/flathub.flatpakrepo
STAMP="$INSTALL_PATH/.duduclaw-flathub-added"
RETRIES="${DUDUCLAW_FLATPAK_SETUP_RETRIES:-3}"
RETRY_SLEEP="${DUDUCLAW_FLATPAK_SETUP_RETRY_SLEEP:-10}"
log() { echo "duduclaw-flatpak-setup: $*"; }

if ! command -v flatpak >/dev/null 2>&1; then
    log "flatpak is not installed -- nothing to do"
    exit 0
fi
if ! mountpoint -q /data; then
    log "/data is not mounted -- refusing to create $INSTALL_PATH on the root filesystem"
    exit 0
fi
mkdir -p "$INSTALL_PATH"
chmod 0755 "$INSTALL_PATH"

OVERRIDE_FILE="$INSTALL_PATH/overrides/global"
if [[ ! -e "$OVERRIDE_FILE" ]]; then
    mkdir -p "$INSTALL_PATH/overrides"
    cat > "$OVERRIDE_FILE" <<'EOT'
[Environment]
XDG_SESSION_TYPE=wayland
EOT
    log "wrote default sandbox environment to $OVERRIDE_FILE"
fi

if ! flatpak --installation="$INSTALLATION" remotes >/dev/null 2>&1; then
    log "named installation '$INSTALLATION' is not registered (missing /etc/flatpak/installations.d/10-duduclaw-data.conf?) -- giving up"
    exit 0
fi

# Offline repo first: zero network, instant, and what the Launcher's
# install path prefers when the app is present there.
if [[ -d "$OFFLINE_REPO_DIR/objects" ]]; then
    if flatpak --installation="$INSTALLATION" remote-add --if-not-exists --no-gpg-verify \
        "$OFFLINE_REMOTE" "file://$OFFLINE_REPO_DIR"; then
        log "offline remote '$OFFLINE_REMOTE' -> $OFFLINE_REPO_DIR"
    else
        log "offline remote-add failed (continuing to flathub)"
    fi
else
    log "no offline repo at $OFFLINE_REPO_DIR -- skipping '$OFFLINE_REMOTE'"
fi

if [[ -e "$STAMP" ]]; then
    log "flathub remote already configured ($STAMP) -- done"
    exit 0
fi
for (( attempt = 1; attempt <= RETRIES; attempt++ )); do
    if flatpak --installation="$INSTALLATION" remote-add --if-not-exists flathub "$FLATHUB_URL"; then
        : > "$STAMP"
        log "flathub remote added to the '$INSTALLATION' installation at $INSTALL_PATH"
        exit 0
    fi
    log "attempt $attempt/$RETRIES to reach $FLATHUB_URL failed"
    if (( attempt < RETRIES )); then
        sleep "$RETRY_SLEEP"
    fi
done
log "giving up for this boot -- no flathub remote yet; will retry on the next boot"
exit 0
