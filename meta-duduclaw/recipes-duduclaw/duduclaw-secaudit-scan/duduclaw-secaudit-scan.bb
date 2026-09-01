SUMMARY = "DuDuClaw OS scheduled quick secaudit self-scan (daily timer)"
DESCRIPTION = "${SUMMARY}. WS-3/自掃 timer (2026-09-01, DESIGN-os-security-\
line-2026-09.md §2 secaudit 遷入 D2' / 拍板 D4: 預設開、每日 quick、範圍= \
/data 可寫執行面). Ships a systemd timer + oneshot service that runs \
`duduclaw secaudit --profile quick /data/duduclaw` once a day (jittered \
via RandomizedDelaySec), writing both an explicit timestamped report \
(files/duduclaw-secaudit-scan.sh's own ${REPORT_PATH}) and the CLI's own \
--save dashboard-discoverable copy. quick profile only — zero LLM/agent/ \
network dependency, safe on an offline appliance (拍板 D4's own \"離線機 \
自動降級 quick\" is satisfied by never requesting more than quick in the \
first place). See files/duduclaw-secaudit-scan.sh's own header for the \
exit-code translation (a routine High+ finding must not mark this unit \
'failed'; a genuine infra error does) and files/*.service's own header \
for why the config-schema `[secaudit] scheduled_scan` on/off toggle is \
deliberately NOT wired here (separate ticket's own scope — this timer \
ships unconditionally enabled per 拍板 D4)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://duduclaw-secaudit-scan.sh \
    file://duduclaw-secaudit-scan.service \
    file://duduclaw-secaudit-scan.timer \
"

S = "${UNPACKDIR}"

inherit systemd allarch

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${UNPACKDIR}/duduclaw-secaudit-scan.sh ${D}${sbindir}/duduclaw-secaudit-scan.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-secaudit-scan.service ${D}${systemd_system_unitdir}/duduclaw-secaudit-scan.service
    install -m 0644 ${UNPACKDIR}/duduclaw-secaudit-scan.timer ${D}${systemd_system_unitdir}/duduclaw-secaudit-scan.timer
}

FILES:${PN} += " \
    ${sbindir}/duduclaw-secaudit-scan.sh \
    ${systemd_system_unitdir}/duduclaw-secaudit-scan.service \
    ${systemd_system_unitdir}/duduclaw-secaudit-scan.timer \
"

# Only the .timer carries an [Install] section (WantedBy=timers.target) --
# the .service has none (it is activated BY the timer, not via its own
# enable symlink), same "don't list [Install]-less units in
# SYSTEMD_SERVICE" discipline duduclaw-rescue.bb's own header already
# documents for units reached only through a static Wants=/timer trigger.
# 拍板 D4 ("預設開"): SYSTEMD_AUTO_ENABLE=enable, not the usual
# ship-disabled-let-the-operator-opt-in posture some hardening items in
# this same wave use.
SYSTEMD_SERVICE:${PN} = "duduclaw-secaudit-scan.timer"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# duduclaw-cli provides /usr/bin/duduclaw (the `secaudit` subcommand this
# script's entire purpose is to invoke) -- RDEPENDS, not DEPENDS, same
# "documentation-as-code" convention this layer's other config/glue
# recipes already use (duduclaw-network-config.bb's own RDEPENDS
# comment). Already co-installed on every image this recipe is added to
# (duduclaw-image.bb's own IMAGE_INSTALL already carries duduclaw-cli, see
# that file's own comment) -- named explicitly anyway so this recipe is
# not silently relying on install ORDER within the same image's
# IMAGE_INSTALL list. No `bash` RDEPENDS: unlike duduclaw-firstboot's
# scripts (real bash-isms: `[[`, `set -o pipefail`), this script is pure
# POSIX `/bin/sh` (`[ ]`, no arrays/`[[`) -- checked its own content
# before deciding not to carry the dependency, not copied from another
# recipe's habit.
RDEPENDS:${PN} += "duduclaw-cli"

COMPATIBLE_MACHINE = ".*"
