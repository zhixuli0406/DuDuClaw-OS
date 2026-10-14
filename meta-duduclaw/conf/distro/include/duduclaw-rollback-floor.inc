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
# EMPTY ON PURPOSE until the platform snapshot catches up. The vendored
# duduclaw-sysd (platform v1.73.1) knows neither flag and clap refuses an
# unknown argument, so sysd would not start. duduclaw-sysd's do_install
# fails the build if this is set while the vendored source lacks either
# flag. TODO(platform-sync): in the commit that moves the snapshots to the
# platform release carrying the rootless gateway changes, set this to that
# build's own DISTRO_VERSION, literally, once.
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
# Trade-off, by design: once a rootless image is blessed, the device can
# no longer return to any pre-rootless image, by sysd rollback or by
# sd-boot fallback. Recovering from a bad rootless release means shipping a
# fixed newer one (or the rescue entry, which these rules never touch).
DUDUCLAW_MIN_ROLLBACK_VERSION ?= ""
