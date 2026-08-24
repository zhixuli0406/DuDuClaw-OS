#!/usr/bin/env bash
# mkosi PostInstallationScripts= entry. Runs on the HOST with the image at
# $BUILDROOT; the mutations below are wrapped in a single `mkosi-chroot` so
# they act on the image. (mkosi auto-roots useradd/groupadd to $BUILDROOT
# but NOT systemctl — a bare `systemctl enable` here targets the build host,
# which is why enabling systemd-timesyncd.service failed with "Unit does not
# exist" before this wrapping. `systemctl enable` needs no running PID 1
# inside the chroot; it only manipulates unit-file symlinks.)
#
# (1) Creates the `duduclaw` system user the gateway service runs as.
#     Static UID 1000 to match container/Dockerfile.server's convention
#     (`useradd -r -g duduclaw -u 1000 duduclaw`) — kept identical so /data
#     ownership is consistent for anyone who's used the container image
#     before, and so a future container<->appliance data migration doesn't
#     need a uid remap. -r alone (no fixed uid) would risk a different
#     dynamically-assigned uid on the next mkosi run, and DynamicUser=yes
#     in the unit was rejected for the same reason: it would mint a new
#     random uid on every gateway restart, breaking persisted /data
#     ownership across reboots.
#
# (2) Creates the `duduclaw-kiosk` system user the detection-gated kiosk
#     display session runs as — see the comment right above that
#     useradd call below for the full "why these exact groups" reasoning.
#
# (3) Explicitly enables every unit this image depends on, rather than
#     trusting each package's own default preset. Checked and NOT assumed:
#     Debian's nftables package does not enable nftables.service by default
#     (deliberately, to avoid a package install silently locking out the
#     admin), and Debian overrides systemd upstream's own default-enable
#     preset for systemd-networkd/systemd-resolved with "disable" (Debian
#     defaults to ifupdown/NetworkManager, neither of which this image
#     installs). Rather than lean on assumptions about avahi-daemon/
#     docker.io/systemd-timesyncd's presumed default-enabled state too,
#     every unit this image actually needs is listed here explicitly —
#     one source of truth, no per-package guessing.
#
# (0) Creates the `netdev` group before anything else, because step (1)'s
#     useradd puts `duduclaw` in it. See that block's own comment for why
#     nothing in this image creates the group on its own.
#
set -euo pipefail

mkosi-chroot bash -s <<'CHROOT_SETUP'
set -euo pipefail

# (0) D4a-1 (2026-08-23): the `netdev` group. iwd's D-Bus policy
#     (/usr/share/dbus-1/system.d/iwd-dbus.conf, read out of the trixie .deb)
#     is deny-by-default with exactly three holes — root, `sudo`, `netdev` —
#     and iwd's Debian packaging creates NONE of them: it has no postinst and
#     no adduser dependency (Debian bug #1098212, open). The groups that
#     normally exist come from wpasupplicant/network-manager postinsts, and
#     this image installs neither. Without this line dbus-daemon logs
#     "Unknown group 'netdev' in message bus configuration file" at every
#     boot and the gateway can never reach iwd.
#     `getent` guard: this script runs under `set -e`, and a groupadd of an
#     already-existing group exits non-zero, which would abort the whole
#     post-install if a future Debian release starts shipping the group.
echo "[postinst] ensuring netdev group exists (iwd D-Bus policy references it)"
getent group netdev >/dev/null || groupadd -r netdev

echo "[postinst] creating duduclaw system user"
groupadd -r duduclaw
# -G netdev: this is the WHOLE authorization story for the gateway's Wi-Fi
# control (design decision B-①, commercial/docs/
# DESIGN-network-settings-2026-08.md §3) — iwd uses no polkit, so group
# membership is what the bus checks. Deliberately NOT granted to
# `duduclaw-kiosk` below: the shell is the largest attack surface on this box
# (GPU drivers, third-party apps) and reaches Wi-Fi only through the
# gateway's own authenticated RPC, exactly as it already does for account
# claim. Per-call authorization (admin role, appliance mode, first-run
# loopback+unclaimed) lives at the gateway RPC entry, not here.
useradd -r -g duduclaw -G netdev -u 1000 -d /data/duduclaw -s /usr/sbin/nologin duduclaw

# (2) Creates the `duduclaw-kiosk` system user the detection-gated kiosk
#     display session runs as (see mkosi.extra/etc/systemd/system/
#     duduclaw-kiosk.service). Same "home dir on /data, not created here"
#     reasoning as duduclaw above — root is read-only, and /data isn't
#     populated until duduclaw-firstboot-provision.sh runs on real
#     hardware, which is why that script (not this one) does the
#     mkdir+chown. No static UID unlike duduclaw: nothing needs a stable
#     uid for this user across image rebuilds, its entire $HOME is
#     disposable browser cache/profile state.
#
#     -G video,render: BOTH verified as actually required on Debian
#     trixie specifically, not guessed —
#       - video:  Debian's own seatd packaging (debian/seatd.service,
#                 debian/seatd.default) runs `seatd -g video` ("Allow
#                 access to video group members"), not upstream seatd's
#                 contrib unit, which uses a "seat" group instead. video
#                 group membership is what lets this user connect to
#                 seatd's socket at all — see duduclaw-kiosk.service's
#                 own comment for the full device-access chain.
#       - render: Debian's systemd package is built with
#                 -Dgroup-render-mode=0660 (debian/rules, systemd source
#                 package, trixie 257.13-1~deb13u1) — NOT upstream
#                 systemd's own default of 0666 (world-accessible). Without
#                 this group, Chromium's GPU process cannot open
#                 /dev/dri/renderD* directly (that device is opened by the
#                 client itself, unlike the DRM "card" device which seatd
#                 brokers over its socket).
#       - audio:  (D5, 2026-08-24) /dev/snd/* is root:audio 0660 on Debian.
#                 On a normal desktop nobody needs this group, because
#                 systemd-logind grants the seat's active session an ACL on
#                 those nodes — but THIS kiosk is a plain system service with
#                 no logind session at all (that is the same fact that makes
#                 duduclaw-kiosk-launch.sh start the D-Bus session bus and
#                 the PipeWire daemons by hand), so no ACL is ever granted
#                 and the group is the only path to the devices. Without it
#                 WirePlumber comes up, finds every ALSA card unopenable, and
#                 the box reports "no output devices" on hardware that has
#                 them.
#     All three groups are standard Debian base-system groups (created by
#     base-passwd / udev respectively), not something this image invents.
echo "[postinst] creating duduclaw-kiosk system user"
groupadd -r duduclaw-kiosk
useradd -r -g duduclaw-kiosk -G video,render,audio -d /data/duduclaw-kiosk \
    -s /usr/sbin/nologin -c "DuDuClaw kiosk display session" duduclaw-kiosk

echo "[postinst] enabling core units"
systemctl enable \
    systemd-networkd.service \
    systemd-resolved.service \
    systemd-timesyncd.service \
    nftables.service \
    avahi-daemon.service \
    docker.service \
    seatd.service \
    duduclaw-firstboot-repart.service \
    duduclaw-firstboot-provision.service \
    duduclaw-data-migrate.service \
    duduclaw-sysd.service \
    duduclaw-gateway.service \
    duduclaw-usb-install.service \
    duduclaw-kiosk.service \
    duduclaw-flatpak-setup.service \
    duduclaw-health-check.service

# H3c (2026-08-23): duduclaw-health-check.service is in the list above, but
# its [Install] section is RequiredBy=boot-complete.target, NOT
# WantedBy=multi-user.target like everything else there — so `enable` puts it
# under /etc/systemd/system/boot-complete.target.requires/ and it runs only
# on boots where boot-complete.target is pulled in at all (i.e. boots that
# sd-boot is counting). That indirection is the whole point: the gate decides
# whether this boot gets blessed, and blessing is only ever in question while
# a boot counter is in flight. Enabling it is what makes a failed health probe
# actually withhold the blessing instead of merely logging.

# D4a-1/D4a-2 (2026-08-23): Wi-Fi units, enabled separately from the block
# above only so this comment can explain the two non-obvious parts.
#
#   iwd.service      — iwd's Debian packaging leaves it D-Bus-ACTIVATED
#                      (net.connman.iwd.service), meaning it starts on the
#                      first bus call and not before. That is fine for
#                      `iwctl` on a laptop and wrong for an appliance: with
#                      only activation, a box that was joined to a network
#                      before a reboot does NOT rejoin it until something
#                      happens to talk to iwd. Enabling the unit is what
#                      makes "plug it in and it comes back on Wi-Fi" true.
#   var-lib-iwd.mount — bind-mounts /var/lib/iwd onto /data/network/iwd so
#                      saved credentials live on the DATA partition. Without
#                      it they sit on the active A/B root slot, and the first
#                      systemd-sysupdate run boots the OTHER slot where they
#                      do not exist — a Wi-Fi-only box would come back from
#                      an update permanently offline and unreachable except
#                      in person (design doc §4.2). Its [Install] section is
#                      RequiredBy=iwd.service, so enabling it here is what
#                      makes iwd depend on the mount: if the bind ever fails,
#                      iwd refuses to start rather than silently writing
#                      credentials to the doomed location.
echo "[postinst] enabling Wi-Fi units (iwd + persistent credential mount)"
systemctl enable iwd.service var-lib-iwd.mount

# Mask systemd-networkd-wait-online.service outright (2026-08-19). Removing it
# from the enable list above is not enough: the Debian networkd package ships
# a preset that re-pulls wait-online into network-online.target, and under
# QEMU's virtio-net it blocks ~120s before *failing*, stalling the whole boot
# (measured: login prompt slips from ~13s to ~135s). The gateway binds 0.0.0.0
# and its channels/relay reconnect on their own with backoff, so nothing here
# needs to wait for "fully online" — masking it is the verified fast-boot path.
echo "[postinst] masking systemd-networkd-wait-online.service (fast boot)"
systemctl mask systemd-networkd-wait-online.service

# H3a (2026-08-23): disarm systemd's OWN automatic update machinery.
#
# Adding `systemd-container` and `systemd-boot` to Packages= (for
# systemd-sysupdate and systemd-bless-boot) drags in three units that
# mkosi's `systemctl preset-all` pass then ENABLES, because the upstream
# preset says to. This was not a guess — measured on the first image built
# with those packages: all three came out `enabled`, and
# `systemd-sysupdate.timer` was live in the booted VM, described as
# "Automatic System Update" and armed to fire ~30 minutes after boot.
#
#   systemd-sysupdate.timer         runs `systemd-sysupdate update` on a
#                                   schedule. On this appliance that means the
#                                   box would install whatever happens to be
#                                   sitting in the staging directory
#                                   (/data/duduclaw/updates), without the
#                                   gateway ever deciding to — and therefore
#                                   without H3d's signature check ever
#                                   having run over it.
#   systemd-sysupdate-reboot.timer  and then REBOOT itself.
#   systemd-boot-update.service     runs `bootctl update` at boot, rewriting
#                                   the bootloader in the ESP. An unannounced
#                                   ESP write is especially unwelcome during
#                                   the boot-assessment window that H3b adds —
#                                   boot counting's whole state lives in ESP
#                                   filenames.
#
# Updating is the gateway's decision (duduclaw-sysd's SysupdateApply verb,
# behind the dashboard), so these are masked rather than merely disabled:
# masking survives any later `preset-all` re-run, exactly like the
# wait-online case above.
#
# TRADE-OFF, recorded deliberately: with systemd-boot-update.service masked,
# the sd-boot binary in the ESP is never refreshed after the factory image, so
# the bootloader ages in place — an A/B update replaces the UKI and the root
# slot, never the ESP's bootloader. Giving bootloader updates a deliberate,
# verified path belongs with the signed payload pipeline (H3d); an unattended
# rewrite of the one thing that makes the machine bootable is not the way to
# get one.
echo "[postinst] masking systemd's own auto-update units (updates are the gateway's decision)"
systemctl mask systemd-sysupdate.timer systemd-sysupdate-reboot.timer systemd-boot-update.service
CHROOT_SETUP
