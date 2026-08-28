# DuDuClaw OS — /data first-boot provisioning payload (Y14-A, 2026-08-27).
#
# Extracted verbatim from duduclaw-image-data.bb's own IMAGE_INSTALL:append
# line (Y9-1, unchanged since) so it can be shared by BOTH the 3-partition
# /data-only line (duduclaw-image-data.bb, ESP+root+data) and the 4-partition
# A/B line (duduclaw-image-appliance.bb, ESP+root-A+root-B+data) without
# either one `require`-ing the other's `.bb` — see
# commercial/docs/DESIGN-image-convergence-2026-08.md §2.2 for why a plain
# `.inc` (no `inherit`/`WKS_FILE`) is the right unit to share here: this
# recipe needs duduclaw-data-partflags (3-partition numbering), the
# appliance recipe needs duduclaw-ab-partflags (4-partition numbering), and
# those two *-partflags bbclasses must never both be inherited into the same
# image (see duduclaw-image-data.bb's own header for the conflicting
# sfdisk-partition-number risk this avoids).
#
# duduclaw-firstboot itself has no partition-NUMBER assumption anywhere
# (checked by reading duduclaw-firstboot.bb, its three .service files, and
# its two .sh scripts — confirmed, not assumed): its systemd units key off
# the generically-named `data.mount` unit, which systemd derives from the
# /data MOUNTPOINT in fstab, not from which partition number backs it (3 on
# the data wks, 4 on the A/B/appliance wks). That is what makes this single
# line safe to share unmodified across both partition layouts.
IMAGE_INSTALL:append = " duduclaw-firstboot"
