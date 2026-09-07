SUMMARY = "DuDuClaw OS: systemd unit for the local llama.cpp model server"
DESCRIPTION = "${SUMMARY}. WP-F of the platform repo's docs/todo/TODO-ai-runtimes-2026-09.md \
(§1 決策 3A). Ships duduclaw-llama-server.service, which runs \
/usr/bin/llama-server (recipes-ai/llama-cpp/) against whatever GGUF the \
gateway's inference.local.* RPCs put in /data/duduclaw/models, configured \
through /data/duduclaw/llama-server.env. \
\
The unit is enabled at build time but STAYS INERT until that env file and \
the models directory both exist -- ConditionPathExists/ \
ConditionPathIsDirectory, so an appliance that only ever uses cloud \
runtimes shows the unit as condition-failed rather than as a restart loop. \
See the unit's own header for why that is a Condition and not an \
ExecStartPre. \
\
Config-only, like duduclaw-flatpak-setup and duduclaw-compat-runners: the \
engine is a separate recipe, and no model weights ship in the image (design \
decision, not an omission -- a curated GGUF is 1-5 GB and the root slot is \
8192 MiB)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://duduclaw-llama-server.service"

S = "${UNPACKDIR}"

inherit systemd

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-llama-server.service ${D}${systemd_system_unitdir}/duduclaw-llama-server.service
}

# Enabled, but see the DESCRIPTION and the unit header: "enabled" here means
# "wanted by multi-user.target", and the unit's own Conditions decide
# whether it actually runs on any given boot. This is the same shape
# duduclaw-flatpak-setup uses (auto-enable a oneshot whose work is
# idempotent/conditional) rather than the duduclaw-rescue shape (never
# enabled, pulled in only by an explicit target Wants=).
SYSTEMD_SERVICE:${PN} = "duduclaw-llama-server.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += "${systemd_system_unitdir}/duduclaw-llama-server.service"

# llama-cpp, not "llama.cpp": the recipe's PN. This is a hard RDEPENDS and
# not merely an image-level co-install, because the unit's ExecStart names
# /usr/bin/llama-server by absolute path -- installing this package without
# the engine would ship a unit that fails at exec time instead of one that
# condition-fails cleanly, which is precisely the distinction this recipe's
# whole design rests on.
#
RDEPENDS:${PN} = "llama-cpp"

# NOT `inherit allarch`, even though the only shipped file is a text unit:
# an allarch package that RDEPENDS on a MACHINE_ARCH one (llama-cpp, which
# pins itself to the two x86-64 machines) is exactly the shape OE's allarch
# handling warns about -- the arch-independent package would be shared
# across machines while its dependency is not. PACKAGE_ARCH =
# ${MACHINE_ARCH} keeps the two in the same feed, at the cost of rebuilding
# a 3 KB package per machine, which is the right trade.
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Anchored to the same two machines llama-cpp builds for, and for the same
# reason (re.match(), "duduclaw-" prefix is load-bearing) -- a unit whose
# ExecStart names a binary that cannot exist on this machine should refuse
# to be built into that image, not ship broken.
COMPATIBLE_MACHINE = "^duduclaw-qemux86-64$|^duduclaw-genericx86-64$"
