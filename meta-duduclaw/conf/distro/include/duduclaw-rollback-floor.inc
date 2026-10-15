# Rollback floor: the oldest OS image a device may boot again once it runs
# the rootless gateway (2026-10-15). Defined once here, read by two recipes:
#   duduclaw-sysd      appends `--require-main-pid-of duduclaw-gateway.service
#                      --min-rollback-version ${DUDUCLAW_MIN_ROLLBACK_VERSION}`
#                      to duduclaw-sysd.service, so `update_rollback` refuses
#                      any older entry;
#   duduclaw-ab-update installs the value for duduclaw-rollback-prune.service,
#                      which deletes older ESP entries after the running one
#                      has passed the boot health gate, so sd-boot's own
#                      fallback (3 failed boots of an unblessed entry) cannot
#                      bring back a root gateway either.
#
# Set 2026-10-15 to the first rootless build's DISTRO_VERSION, literally,
# in the same commit that moved the snapshots to platform v1.73.4 (the
# release carrying the rootless gateway changes). duduclaw-sysd's
# do_install still fails the build if the vendored source lacks either
# flag.
#
# Which version string: the one in the UKI, not the repo-root VERSION file.
# sysd reads the target entry's embedded os-release IMAGE_VERSION and the
# `duduclaw-os_<version>.efi` filename, and on this line both are
# DISTRO_VERSION ("${DUDUCLAW_PLATFORM_VERSION}-y1-bringup", see
# duduclaw-os.conf and os-release.bbappend). The OS VERSION (0.x) appears in
# neither, so a floor of "0.4.0" would compare 0.4.0 with 1.73.x and never
# refuse anything. sysd's comparison treats "-y1-bringup" as a pre-release
# (1.73.4-y1-bringup < 1.73.4), so write the full string, e.g.
# "1.73.4-y1-bringup", not "1.73.4" (which would refuse rolling back to the
# first rootless image itself).
#
# Pinned, not derived from the current build: a floor that followed
# DISTRO_VERSION would forbid rolling back from one rootless release to the
# previous rootless release, which is exactly the rollback A/B exists for.
#
# Known gap during the FIRST rootless image's trial boots (design
# trade-off, accepted): until that entry is blessed, sd-boot's automatic
# boot assessment still holds the previous, root-gateway entry as its
# fallback. An AI employee on the new image runs as uid 1000 and can make
# those trial boots fail on purpose (stop the gateway from answering
# /healthz, hang it past the health-check budget), and three failed tries
# send the device back to the image where the gateway, and therefore the
# agent, ran as root. Closing it would mean deleting the old entry before
# the new one has proved it boots, i.e. giving up rollback for a broken
# update; the window is a few boots long and needs agent code already
# running on the new image. After the first bless, rollback-prune removes
# the old entry and the path is gone.
#
# Trade-off, by design: once a rootless image is blessed, the device can
# no longer return to any pre-rootless image, by sysd rollback or by
# sd-boot fallback. Recovering from a bad rootless release means shipping a
# fixed newer one (or the rescue entry, which these rules never touch).
DUDUCLAW_MIN_ROLLBACK_VERSION ?= "1.73.4-y1-bringup"
