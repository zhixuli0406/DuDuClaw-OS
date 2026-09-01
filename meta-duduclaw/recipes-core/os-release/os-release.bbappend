# WS-3/A6 (2026-09-01, DESIGN-os-security-line-2026-09.md §2 支柱一 A6:
# "DISTRO_VERSION 與分割區 LABEL 版號串一致化，救活 ProtectVersion=%A").
#
# DEEPER ROOT CAUSE than the design doc's own one-line description names —
# found while verifying, not silently worked around (flagged per this
# ticket's own discipline): `ProtectVersion=%A` in both
# recipes-duduclaw/duduclaw-ab-update/files/10-duduclaw-root.transfer and
# 20-duduclaw-uki.transfer resolves the `%A` specifier from the
# `IMAGE_VERSION=` field of /etc/os-release specifically — read directly
# from systemd's own man/standard-specifiers.xml at this line's pinned
# SRCREV ("%A ... as read from the IMAGE_VERSION= field"), NOT from
# `VERSION_ID=` (that's the separate `%w` specifier). oe-core's own
# meta/recipes-core/os-release/os-release.bb (read directly, not recalled)
# sets `VERSION`/`VERSION_ID` from DISTRO_VERSION via its
# `OS_RELEASE_FIELDS` list, but that list has NO `IMAGE_VERSION` entry at
# all, and grepping this entire layer (meta-duduclaw) before writing this
# file found zero existing os-release.bbappend or any other mechanism that
# adds one. Net effect BEFORE this file: `/etc/os-release` never had an
# `IMAGE_VERSION=` line, `%A` resolved to an empty string on every boot,
# and `ProtectVersion=%A` was comparing against "" the whole time — not
# merely mismatched (10-duduclaw-root.transfer's own existing Y8-1 comment,
# now corrected by this file, described it as "the wks bakes ... with no
# suffix" vs. a real DISTRO_VERSION value; the actual state was that
# `%A` never had ANY value to compare, mismatched or otherwise). An empty
# ProtectVersion= pattern matches no real partition name, which is a
# silent no-op, not a crash — the whole mechanism was inert, not merely
# imprecise.
#
# Fix: extend OS_RELEASE_FIELDS (the officially-supported extension point
# — os-release.bb's own `do_compile[vardeps] += "${OS_RELEASE_FIELDS}"`
# means appending here correctly triggers a rebuild on change, not a
# side-channel hack) to also emit IMAGE_VERSION=${DISTRO_VERSION} — the
# SAME value the wks (files/wic/duduclaw-ab-bootdisk.wks.in p2's
# `--part-name`) and the UKI filename
# (recipes-core/images/duduclaw-image-ab.bb's `UKI_FILENAME`) now also
# bake in, this same WS-3/A6 wave, so all three — the running system's own
# os-release, its root partition's GPT name, and its factory UKI's
# filename — agree on one string for any given build, keeping
# ProtectVersion=%A meaningful (and self-consistently correct across
# future builds, suffix or not — see the wks file's own A6 comment for why
# tying all three to the same DISTRO_VERSION variable is self-maintaining
# rather than a one-time string copy).
#
# Left unquoted-field-list alone (OS_RELEASE_UNQUOTED_FIELDS): IMAGE_VERSION
# stays in the default quoted bucket, same treatment VERSION/PRETTY_NAME
# already get from the base recipe — systemd's own os-release parser
# (env-file-style) handles quoted values transparently, and DISTRO_VERSION
# ("1.62.0-y1-bringup") contains no characters that would need the
# VERSION_ID-only `sanitise_value()` lowercase/space-to-underscore
# treatment anyway.
OS_RELEASE_FIELDS += "IMAGE_VERSION"
IMAGE_VERSION = "${DISTRO_VERSION}"
