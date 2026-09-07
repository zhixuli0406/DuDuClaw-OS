# DuDuClaw OS — live installer ISO, DESKTOP edition (2026-09-04).
#
# The SAME live environment as duduclaw-image-live.bb (`require`d verbatim:
# squashfs live root, graphical installer wizard, desktop stack for the
# wizard itself). The one and only difference is the install material the
# ISO carries: the full-desktop shipping image duduclaw-image-appliance
# (A/B update chain + duduclaw-comp/duduclaw-shell desktop + Flatpak-preloaded
# Chromium/LibreOffice/Steam + fcitx5 IME — the same image the release's
# whole-disk .wic.zst is made from) instead of the headless duduclaw-image-ab.
#
# Why a second recipe rather than a knob on the first: bitbake keys stamps,
# deploy names and the cross-image do_bootimg dependency off the recipe name,
# so two ISOs with different payloads must be two recipes to coexist in one
# deploy dir; and the headless ISO's byte-for-byte Y19 behaviour stays
# untouched (its default DUDUCLAW_INSTALL_PAYLOAD_IMAGE is unchanged).
#
# Size: the appliance .wic zstd-compresses to ~1.6 GB (v0.1.0 release
# numbers), plus the live squashfs — comfortably under the 3.8 GB point
# where image-live.bbclass switches mkisofs to -iso-level 3, and under the
# 4 GB FAT32 single-file limit of the .hddimg twin.
#
# Install-time disk requirement is unchanged from the headless ISO: both
# payloads use the same A/B GPT layout (duduclaw-image-appliance `require`s
# duduclaw-image-ab.bb), so the installer's size check and the first-boot
# /data growth behave identically.

require recipes-core/images/duduclaw-image-live.bb

SUMMARY = "DuDuClaw OS live installer environment — desktop edition (installs duduclaw-image-appliance)"

DUDUCLAW_INSTALL_PAYLOAD_IMAGE = "duduclaw-image-appliance"
