# DuDuClaw OS boot splash (C1 identity, 2026-10-16).
#
# `require`d by duduclaw-image-desktop.inc, so every image with a display
# stack gets it: duduclaw-image (and through it -ab, -appliance,
# -appliance-test, -data, -flatpak) and duduclaw-image-live(-desktop).
# duduclaw-image-minimal, which has no desktop, does not.
#
# What it adds:
#   * plymouth (meta-oe; see recipes-core/plymouth/plymouth_%.bbappend for
#     why it is rootfs-only, never in the initramfs) and duduclaw-boot-splash
#     (the theme plus the kiosk/rescue ordering drop-ins).
#   * DUDUCLAW_SPLASH_CMDLINE on the kernel command line of the product UKI.
#     duduclaw-image-ab.bb appends it to its slot-B UKI next to its own
#     UKI_SLOTB_CMDLINE definition, and duduclaw-image-live.bb to the live
#     medium's APPEND; neither is done from here (see below).
#   * plymouth.enable=0 on the rescue UKI.
#
# The kernel arguments, and why each one is there:
#   splash         plymouthd shows the graphical theme only when the command
#                  line carries `splash` or `rhgb`; without either it shows
#                  the text "details" view (plymouth 24.004.60 src/main.c,
#                  plymouth_should_show_default_splash).
#   plymouth.ignore-serial-consoles
#                  this machine's only `console=` is the serial port
#                  (KERNEL_CONSOLE = ttyS0,115200, oe-core's default from
#                  SERIAL_CONSOLES). With a serial console present plymouth
#                  forces "details" mode on every display
#                  (ply-device-manager.c create_devices_from_terminals +
#                  main.c should_force_details), i.e. no graphical splash at
#                  all. This flag makes it ignore the serial console, so the
#                  display gets the theme and ttyS0 keeps the plain boot log
#                  that release-os.sh smoke reads (SMOKE_LOGIN_RE).
#   NOT `quiet`    deliberate. The kernel already prints only to ttyS0 (no
#                  console=tty0), so `quiet` would not hide anything on the
#                  screen; it would only strip the serial log that the QEMU
#                  smoke run and every bring-up transcript in wiki/reports/
#                  depend on.
#
# Fail-safe by construction: nothing in the initramfs changes; plymouth-start
# is a Wants= of sysinit.target (not Requires=), so a plymouthd that fails to
# start or finds no DRM device (DeviceTimeout=8 in plymouthd.defaults) is a
# failed unit and boot carries on; the kiosk is ordered after
# plymouth-quit.service, which is a 20 s-capped oneshot whose failure is
# ignored; and plymouth.enable=0 (honoured by plymouth-start.service's own
# ConditionKernelCommandLine=!plymouth.enable=0) keeps the splash off the
# rescue path entirely.
#
# Status (2026-10-16): written and statically reviewed only. Not yet built
# with bitbake, not yet booted in QEMU. Verify with a real
# `kas build` + `scripts/release-os.sh smoke` before relying on it.

DUDUCLAW_SPLASH_CMDLINE ?= "splash plymouth.ignore-serial-consoles"

IMAGE_INSTALL:append = " plymouth duduclaw-boot-splash"

# :append, not a reassignment: duduclaw-image-ab.bb later REASSIGNS
# UKI_CMDLINE (`=`, for its PARTUUID root), and an :append survives that,
# the same mechanism duduclaw-ro-root.inc's own `UKI_CMDLINE:append = " ro"`
# relies on. The verity class injects its tokens at parse end and is
# unaffected by token order.
UKI_CMDLINE:append = " ${DUDUCLAW_SPLASH_CMDLINE}"

# The rescue UKI's cmdline defaults to "${UKI_CMDLINE} systemd.unit=
# duduclaw-rescue.target" (classes/duduclaw-rescue-boot.bbclass), so it would
# inherit `splash`. duduclaw-rescue.target Conflicts= multi-user.target, so
# plymouth-quit.service would never run and the splash would cover the tty1
# rescue shell. plymouth.enable=0 stops plymouth-start.service from running
# at all. (The rescue shell also quits any splash itself, see
# duduclaw-boot-splash's drop-in; this is the primary guard, that is the
# backstop.) Harmless on images that do not inherit duduclaw-rescue-boot:
# nothing reads the variable there.
UKI_RESCUE_CMDLINE:append = " plymouth.enable=0"
