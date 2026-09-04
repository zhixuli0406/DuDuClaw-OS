# duduclaw-verity.bbclass — build-time dm-verity hash-tree production +
# per-slot UKI cmdline injection (VER-V, 2026-09-02 —
# commercial/docs/DESIGN-os-trust-chain-2026-09.md §3 + 2026-09-02 拍板
# 紀錄 "T4 修正案"/"依賴鏈補記"). Read both before touching this file.
#
# UNCONDITIONALLY inherited by recipes-core/images/duduclaw-image-ab.bb,
# same convention as classes/duduclaw-secure-boot.bbclass one wave prior
# (see that class's own header for the precedent) — everything this class
# DOES is itself gated on DUDUCLAW_VERITY_ENABLE == "1" (no `?=` default
# anywhere in this file for that variable, deliberately matching
# duduclaw-secure-boot.bbclass's own UKI_SB_KEY/UKI_SB_CERT precedent — an
# unset bitbake variable already reads as empty/None, `!= "1"` is `True`
# for that case with no ownership question about who "owns" the off
# default). Set to "1" only by classes/duduclaw-ab-partflags.bbclass. Set
# to "1" by kas/sb-signing.yml (the SB+verity combined test line — see
# that file's own comment for why they are tested together).
#
# Off (unset / anything other than "1"): every task this class adds is a
# fast no-op (first statement, no side effects, no DEPLOY_DIR_IMAGE
# writes), every DEPENDS/IMAGE_CMD:wic:append addition is
# python-conditional to a no-op, and both
# DUDUCLAW_AB_ROOTA_VERITY_WKS_LINE/DUDUCLAW_AB_ROOTB_VERITY_WKS_LINE stay
# at classes/duduclaw-ab-partflags.bbclass's own blank `?=` default — the
# wks, the DEPENDS list, and the final .wic all come out byte-identical to
# a build where this class were never inherited at all. This is the
# load-bearing property this whole wave's own task brief calls "現有 CI
# 不能壞" — verified by construction in each block below, not merely
# asserted.
#
# =========================================================================
# THE CORE PROBLEM THIS CLASS SOLVES: root-A's content must be HASHED and
# WRITTEN as the exact same bytes
# =========================================================================
#
# dm-verity's roothash is a cryptographic digest of root-A's own on-disk
# filesystem bytes. That roothash then gets baked, at build time, into a
# Secure-Boot-signed UKI's cmdline (T4's own per-slot dual-sign mechanism
# — classes/duduclaw-ab-dualsign-uki.bbclass). do_uki/do_uki_slotb/
# do_uki_rescue ALL run BEFORE do_image_wic in the existing task graph
# (classes/duduclaw-ab-partflags.bbclass's own DUDUCLAW_AB_ROOTA_PARTUUID
# comment already establishes this ordering, for the unrelated PARTUUID
# problem — the same ordering constraint applies here for the identical
# underlying reason: a signed artifact can't embed a fact about a file
# that does not exist yet). That means the roothash must be known, and
# root-A's REAL final bytes must already exist as a build artifact, BEFORE
# wic ever runs — root-A cannot be "whatever wic's own `rootfs` source
# plugin happens to build," because that build only happens INSIDE
# do_image_wic, one step too late.
#
# The fix: build root-A's content ONCE, as a plain ext4 FILE (not a wic
# partition), hash THAT FILE with `veritysetup format`, and have wic copy
# that SAME FILE verbatim into the root-A partition via its `rawcopy`
# source plugin (byte-identical BY CONSTRUCTION — a literal `dd`-style
# copy, not a second independent `mkfs.ext4` invocation that could produce
# different bytes for the same logical content, e.g. via a different
# random filesystem UUID or creation timestamp neither tool pins for this
# purpose). This is why files/wic/duduclaw-ab-bootdisk.wks.in's p2 line
# now sources from ${DUDUCLAW_AB_ROOTA_WIC_SOURCE} instead of a hard-coded
# `rootfs` plugin invocation — see that variable's own default in
# classes/duduclaw-ab-partflags.bbclass.
#
# REFACTORED (2026-09-02, main-line live-fire feedback — round-4 real
# `bitbake` failures, not theoretical): the FIRST version of this class
# built that ext4 file itself, by hand (`oe.path.copyhardlinktree()` the
# rootfs minus /boot, then a hand-rolled `mkfs.ext4 -d`, mirroring
# image_types.bbclass's own `oe_mkext234fs()` shape under `fakeroot`). A
# real bake reproduced "Cannot change ownership to uid 0: Operation not
# permitted" out of the tar step inside `copyhardlinktree()` on every
# root-owned rootfs entry, even with `[fakeroot] = "1"` correctly set and
# verified present (`bitbake-getvar` confirmed the flag; child processes
# saw `uid=0` and the LD_PRELOAD pseudo library; a live `chown 0:0` probe
# inside this exact task STILL failed). Root cause not conclusively
# isolated after real investigation — not worth chasing further per this
# wave's own "don't over-engineer" discipline. Reworked instead to need
# NO pseudo/fakeroot semantics at all: let oe-core's OWN
# battle-tested `do_image_ext4` task (image_types.bbclass's
# `oe_mkext234fs()`, already `fakeroot`, already pseudo-correct — it is
# the SAME mechanism `do_rootfs` itself trusts) build root-A's ext4
# content, and have this class's own task do nothing more than a plain
# file copy + `veritysetup format` against the finished artifact — see
# "WHY NO fakeroot" further down for the full reasoning, and IMAGE_FSTYPES
# below for how `do_image_ext4` gets pulled in.
#
# ACCEPTED TRADE-OFF (recorded, not silently absorbed): `do_image_ext4`
# has no `--exclude-path boot/` equivalent — it builds straight from
# `${IMAGE_ROOTFS}` as-is (image_types.bbclass's own `oe_mkext234fs()`:
# `mkfs.$fstype -F ... -d ${IMAGE_ROOTFS}`, no filtering hook at all).
# root-A's own ext4 content therefore now carries whatever this image's
# `${IMAGE_ROOTFS}/boot` holds (kernel image, initramfs, etc. — the same
# content the ORIGINAL `--source rootfs --exclude-path boot/` line used to
# strip), rather than an empty placeholder directory. This is DEAD WEIGHT,
# not a correctness bug: at runtime `/boot` is never read from root-A at
# all (the ESP, a completely separate GPT partition, is what
# systemd-boot/the UKI actually boot from — see this file's own
# `root=PARTUUID=` discussion below), so a stray kernel image sitting
# unused inside root-A's own filesystem is harmless, only wasted space —
# typically on the order of tens-to-low-hundreds of MB depending on
# machine/kernel config, well inside the multi-GB slot budget
# (DUDUCLAW_AB_SLOT_SIZE_MB) this layer's own real-hardware image recipes
# already size for. Reversible later (a future wave could reintroduce
# path-filtering via a copy-then-strip-then-mkfs step) without touching
# anything else in this design; not worth the pseudo/fakeroot complexity
# this wave just spent a real bake cycle discovering was not free.
#
# root-B is UNAFFECTED by this problem: it ships empty (`_empty`, no real
# content) at factory-build time either way, so root-b-verity ships empty
# too — only root-a-verity needs a real hash tree this wave. A future
# update INTO root-B (systemd-sysupdate, 15-duduclaw-root-verity.transfer
# below) writes both the new root payload AND its hash tree as one
# already-matched pair produced by a FUTURE release's own run of this
# exact task — the device never has to compute a hash tree itself.
#
# Task ordering this class establishes (VER-V's own task brief states this
# literally: "ext4 → verity format → do_uki* → do_image_wic"; the ext4
# step is now oe-core's OWN do_image_ext4, not a task this class defines):
#
#   do_image → do_image_ext4 → do_duduclaw_verity_format → do_uki
#            → do_uki_rescue → do_uki_slotb → do_image_wic → do_deploy
#            → do_image_complete
#
# WHY do_image_ext4, NOT do_image_complete, IS THE RIGHT ANCHOR: read
# image.bbclass's own per-fstype task generator before making this call —
# `do_image_ext4`/`do_image_wic` are BOTH scheduled `after do_image` and
# `before do_image_complete` (siblings, not sequenced against each other
# by default); `do_image_complete` runs LAST, after every `do_image_<type>`
# task including `do_image_wic` itself. `do_image_ext4`'s own RAW output
# lands in `IMGDEPLOYDIR` (image.bbclass: `IMGDEPLOYDIR =
# "${WORKDIR}/deploy-${PN}-image-complete"`, a per-recipe-build STAGING
# directory, cleaned only once at `do_rootfs[cleandirs]` time) — it is
# `do_image_complete`'s own sstate output-dirs mechanism
# (`do_image_complete[sstate-outputdirs] = "${DEPLOY_DIR_IMAGE}"`) that
# promotes `IMGDEPLOYDIR` content into the REAL `${DEPLOY_DIR_IMAGE}`, and
# that promotion has not happened yet by the time `do_image_wic` (or this
# class's own task, which must run even earlier, before `do_uki`) needs
# root-A's content. This class's own task therefore reads the ext4
# artifact straight out of `IMGDEPLOYDIR` (the same location
# `do_image_ext4` itself just wrote it, still valid for the rest of this
# recipe's build) and copies it into the REAL `${DEPLOY_DIR_IMAGE}` under
# this class's own stable name — see the task body's own comment for the
# full citation trail, including why `${DEPLOY_DIR_IMAGE}` (not
# `IMGDEPLOYDIR`) is where wic's `rawcopy` plugin actually looks.
#
# =========================================================================
# WHY THE UKI CMDLINE VOCABULARY IS `roothash=` + `hashdev=PARTUUID=...`,
# NOT systemd's `systemd.verity_root_*=`, AND NOT a fully self-chosen set
# =========================================================================
#
# DESIGN-os-trust-chain-2026-09.md §3.2's own P1 plan assumed
# `systemd.verity_root_data=`/`systemd.verity_root_hash=`
# (systemd-veritysetup-generator's own cmdline vocabulary). The 2026-09-02
# "依賴鏈補記" decision found this project's UKI initrd is
# initramfs-framework (recipes-core/images/core-image-minimal-
# initramfs.bbappend's own INITRAMFS_SCRIPTS list — no systemd binary ever
# runs in this initrd), so that vocabulary has ZERO consumer here.
#
# The ACTUAL vocabulary this class bakes is NOT freely self-chosen either
# — grepped for existing consumers before inventing anything, and found
# two already committed, real ones this class must interoperate with,
# both dated the same day as this wave's own task brief:
#
#   crates/duduclaw-gateway/src/uki_patch.rs's `ROOTHASH_TOKEN = "roothash="`
#   (+ `cmdline_roothash()`, a 64-hex-char fixed-width field exactly like
#   `ROOT_PARTUUID_TOKEN`'s own 36-char UUID) and
#   crates/duduclaw-gateway/src/os_update.rs's
#   `verify_verity_roothash_consistency()`, which reads that SAME token
#   out of a staged UKI's cmdline to cross-check it against the release's
#   signed hash tree before ever letting sysupdate install it.
#   appliance/tools/make-payload.py's `find_cmdline_roothash()` (also
#   bare `roothash=`) does the equivalent build-host-side check for the
#   Debian/mkosi line.
#
# So `roothash=<64-hex>` is REUSED verbatim, not renamed to
# `duduclaw_verity_roothash=` as an earlier draft of this class
# considered — a self-chosen prefix would have silently broken both of
# those already-shipping consistency checks (`cmdline.find("roothash=")`
# would simply never match `duduclaw_verity_roothash=`, degrading them to
# their own documented "not adopted yet" no-op path forever, on every
# build that actually DOES set DUDUCLAW_VERITY_ENABLE=1 — a silent
# regression of a real safety net, not a cosmetic mismatch).
#
# `root=` ALSO stays completely untouched — recipes-core/images/
# duduclaw-image-ab.bb's existing `UKI_CMDLINE`/`UKI_SLOTB_CMDLINE`
# already bake `root=PARTUUID=${DUDUCLAW_AB_ROOTA_PARTUUID}` /
# `root=PARTUUID=${DUDUCLAW_AB_ROOTB_PARTUUID}` (T4's own per-slot
# constants), and `uki_patch.rs`'s own `root_partuuid()` parses exactly
# that shape — this class's prefuncs never touch UKI_CMDLINE/
# UKI_SLOTB_CMDLINE's own `root=` token, only APPEND after it. The
# initramfs verity module (recipes-core/initrdscripts/
# initramfs-module-duduclaw-verity_1.0.bb) reads the framework's own
# already-parsed `$bootparam_root` (still literally "PARTUUID=<uuid>" at
# the point that module runs, since it runs BEFORE 90-rootfs) as
# dm-verity's DATA device — no separate data-device token needed at all,
# it is simply the existing `root=` value read one module earlier than
# usual. Only ONE new token was genuinely needed, because nothing existing
# names the HASH-TREE partition: `hashdev=PARTUUID=<uuid>` (this class's
# own choice, kept in the SAME bare, no-prefix style as `roothash=` for
# consistency, and the SAME `<token>PARTUUID=<36-char-uuid>` fixed-width
# shape `root=` and a future Rust-side reader could parse with
# uki_patch.rs's own existing `cmdline_field()` helper unmodified, should
# one ever be needed).
#
# =========================================================================
# WHY THREE PREFUNCS, NOT ONE — d.setVar() DOES NOT CROSS TASK BOUNDARIES
# =========================================================================
#
# do_uki / do_uki_rescue / do_uki_slotb are THREE SEPARATE bitbake tasks,
# each executed in its own forked worker process with its own copy of the
# datastore. A prefunc's `d.setVar('UKI_CMDLINE', ...)` mutation is visible
# to the REST OF THAT SAME TASK's execution (prefuncs and the main task
# body share one process, one datastore instance, for the duration of
# that ONE task — this is prefuncs' whole purpose, same mechanism
# image.bbclass's own per-fstype task generator uses for its
# `set_image_size` prefunc) but does NOT persist into a DIFFERENT task's
# own process, even a later one in the same recipe build. This means
# do_uki_rescue's own `UKI_RESCUE_CMDLINE ?= "${UKI_CMDLINE}
# systemd.unit=duduclaw-rescue.target"` default, despite textually
# referencing `${UKI_CMDLINE}`, does NOT automatically pick up whatever
# do_uki's own prefunc appended to UKI_CMDLINE during do_uki's separate
# run — it re-expands `${UKI_CMDLINE}` against ITS OWN task's copy of the
# datastore, which never saw that mutation. Each of the three UKI tasks
# below gets its own dedicated prefunc for exactly this reason, all three
# calling the one shared duduclaw_verity_inject_tokens() Python function
# (defined once, top-level in this file, callable from any of them) to
# avoid triplicating the actual string-building logic.
#
# =========================================================================
# WHY NO fakeroot — this task never touches pseudo-tracked file ownership
# =========================================================================
#
# The pre-refactor version of this task needed `fakeroot` because it
# MATERIALIZED a copy of the rootfs tree (tens of thousands of files, many
# root-owned, some setuid) and ran `mkfs.ext4 -d` against that copy — real
# per-inode ownership metadata that only resolves correctly inside the
# pseudo session bitbake's `fakeroot` task wrapper provides (and, per the
# round-4 live-fire failure this refactor responds to, did NOT resolve
# correctly for this particular hand-rolled task shape even so — see
# above). The REFACTORED task does exactly two things: (1) `shutil.copyfile()`
# a single already-finished regular file (oe-core's own `do_image_ext4`
# output — a `fakeroot` task in its own right, already pseudo-correct,
# same trust boundary `do_rootfs` itself relies on) from `IMGDEPLOYDIR` to
# `DEPLOY_DIR_IMAGE`, and (2) runs `veritysetup format`, which reads that
# file's CONTENT (bytes) and writes a NEW, plain, build-user-owned hash
# tree file — neither step ever inspects or sets a uid/gid on anything.
# Copying or hashing a file's bytes does not require pseudo any more than
# `sha256sum`/`cp` on a build host normally does. `[fakeroot]` and the
# `virtual/fakeroot-native:do_populate_sysroot` depends the previous round
# added are both removed accordingly — carrying them forward would be
# cargo-culted caution with no remaining justification, not a safety
# margin.
#
# =========================================================================
# HONESTLY UNVERIFIED (still no successful end-to-end bake of THIS
# refactored shape as of this edit — the round-4 failure was against the
# PREVIOUS copyhardlinktree design, not this one)
# =========================================================================
#
# - `veritysetup format`'s exact stdout shape ("Root hash:\t<hex>", the
#   line this class's regex parses) is cited from cryptsetup's own
#   long-stable, widely-documented CLI output convention — this container
#   had no built veritysetup binary to run and confirm against literally.
#   FIRST REAL VERIFICATION STEP for whoever bakes this: run
#   `bitbake duduclaw-image-ab` (or -flatpak) with DUDUCLAW_VERITY_ENABLE=1
#   and inspect do_duduclaw_verity_format's own log for either a clean
#   pass or the bb.fatal() this class raises if the regex ever fails to
#   match — that failure mode is loud and specific on purpose, not a
#   silent wrong-roothash.
# - The IMGDEPLOYDIR→DEPLOY_DIR_IMAGE reasoning above is a code-level
#   citation trail (image.bbclass's own IMGDEPLOYDIR/sstate-outputdirs
#   definitions, image_types_wic.bbclass's own WICVARS list including
#   DEPLOY_DIR_IMAGE), not something re-run end to end in this
#   reconnaissance-only session either — the next real bake is the actual
#   proof.
# - The ESP capacity risk DESIGN-os-trust-chain-2026-09.md §6 already
#   flags (longer cmdline → bigger UKI, against an already-tight 73.8MiB
#   H3e margin) is UNCHANGED by anything in this class and still needs a
#   real three-UKI-coexistence measurement once this bakes for real.
# - The accepted /boot trade-off above (see "ACCEPTED TRADE-OFF") is a
#   reasoned judgment call, not a measured byte count for THIS project's
#   own kernel/initramfs — worth a quick `du -sh` on the produced ext4 at
#   first bake to confirm it is the "tens-to-low-hundreds of MB" order of
#   magnitude assumed, not something larger.

# cryptsetup-native only -- e2fsprogs-native is NOT needed here: this
# class no longer calls mkfs.ext4/fsck.ext4 itself (see "WHY NO fakeroot"
# below for the refactor that removed that call). oe-core's own
# image_types.bbclass already carries
# `do_image_ext4[depends] += "e2fsprogs-native:do_populate_sysroot"`
# unconditionally for any recipe whose IMAGE_FSTYPES contains "ext4"
# (verified by reading that exact line, this layer's pinned oe-core
# commit) -- IMAGE_FSTYPES:append below is what pulls do_image_ext4 in at
# all; its own DEPENDS is oe-core's problem, not this class's.
DEPENDS:append = "${@ ' cryptsetup-native' if d.getVar('DUDUCLAW_VERITY_ENABLE') == '1' else ''}"

# veritysetup in the TARGET rootfs too (round-7 harness evidence:
# "-sh: veritysetup: command not found" in the booted system) — the
# initramfs module RDEPENDS pulls cryptsetup into the INITRD only; the
# running system needs the same tool for status introspection
# (`veritysetup status duduclaw-vroot`, wavever VV1) and for any future
# operator diagnostics on a live verity root. Conditional like everything
# else here.
IMAGE_INSTALL:append = "${@ ' cryptsetup' if d.getVar('DUDUCLAW_VERITY_ENABLE') == '1' else ''}"

# Static /boot + /data fstab lines (round-8 QEMU root cause, full evidence
# at DUDUCLAW_AB_ESP_PARTUUID's definition in duduclaw-ab-partflags
# .bbclass): wic only injects fstab entries into partitions built by its
# `rootfs` source plugin — the rawcopy'd verity root never receives them,
# so the booted image had NO data.mount at all and the entire /data bind
# chain (journald included) collapsed. With p1/p6 PARTUUIDs now build-time
# constants, the two lines can simply be baked into the hashed rootfs.
# Mount option parity with the wic-generated lines they replace: /data
# keeps x-systemd.growfs + fspassno 2 (wks p6's own comment explains both
# are load-bearing); /boot keeps stock defaults (rw — firstboot's
# secure-boot-enroll downgrade and sysupdate's UKI writes both need it).
# Gated on DUDUCLAW_VERITY_ENABLE: the non-verity build still gets its
# fstab lines from wic's own injection, and static duplicates would race
# it.
duduclaw_verity_static_fstab () {
    if [ "${DUDUCLAW_VERITY_ENABLE}" != "1" ]; then
        return 0
    fi
    cat >> ${IMAGE_ROOTFS}${sysconfdir}/fstab <<EOF
PARTUUID=${DUDUCLAW_AB_ESP_PARTUUID}	/boot	vfat	defaults	0	0
PARTUUID=${DUDUCLAW_AB_DATA_PARTUUID}	/data	ext4	defaults,x-systemd.growfs	0	2
EOF
}
ROOTFS_POSTPROCESS_COMMAND += "duduclaw_verity_static_fstab; "

# Pulls in oe-core's own do_image_ext4 task (image_types.bbclass) — see
# this class's header "REFACTORED" section for why this class now reuses
# that already-fakeroot-correct mechanism instead of building root-A's
# ext4 content itself. "ext4" is appended, never assigned outright, so a
# build that already customizes IMAGE_FSTYPES for some other reason (this
# layer's own duduclaw-image-minimal.bb `IMAGE_FSTYPES:append = " wic"`,
# for instance) keeps every existing entry — this only ever ADDS the one
# new type this class needs, and only when DUDUCLAW_VERITY_ENABLE=1 (off:
# IMAGE_FSTYPES is untouched, do_image_ext4 is never scheduled at all,
# matching this whole class's "off = byte-identical" contract).
IMAGE_FSTYPES:append = "${@ ' ext4' if d.getVar('DUDUCLAW_VERITY_ENABLE') == '1' else ''}"

# Pin the ext4 artifact to EXACTLY the A/B slot budget (round-5 real bake
# failure): image.bbclass sizes loose fstypes as
# max(du*IMAGE_OVERHEAD_FACTOR, IMAGE_ROOTFS_SIZE) + IMAGE_ROOTFS_EXTRA_SPACE
# — with the stock 1.3 overhead factor this rootfs came out 10418365 kB,
# and wic's rawcopy correctly refused to place a 9.9 GiB file into the
# 7168 MiB fixed-size root-A partition ("File system image of partition /
# is larger ... than its allowed size"). For a verity rawcopy source the
# artifact SHOULD equal the slot budget anyway (the hash tree covers the
# filesystem image byte range; growing it at runtime is impossible on an
# ro+verity root, so headroom-for-growth sizing is meaningless here).
# Overhead 1.0 + extra 0 + floor=slot gives: size = max(du, slot) — i.e.
# exactly the slot unless the rootfs genuinely no longer fits, in which
# case mkfs fails loudly (the honest signal; same budget the wic path
# always enforced). setVar'd in the anonymous block only when verity is
# on, so the off-case keeps every stock sizing default byte-identical.
python () {
    if d.getVar('DUDUCLAW_VERITY_ENABLE') != '1':
        return
    slot_mb = int(d.getVar('DUDUCLAW_AB_SLOT_SIZE_MB') or '7168')
    d.setVar('IMAGE_ROOTFS_SIZE', str(slot_mb * 1024))
    d.setVar('IMAGE_OVERHEAD_FACTOR', '1.0')
    d.setVar('IMAGE_ROOTFS_EXTRA_SPACE', '0')
}

# Hash algorithm + intermediate/final artifact filenames. Non-timestamped
# (derive only from DISTRO_VERSION, not IMAGE_NAME/DATETIME) — same
# convention recipes-core/images/duduclaw-image-ab.bb's own UKI_FILENAME
# already uses for exactly the same reason (a do_image_wic-consumed
# DEPLOY_DIR_IMAGE artifact must have a name stable across re-parses of
# the SAME build, not one that drifts with wall-clock time).
#
# DUDUCLAW_VERITY_ROOTA_IMG_FILENAME: root-A's ext4 payload, this class's
# own STABLE-named copy of oe-core's do_image_ext4 output (see the
# "REFACTORED" header section for why this is a copy of an oe-native
# artifact, not something this class builds itself). BOTH wic's rawcopy
# (DUDUCLAW_AB_ROOTA_WIC_SOURCE, set below) AND `veritysetup format`'s own
# data-device argument point at this SAME copied file.
#
# DUDUCLAW_VERITY_HASHTREE_FILENAME: the contract name given by this
# wave's own task brief verbatim (`duduclaw-os_${DISTRO_VERSION}.verity-
# x86-64.raw`) — this is the file wic's rawcopy writes into
# root-a-verity AND the same file a future release's copy of this class
# produces for 15-duduclaw-root-verity.transfer to ship as an OTA update
# payload (recipes-duduclaw/duduclaw-ab-update/files/ — see that file's
# own header).
#
# DUDUCLAW_VERITY_ROOTHASH_FILENAME: a plain-text sidecar (one line, 64
# lowercase hex chars) — the hand-off medium between
# do_duduclaw_verity_format (writer) and the three
# duduclaw_verity_inject_cmdline_* prefuncs (readers), each in their OWN
# separate task process (see this file's header on why d.setVar() alone
# cannot do this job across tasks). A file in DEPLOY_DIR_IMAGE is the same
# kind of cross-task hand-off mechanism this layer already relies on
# throughout (do_uki itself locates the kernel/initramfs/stub it embeds
# the exact same way, by DEPLOY_DIR_IMAGE-relative filename, not via any
# in-memory value another task computed).
DUDUCLAW_VERITY_HASH_ALGO ?= "sha256"
DUDUCLAW_VERITY_ROOTA_IMG_FILENAME ?= "duduclaw-os_${DISTRO_VERSION}.root-a-content.ext4"
DUDUCLAW_VERITY_HASHTREE_FILENAME ?= "duduclaw-os_${DISTRO_VERSION}.verity-x86-64.raw"
DUDUCLAW_VERITY_ROOTHASH_FILENAME ?= "duduclaw-os_${DISTRO_VERSION}.verity-x86-64.roothash"

# Hash-tree partition budget (VER-V's own task brief: "bbclass 設預設",
# unlike DUDUCLAW_AB_SLOT_SIZE_MB/DUDUCLAW_AB_DATA_SIZE_MB which live in
# duduclaw-ab-partflags.bbclass — this size is a verity-specific concern,
# owned by the verity-specific class, matching how
# classes/duduclaw-ab-dualsign-uki.bbclass owns UKI_SLOTB_FILENAME rather
# than dumping it into the base A/B class). 128MB against an actual root
# rootfs of roughly 1.2G (duduclaw-image.bb) up to ~10G
# (duduclaw-image-flatpak.bb / genericx86-64, per
# duduclaw-ab-partflags.bbclass's own DUDUCLAW_AB_SLOT_SIZE_MB comment) —
# DESIGN-os-trust-chain-2026-09.md §6's own risk-table citation
# (ejaaskel.dev, a dm-verity-on-Yocto write-up) suggests an 8-10% overhead
# BUDGET as a conservative rule of thumb, not a measured value for THIS
# project's own rootfs; SHA-256's actual per-block hash-tree overhead is
# normally well under 1% of data size for a multi-block-tree at typical
# 4096-byte blocks. 128MB is comfortably above either estimate for a
# 3072MB slot; do_duduclaw_verity_format below bb.fatal()s loudly if the
# real, measured tree ever exceeds this budget rather than silently
# growing wic's own partition past its declared --fixed-size.
DUDUCLAW_AB_VERITY_SIZE_MB ?= "128"

# --- root-A source-mechanism + wks-line overrides (parse time) ---------
#
# Strong `=` (not `?=`) deliberately: classes/duduclaw-ab-partflags.bbclass
# already provides the "off" default for each of these five variables
# (DUDUCLAW_AB_ROOTA_WIC_SOURCE, DUDUCLAW_AB_ROOTA_VERITY_WKS_LINE,
# DUDUCLAW_AB_ROOTB_VERITY_WKS_LINE, DUDUCLAW_AB_ROOTB_PARTNUM,
# DUDUCLAW_AB_DATA_PARTNUM); this block's whole job is to OVERRIDE them, and only when
# DUDUCLAW_VERITY_ENABLE=1. Runs at recipe-parse time (anonymous python,
# no task involved) — by the time files/wic/duduclaw-ab-bootdisk.wks.in
# gets expanded (image_types_wic.bbclass's do_write_wks_template, itself a
# task-time operation, necessarily AFTER all parsing) these four variables
# already hold their final value regardless of bbclass inherit order.
#
# Each `part ...` line is built with plain Python string formatting
# (%-substitution against values already pulled out via d.getVar()), NOT
# by embedding further ${VAR} references inside the resulting string —
# deliberately: a value that itself contains ${OTHER_VAR} would need a
# SECOND bitbake expansion pass to resolve when the wks template
# ultimately reads ${DUDUCLAW_AB_ROOTA_VERITY_WKS_LINE}, and whether
# bitbake re-scans an already-expanded variable's OWN result for further
# ${...} patterns is exactly the kind of behavior
# classes/duduclaw-secure-boot.bbclass's own IMAGE_EFI_BOOT_FILES:append
# comment already flagged as "not something this ticket wanted to depend
# on being true" — same call made here, for the same reason.
python () {
    if d.getVar('DUDUCLAW_VERITY_ENABLE') != '1':
        return

    roota_img = d.getVar('DUDUCLAW_VERITY_ROOTA_IMG_FILENAME')
    hashtree = d.getVar('DUDUCLAW_VERITY_HASHTREE_FILENAME')
    verity_size = d.getVar('DUDUCLAW_AB_VERITY_SIZE_MB')
    distro_version = d.getVar('DISTRO_VERSION')
    roota_verity_uuid = d.getVar('DUDUCLAW_AB_ROOTA_VERITY_PARTUUID')
    rootb_verity_uuid = d.getVar('DUDUCLAW_AB_ROOTB_VERITY_PARTUUID')

    # p2 (root-A): rawcopy the SAME file do_duduclaw_verity_format hashes
    # — see this class's header for why byte-identity depends on this.
    d.setVar('DUDUCLAW_AB_ROOTA_WIC_SOURCE',
             'rawcopy --sourceparams="file=%s"' % roota_img)
    # ...and NO cosmetic ext4 label on p2 (round-6 QEMU root cause, full
    # evidence trail at DUDUCLAW_AB_ROOTA_LABEL_OPT's own default in
    # duduclaw-ab-partflags.bbclass): rawcopy's post-copy
    # do_image_label() rewrites the superblocks inside the partition
    # AFTER the hash tree was computed — "data block 0 is corrupted" on
    # every boot. Blank the option so rawcopy's `if part.label:` branch
    # never fires; the bytes wic places are then the hashed bytes,
    # untouched.
    d.setVar('DUDUCLAW_AB_ROOTA_LABEL_OPT', '')

    # p3 (root-a-verity): rawcopy the hash tree the same task produces.
    # GPT type is SD_GPT_ROOT_X86_64_VERITY (UAPI Discoverable Partitions
    # Specification, uapi-group.org — the same one-hand source
    # DESIGN-os-trust-chain-2026-09.md §3.1 already cites), matching the
    # exact GUID that design doc's §3.1 gives verbatim. `--no-fstab-update`
    # mirrors root-B's own line — this partition is never mounted by
    # fstab, only opened by the initramfs verity module.
    d.setVar('DUDUCLAW_AB_ROOTA_VERITY_WKS_LINE',
             'part --source rawcopy --sourceparams="file=%s" --fstype=ext4 '
             '--align 1024 --uuid="%s" --part-name="duduclaw-verity_%s" '
             '--part-type=2c7357ed-ebd2-46d9-aec1-23d437ec2bf5 '
             '--no-fstab-update --fixed-size %s'
             % (hashtree, roota_verity_uuid, distro_version, verity_size))

    # p5 (root-b-verity): empty twin of root-B, same GPT type as p3 above
    # — no `--source` clause at all (an unformatted-but-`--fstype`-tagged
    # empty partition, matching root-B's own p3/p4 line one section up in
    # the wks — wic's kickstart parser requires SOME --fstype even for an
    # empty partition, same reasoning root-B's own comment already gives).
    d.setVar('DUDUCLAW_AB_ROOTB_VERITY_WKS_LINE',
             'part --fstype=ext4 --align 1024 --uuid="%s" '
             '--part-name="_empty" '
             '--part-type=2c7357ed-ebd2-46d9-aec1-23d437ec2bf5 '
             '--no-fstab-update --fixed-size %s'
             % (rootb_verity_uuid, verity_size))

    # Renumber root-B/data — root-a-verity now sits between root-A and
    # root-B (see classes/duduclaw-ab-partflags.bbclass's own
    # DUDUCLAW_AB_ROOTB_PARTNUM/DUDUCLAW_AB_DATA_PARTNUM comments for the
    # full six-partition contract this produces:
    # ESP=1/root-A=2/root-a-verity=3/root-B=4/root-b-verity=5/data=6).
    d.setVar('DUDUCLAW_AB_ROOTB_PARTNUM', '4')
    d.setVar('DUDUCLAW_AB_DATA_PARTNUM', '6')
}

# --- root-b-verity GPT attribute bits (post do_image_wic) --------------
#
# Own, separate IMAGE_CMD:wic:append() block — bitbake concatenates every
# `:append` of the same shell-function variable across all inherited
# classes into ONE function body (verified against image_types_wic.bbclass
# by classes/duduclaw-ab-partflags.bbclass's own header comment, same fact
# reused here) — so this runs alongside, not instead of, that class's own
# existing root-B/data attribute-fixup hook, in whatever order
# duduclaw-image-ab.bb's own `inherit` lines place the two classes
# (independent partition numbers, independent operations — order between
# them does not matter for correctness).
IMAGE_CMD:wic:append () {
	if [ "${DUDUCLAW_VERITY_ENABLE}" = "1" ]; then
		# GUID:63/60 = NoAuto+ReadOnly — identical bits, identical
		# reasoning to root-B's own attribute fixup one class over: an
		# empty, factory-reserved slot must not be gpt-auto-discoverable
		# or writable until a real update lands in it (see
		# recipes-duduclaw/duduclaw-ab-update/files/
		# 15-duduclaw-root-verity.transfer's own [Target] block, which
		# clears both bits the same way 10-duduclaw-root.transfer already
		# clears them for root-B).
		sfdisk --sector-size 512 --part-attrs "$out.wic" ${DUDUCLAW_AB_ROOTB_VERITY_PARTNUM} "GUID:63,GUID:60"
	fi
}

# --- Build-time hash tree production ------------------------------------
#
# No [fakeroot], no [dirs] workdir requirement either -- this task never
# writes anything outside DEPLOY_DIR_IMAGE (no per-task WORKDIR scratch
# space needed once the copyhardlinktree/mkfs step is gone) and never
# touches file ownership -- see "WHY NO fakeroot" above for the full
# reasoning behind removing both.
python do_duduclaw_verity_format() {
    # `bb` is a bitbake-injected global, but the `import bb.process` / `import
    # bb` later in this function make Python treat `bb` as function-LOCAL for
    # the whole scope — so the no-op path's bb.debug() below would raise
    # UnboundLocalError (only when DUDUCLAW_VERITY_ENABLE != '1', i.e. verity
    # OFF: the enabled path reaches the imports before using bb, which is why
    # verity-ON appliance-test never hit this and verity-OFF appliance did).
    # Bind it up front so the name is assigned before first use.
    import bb
    if d.getVar('DUDUCLAW_VERITY_ENABLE') != '1':
        # Off: no DEPLOY_DIR_IMAGE writes, no side effects at all —
        # byte-identical to a build where this class is not inherited.
        bb.debug(2, "duduclaw-verity: DUDUCLAW_VERITY_ENABLE not set to "
                     "'1' -- do_duduclaw_verity_format is a no-op.")
        return

    import re
    import shutil
    import bb.process

    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')
    bb.utils.mkdirhier(deploy_dir_image)

    # --- locate oe-core's own do_image_ext4 output --------------------
    # image_types.bbclass's own oe_mkext234fs() writes
    # "${IMGDEPLOYDIR}/${IMAGE_NAME}.$fstype" -- IMGDEPLOYDIR
    # (image.bbclass: "${WORKDIR}/deploy-${PN}-image-complete") is a
    # per-recipe-build STAGING directory, NOT ${DEPLOY_DIR_IMAGE} --
    # promotion into the real DEPLOY_DIR_IMAGE only happens via
    # do_image_complete's own sstate output-dirs mechanism, and
    # do_image_complete runs AFTER every do_image_<type> task including
    # do_image_wic (see this class's own header, "WHY do_image_ext4, NOT
    # do_image_complete, IS THE RIGHT ANCHOR", for the full task-graph
    # citation). IMAGE_NAME (unlike IMAGE_LINK_NAME) carries a DATETIME
    # suffix (bitbake.conf: DATE/TIME are `:=` IMMEDIATE-expansion
    # variables, resolved once at config-parse time -- confirmed by
    # reading that exact operator, not assumed -- so every task of this
    # SAME build invocation reads back the identical DATETIME string;
    # this is not a race).
    oe_ext4 = os.path.join(d.getVar('IMGDEPLOYDIR'), d.getVar('IMAGE_NAME') + '.ext4')
    if not os.path.exists(oe_ext4):
        bb.fatal("duduclaw-verity: expected oe-native ext4 artifact %s "
                  "(from IMAGE_FSTYPES:append=' ext4', do_image_ext4) does "
                  "not exist -- check that this task's own conditional "
                  "bb.build.addtask() call (near the task body, below) "
                  "actually resolved 'after' to do_image_ext4 for this "
                  "build (this class really is inherited, IMAGE_FSTYPES "
                  "really contains ext4)." % oe_ext4)

    # --- copy into the REAL DEPLOY_DIR_IMAGE, under a stable name ------
    # wic's own `rawcopy` source plugin (src/wic/plugins/source/rawcopy.py
    # at this layer's pinned wic SRCREV, 5974ade11032f218841d9f449ef0efeee3f9a2ca
    # -- read in full before writing this) resolves its `file=`
    # sourceparam relative to `get_bitbake_var("DEPLOY_DIR_IMAGE")` when no
    # explicit kernel_dir is passed; image_types_wic.bbclass's own WICVARS
    # list explicitly includes DEPLOY_DIR_IMAGE among the variables
    # snapshotted into the `--vars` dir `wic create` reads from (the
    # SAME mechanism that already lets wic's `bootimg_efi` plugin find
    # do_uki's own UKI output, which ALSO lands directly in the real
    # DEPLOY_DIR_IMAGE, not IMGDEPLOYDIR) -- so this class's own rawcopy
    # source for root-A must live in DEPLOY_DIR_IMAGE too, not
    # IMGDEPLOYDIR. A plain `shutil.copyfile()`: this is ONE already-
    # finished regular file (do_image_ext4's own fakeroot task already
    # baked its content correctly), not a tree of per-file ownership
    # metadata -- no pseudo semantics involved, matching "WHY NO
    # fakeroot" above.
    roota_img = os.path.join(deploy_dir_image, d.getVar('DUDUCLAW_VERITY_ROOTA_IMG_FILENAME'))
    shutil.copyfile(oe_ext4, roota_img)

    # --- hash tree: pre-size, then `veritysetup format` writes into it -
    # Pre-sizing (`dd ... seek=... count=0`, sparse-allocate -- not
    # relied-on auto-extend behavior from veritysetup itself, which this
    # class's own header flags as unconfirmed for a regular-file
    # hash-device target) also gives the size-budget check below a real,
    # comparable byte count: a hash tree that legitimately needed MORE
    # than DUDUCLAW_AB_VERITY_SIZE_MB would make `veritysetup format`
    # itself fail against the pre-sized file (loud, at the source of the
    # problem) rather than silently letting wic's own rawcopy plugin grow
    # the partition past its declared --fixed-size later.
    verity_size_mb = int(d.getVar('DUDUCLAW_AB_VERITY_SIZE_MB'))
    hashtree_file = os.path.join(deploy_dir_image, d.getVar('DUDUCLAW_VERITY_HASHTREE_FILENAME'))
    bb.process.run("dd if=/dev/zero of=%s seek=%d count=0 bs=1M" % (hashtree_file, verity_size_mb), shell=True)

    hash_algo = d.getVar('DUDUCLAW_VERITY_HASH_ALGO')
    out, err = bb.process.run(
        "veritysetup format --data-block-size=4096 --hash-block-size=4096 --hash=%s %s %s"
        % (hash_algo, roota_img, hashtree_file), shell=True)

    # "Root hash:\t<hex>" -- cryptsetup's own long-stable CLI output
    # convention (see this class's own header "HONESTLY UNVERIFIED"
    # section: not literally re-run against a built veritysetup binary in
    # this read-only reconnaissance session).
    m = re.search(r'^Root hash:\s*([0-9a-fA-F]+)\s*$', out, re.MULTILINE)
    if not m:
        bb.fatal("duduclaw-verity: could not find a 'Root hash:' line in "
                  "`veritysetup format` output -- refusing to bake an "
                  "unknown/unparsed roothash into a signed UKI. Full "
                  "output:\n%s\n%s" % (out, err))
    roothash = m.group(1).lower()
    if len(roothash) != 64:
        bb.fatal("duduclaw-verity: parsed roothash '%s' is %d hex chars, "
                  "expected 64 (sha256) -- refusing to proceed with a "
                  "value that doesn't match DUDUCLAW_VERITY_HASH_ALGO=%s."
                  % (roothash, len(roothash), hash_algo))

    # rawcopy's own do_prepare_partition() (read above) does `if filesize
    # > part.size: part.size = filesize` -- it only ever GROWS a
    # partition past its wks-declared --fixed-size, never errors when the
    # source file is SMALLER. root-A's own ext4 (do_image_ext4, sized off
    # IMAGE_ROOTFS_SIZE, i.e. actual content, not DUDUCLAW_AB_SLOT_SIZE_MB)
    # is normally well under the multi-GB slot budget, so root-a-verity's
    # partition (this size-budget check's own subject) is the one place
    # an unexpectedly large value could still matter -- kept as a real
    # bb.fatal(), not silently accepted growth, for the identical reason
    # DESIGN-os-trust-chain-2026-09.md's own risk table treats size drift
    # as something to catch loudly rather than absorb quietly.
    actual_size = os.path.getsize(hashtree_file)
    budget_bytes = verity_size_mb * 1024 * 1024
    if actual_size > budget_bytes:
        bb.fatal("duduclaw-verity: hash tree for %s is %d bytes, exceeding "
                  "the DUDUCLAW_AB_VERITY_SIZE_MB=%dMB budget (%d bytes) -- "
                  "wic's rawcopy plugin would silently GROW root-a-verity "
                  "past its declared --fixed-size in "
                  "files/wic/duduclaw-ab-bootdisk.wks.in, drifting this "
                  "wave's own six-partition size contract. Raise "
                  "DUDUCLAW_AB_VERITY_SIZE_MB instead of letting that "
                  "happen silently."
                  % (roota_img, actual_size, verity_size_mb, budget_bytes))

    roothash_file = os.path.join(deploy_dir_image, d.getVar('DUDUCLAW_VERITY_ROOTHASH_FILENAME'))
    with open(roothash_file, 'w') as f:
        f.write(roothash + "\n")

    bb.note("duduclaw-verity: roothash=%s hashtree=%d/%d bytes (%s)"
             % (roothash, actual_size, budget_bytes, hashtree_file))
}
# Wired via a direct bb.build.addtask() call, NOT the bare `addtask ...`
# metadata keyword, and the "after" target is itself picked conditionally
# -- `do_image_ext4` only exists as a registered task at all when
# IMAGE_FSTYPES:append above actually put "ext4" in the list (i.e. only
# when DUDUCLAW_VERITY_ENABLE=1). bb.build.addtask()'s own implementation
# (bitbake/lib/bb/build.py, read directly before writing this) records an
# "after" dependency as a PLAIN STRING with zero existence validation
# against __BBTASKS at call time -- oe-core relies on this permissiveness
# throughout for genuinely-optional cross-class task references, and it
# is very likely tolerated equally well by the runqueue builder later.
# "Very likely" is not "provably" though, and this class had four failed
# real-bake rounds before this refactor even started -- rather than add a
# fifth speculative failure mode on top of an already-costly debugging
# session, this makes the "off" path reference ONLY `do_image` (the SAME,
# always-registered anchor this task used before the do_image_ext4
# refactor), so an unset DUDUCLAW_VERITY_ENABLE never has ANY reason to
# depend on whether a dangling task reference is tolerated. Image
# recipes' own anonymous-python per-fstype task generator
# (image.bbclass, read directly before writing this) is what actually
# creates `do_image_ext4` when "ext4" is present in IMAGE_FSTYPES; this
# class's own `IMAGE_FSTYPES:append` line, positioned identically to this
# exact project's own proven-working `IMAGE_FSTYPES:append = " wic"` in
# recipes-core/images/duduclaw-image-minimal.bb (same file-position
# relationship to its own `require`/`inherit` chain, same append
# mechanism), is trusted to reach that generator correctly on the same
# proven precedent -- not re-derived from bitbake internals archaeology
# in this pass.
python () {
    if d.getVar('DUDUCLAW_VERITY_ENABLE') == '1':
        after = 'do_image_ext4'
    else:
        after = 'do_image'
    bb.build.addtask('duduclaw_verity_format',
                      'do_uki do_uki_rescue do_uki_slotb do_image_wic',
                      after, d)
}

# --- Per-slot UKI cmdline injection (prefuncs) --------------------------
#
# Shared implementation, called from three thin per-task prefuncs below —
# see this class's own header "WHY THREE PREFUNCS" section for why a
# single shared prefunc cannot do all three jobs, and the "WHY THE UKI
# CMDLINE VOCABULARY" section for why this appends `roothash=`/`hashdev=`
# (not `root=` or any `data`-shaped token — `root=PARTUUID=` already exists
# in every cmdline this touches and is deliberately left untouched here).
def duduclaw_verity_inject_tokens(d, cmdline_var, hash_partuuid_var):
    import bb

    if d.getVar('DUDUCLAW_VERITY_ENABLE') != '1':
        return

    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')
    roothash_file = os.path.join(deploy_dir_image, d.getVar('DUDUCLAW_VERITY_ROOTHASH_FILENAME'))
    if not os.path.exists(roothash_file):
        bb.fatal("duduclaw-verity: DUDUCLAW_VERITY_ENABLE=1 but %s is "
                  "missing -- do_duduclaw_verity_format should have "
                  "produced it before %s ran. Check that this class's own "
                  "conditional bb.build.addtask() call is actually in "
                  "effect for this recipe (e.g. this class really is "
                  "inherited)." % (roothash_file, cmdline_var))
    with open(roothash_file) as f:
        roothash = f.read().strip()
    if len(roothash) != 64:
        bb.fatal("duduclaw-verity: %s contains %d chars, expected a bare "
                  "64-hex-char sha256 roothash -- refusing to bake a "
                  "malformed value into %s." % (roothash_file, len(roothash), cmdline_var))

    hash_partuuid = d.getVar(hash_partuuid_var)
    if not hash_partuuid:
        bb.fatal("duduclaw-verity: %s is unset -- cannot inject verity "
                  "cmdline tokens into %s." % (hash_partuuid_var, cmdline_var))

    base = d.getVar(cmdline_var) or ""
    if 'root=PARTUUID=' not in base:
        # Not fatal by itself -- a future consuming recipe could
        # legitimately choose a different root= scheme -- but this class's
        # own initramfs module (recipes-core/initrdscripts/
        # initramfs-module-duduclaw-verity_1.0.bb) reads the data device
        # from the framework's already-parsed $bootparam_root, i.e. from
        # THIS SAME root=PARTUUID= token, not a separate one this class
        # bakes -- warn loudly so a future refactor that drops it doesn't
        # silently produce a verity-enabled UKI with no data device to
        # verify against.
        bb.warn("duduclaw-verity: %s has no 'root=PARTUUID=' token -- the "
                 "initramfs verity module has no data device to verify "
                 "against. Baking roothash=/hashdev= anyway; this is "
                 "almost certainly a configuration mistake."
                 % cmdline_var)
    extra = " roothash=%s hashdev=PARTUUID=%s" % (roothash, hash_partuuid)
    d.setVar(cmdline_var, base + extra)
    bb.debug(2, "duduclaw-verity: %s += %s" % (cmdline_var, extra))

python duduclaw_verity_inject_cmdline_a () {
    duduclaw_verity_inject_tokens(d, 'UKI_CMDLINE',
                                   'DUDUCLAW_AB_ROOTA_VERITY_PARTUUID')
}
do_uki[prefuncs] += " duduclaw_verity_inject_cmdline_a"

# do_uki_rescue's own UKI_RESCUE_CMDLINE default
# (classes/duduclaw-rescue-boot.bbclass: `?= "${UKI_CMDLINE}
# systemd.unit=duduclaw-rescue.target"`) textually references
# ${UKI_CMDLINE}, but that does NOT pick up do_uki's own prefunc mutation
# above -- do_uki_rescue is a SEPARATE task/process (see this class's
# header "WHY THREE PREFUNCS" section). Targeting UKI_RESCUE_CMDLINE
# directly, in do_uki_rescue's own task, is the robust fix: it works
# regardless of whatever UKI_RESCUE_CMDLINE's own base string happens to
# be at any point in the future, rather than depending on it still
# containing a literal, unexpanded "${UKI_CMDLINE}" substring. Rescue mode
# boots the SAME root-A content as the normal entry (task brief's own
# item 4: "rescue UKI 進 rescue target 是否也走 verity root——是，同 root
# 內容") -- slot A's own hash-tree PARTUUID, same as
# duduclaw_verity_inject_cmdline_a (root-A's own root=PARTUUID= is already
# baked into UKI_RESCUE_CMDLINE's own "${UKI_CMDLINE} ..." base string, so
# nothing extra is needed for the data-device side here either).
python duduclaw_verity_inject_cmdline_rescue () {
    duduclaw_verity_inject_tokens(d, 'UKI_RESCUE_CMDLINE',
                                   'DUDUCLAW_AB_ROOTA_VERITY_PARTUUID')
}
do_uki_rescue[prefuncs] += " duduclaw_verity_inject_cmdline_rescue"

python duduclaw_verity_inject_cmdline_b () {
    duduclaw_verity_inject_tokens(d, 'UKI_SLOTB_CMDLINE',
                                   'DUDUCLAW_AB_ROOTB_VERITY_PARTUUID')
}
do_uki_slotb[prefuncs] += " duduclaw_verity_inject_cmdline_b"
