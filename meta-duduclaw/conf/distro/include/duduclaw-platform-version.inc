# Embedded DuDuClaw platform version in this OS checkout.
#
# Since the 2026-09 repo split, OS release artifacts and tags use the
# independent repo-root VERSION file. This value records the platform source
# vendored into the image; it drives DISTRO_VERSION in ../duduclaw-os.conf
# and the PV of the cli/sysd recipes. The comp/shell recipes keep their
# own version. It need not equal VERSION.
#
# Update with scripts/sync-platform.sh <platform-version>, which checks the
# platform checkout, refreshes all four source snapshots, updates this file
# and renames their recipes together. See docs/guides/platform-sync.md.
#
# The -y1-bringup suffix remains separately owned in duduclaw-os.conf;
# syncing platform source must not silently change that milestone marker.
DUDUCLAW_PLATFORM_VERSION = "1.74.0"
DUDUCLAW_PLATFORM_SRCREV = "99aeee9c8d819314f72287a8fef6fc72bd733dde"
