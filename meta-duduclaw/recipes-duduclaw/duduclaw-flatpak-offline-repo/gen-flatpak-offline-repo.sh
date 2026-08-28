#!/usr/bin/env bash
# Build-time helper: pull Chromium + LibreOffice (+ each one's Flathub
# runtime deps) into a scratch named Flatpak installation, then normalize
# the resulting OSTree repo (remote-tracking refs -> real head refs +
# `flatpak build-update-repo` summary) so it can be served as a plain
# file:// remote with zero network at consumption time.
#
# This is the exact replacement path validated in
# research/native-os-2026-08/flatpak-carrier-2026-08.md §2.3/§2.4 and
# re-confirmed against flatpak 1.18.1 in commercial/docs/
# TODO-agent-first-os-2026-08.md's Y3-2 "sid-test" spike: the official
# sideload-repos/--sideload-repo= mechanism does NOT fall back to local
# content when the remote Url= is unreachable (it always tries summary.idx
# over the network first) -- so this script does not use sideload-repos at
# all. The repo produced here is meant to be baked into the image and
# pointed to directly as a remote's Url=.
#
# Y14-B (2026-08-27): LibreOffice added alongside Chromium -- meta-duduclaw
# never carried a LibreOffice recipe at all (Y13-1 grepped the whole layer
# and found zero hits; the earlier assumption that it already existed was
# wrong), and the offline-repo consumer side has the exact same "zero
# network at first boot" requirement for it as for Chromium, so it goes
# through the identical pull-then-normalize pipeline rather than a second
# bespoke mechanism. APP_IDS is now a space-separated list (was the
# singular APP_ID) so `flatpak install` can pull every app -- and, via
# Flatpak's own dependency resolution, every runtime/extension each one
# needs -- in the ref-normalization loop below, which already iterates
# generically over whatever `flathub:`-prefixed refs ended up in the repo
# and therefore needed zero changes to support more than one app.
set -euo pipefail

ARCH="${ARCH:-x86_64}"
APP_IDS="${APP_IDS:-org.chromium.Chromium org.libreoffice.LibreOffice}"
INSTALL_NAME="gen"
INSTALL_PATH="/srv/flatpak-gen"
OUT_DIR="/srv/out"

echo "==> [1/6] apt-get install flatpak/ostree/gnupg/curl"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends flatpak ostree gnupg curl ca-certificates >/dev/null
flatpak --version
ostree --version | head -1

echo "==> [2/6] named installation + flathub remote"
mkdir -p "$INSTALL_PATH" "$OUT_DIR"
mkdir -p /etc/flatpak/installations.d
cat > "/etc/flatpak/installations.d/${INSTALL_NAME}.conf" <<EOF
[Installation "${INSTALL_NAME}"]
Path=${INSTALL_PATH}
EOF
flatpak remote-add --installation="${INSTALL_NAME}" --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remote-list --installation="${INSTALL_NAME}" -d

echo "==> [3/6] flatpak install (real network fetch, this is the ONLY step that needs network)"
# shellcheck disable=SC2086 -- APP_IDS is intentionally word-split, it is a
# space-separated list of refs, not a single value.
time flatpak install --installation="${INSTALL_NAME}" -y --noninteractive --arch="${ARCH}" flathub ${APP_IDS}
flatpak list --installation="${INSTALL_NAME}" --app --runtime -d

REPO="${INSTALL_PATH}/repo"

echo "==> [4/6] ref normalization: remote-tracking refs -> real head refs"
ostree refs --repo="$REPO" | sort
ostree refs --repo="$REPO" | grep '^flathub:' | while IFS= read -r ref; do
  bare="${ref#flathub:}"
  commit="$(ostree rev-parse --repo="$REPO" "$ref")"
  echo "    create ${bare} -> ${commit}"
  ostree refs --repo="$REPO" --create="$bare" "$commit" --force
done
echo "-- refs after normalization --"
ostree refs --repo="$REPO" | sort

echo "==> [5/6] flatpak build-update-repo (generates servable summary, no GPG sign)"
flatpak build-update-repo "$REPO"
ls -la "$REPO/summary" "$REPO/summary.sig" 2>/dev/null || true

echo "==> [6/6] size measurement + package"
echo "-- repo dir size (uncompressed, this is the real 'Chromium runtime' disk cost) --"
du -sh "$REPO"
du -sh "$REPO"/* 2>/dev/null | sort -rh | head -20

tar -C "$INSTALL_PATH" -cf "${OUT_DIR}/duduclaw-flatpak-offline-repo.tar" repo
if command -v zstd >/dev/null 2>&1; then
  COMPRESSOR=zstd-preinstalled
else
  apt-get install -y --no-install-recommends zstd >/dev/null
fi
zstd -T0 -19 --rm "${OUT_DIR}/duduclaw-flatpak-offline-repo.tar" -o "${OUT_DIR}/duduclaw-flatpak-offline-repo.tar.zst"
sha256sum "${OUT_DIR}/duduclaw-flatpak-offline-repo.tar.zst" | tee "${OUT_DIR}/duduclaw-flatpak-offline-repo.tar.zst.sha256"
ls -la "${OUT_DIR}"

echo "==> DONE"
