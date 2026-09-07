# H3g migration #2: tell the gateway where the compositor's co-drive socket is.
#
# WHY: duduclaw-comp creates its agent-seat injection socket + token under
# the kiosk session's runtime dir (/run/duduclaw-kiosk/duduclaw-codrive.sock
# and .token, see crates/duduclaw-comp/src/codrive/mod.rs), but the gateway
# is a root system service with NO XDG_RUNTIME_DIR in its environment, and
# its [codrive] config defaults to "$XDG_RUNTIME_DIR/duduclaw-codrive.sock"
# (crates/duduclaw-gateway/src/codrive/config.rs). Without an explicit
# socket_path/token_path every codrive_run therefore failed with
# "XDG_RUNTIME_DIR is not set and [codrive] socket_path is not configured"
# -- co-drive could never reach the screen on a shipped machine (2026-09-05
# QEMU feature walkthrough). duduclaw-firstboot-provision.sh now writes the
# section for new devices; this migrator adds it on devices provisioned
# before the fix, because /data is forward-only (see data_migrations.rs).
#
# Idempotent: appends the [codrive] table only when no [codrive] header is
# present at all; an operator-edited section is left untouched.
set -euo pipefail
CONFIG_PATH="${DUDUCLAW_HOME:-/data/duduclaw}/config.toml"
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "[migration 1788591433] ${CONFIG_PATH} does not exist yet, nothing to do"
    exit 0
fi
if grep -qE '^\[codrive\]' "$CONFIG_PATH"; then
    echo "[migration 1788591433] [codrive] already present in ${CONFIG_PATH}, nothing to do"
    exit 0
fi
echo "[migration 1788591433] adding [codrive] socket/token paths to ${CONFIG_PATH}"
cat >> "$CONFIG_PATH" <<'EOT'

# Added by DuDuClaw OS (migration 1788591433): the compositor's co-drive
# agent-seat socket lives in the kiosk session's runtime dir, not the
# gateway's. Both files are created by duduclaw-comp at every session start.
[codrive]
socket_path = "/run/duduclaw-kiosk/duduclaw-codrive.sock"
token_path = "/run/duduclaw-kiosk/duduclaw-codrive.token"
EOT
