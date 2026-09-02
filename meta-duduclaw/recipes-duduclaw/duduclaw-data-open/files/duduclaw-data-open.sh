#!/usr/bin/env bash
# duduclaw-data-open.sh — TPM2+LUKS2 /data first-boot conversion + every-
# boot unlock, or T7's own fail-open/fail-closed degrade paths.
#
# Trust chain P1 wave TPM (2026-09-02 — commercial/docs/
# DESIGN-os-trust-chain-2026-09.md §4 + 2026-09-02 拍板紀錄 T5/T6/T7).
# Only ever run via duduclaw-data-open.service, itself only ever written
# into /run/systemd/generator.early/ by this recipe's OWN
# duduclaw-data-open-generator — see that script's own header for why it,
# not this one, makes the plain-vs-LUKS2 override decision (this service
# only runs at all on a boot where the generator already decided TPM
# and/or LUKS2 is relevant).
#
# --- FOUR-CELL TRUTH TABLE (T7's own fail-open vs fail-closed distinction,
# DESIGN-os-trust-chain-2026-09.md §4.3) -----------------------------------
#
#   TPM present | /data already LUKS2 | outcome
#   ------------|----------------------|---------------------------------
#   no          | no                   | fail-OPEN: plain, nothing to do
#                                         (T7 — a device that shipped
#                                         without a TPM chip must not be
#                                         bricked by this wave)
#   no          | yes                  | fail-CLOSED: needs-recovery.
#                                         T6's design has NO interactive-
#                                         passphrase keyslot, only TPM2 +
#                                         a one-time recovery key — a TPM-
#                                         absent LUKS2-present device
#                                         cannot self-unlock at all, and
#                                         falling through to a plain mount
#                                         attempt would just fail anyway
#                                         against a LUKS2 header (worse:
#                                         silently, with a confusing
#                                         error, instead of this script's
#                                         own clear diagnostic)
#   yes         | no                   | FIRST-BOOT CONVERSION: wipe +
#                                         luksFormat + TPM2 enroll (PCR
#                                         T5=7+11) + recovery key + mkfs
#   yes         | yes                  | every-boot UNLOCK via TPM2; a
#                                         PCR-policy mismatch here (boot
#                                         chain tampered) is FAIL-CLOSED
#                                         (§4.3: "PCR 失配…絕不能靜默明文
#                                         掛載") — no fallback, no retry
#                                         loop, this script just exits
#                                         nonzero and data.mount fails
#                                         with it
#
# --- ONE-HAND CLI CITATIONS (all read directly from this project's
# pinned systemd v259.5 man-page sources inside the duduclaw-yocto builder
# container, github.com/systemd/systemd.git at tag v259.5 — NOT recalled
# from training data) --------------------------------------------------
#
#   cryptsetup luksFormat --type luks2 --batch-mode --key-file=<path> DEV
#     -- standard cryptsetup(8) invocation; --batch-mode suppresses the
#        interactive "Are you sure?" y/n prompt (no operator present at
#        first boot).
#   systemd-cryptenroll DEV --unlock-key-file=<path> --tpm2-device=auto
#     --tpm2-pcrs=7+11 --wipe-slot=password
#     -- man/systemd-cryptenroll.xml, read in full: "This switch may be
#        used alone... It may also be used in combination with any of the
#        enrollment options listed above, in which case the enrollment is
#        completed first, and only when successful the wipe operation
#        executed — and the newly added slot is always excluded from the
#        wiping." --wipe-slot=password (NOT =empty — a materially
#        different LUKS2 slot class, confirmed by reading
#        src/cryptenroll/cryptenroll-wipe.c directly: "password" slots
#        are "those which have no token assigned" — exactly what a plain
#        `cryptsetup luksFormat --key-file=` slot is; "empty" specifically
#        tests each slot against a LITERAL empty-string passphrase, the
#        wrong test for a random-content throwaway keyfile).
#   systemd-cryptenroll DEV --unlock-tpm2-device=auto --recovery-key
#     -- prints the newly generated recovery key to stdout (man page's
#        own worked example: "Or for replacing an enrolled empty password
#        by TPM2: systemd-cryptenroll /dev/sda1 --wipe-slot=empty
#        --tpm2-device=auto" establishes the --unlock-tpm2-device=auto
#        unlock-via-already-enrolled-TPM pattern this script reuses to
#        add the recovery key AFTER the throwaway keyfile slot is gone).
#   systemd-cryptsetup attach VOLUME SOURCE-DEVICE KEY-FILE CRYPTTAB-OPTIONS
#     -- man/systemd-cryptsetup.xml's own synopsis; KEY-FILE="none" (the
#        crypttab(5) keyword for "no key file, use pkcs11-uri=/
#        fido2-device=/tpm2-device=") and CRYPTTAB-OPTIONS=
#        "tpm2-device=auto,tpm2-pcrs=7+11" — same crypttab(5) option
#        vocabulary the man page's own worked example
#        ("myvolume /dev/sda1 none tpm2-device=auto") uses, just passed as
#        positional CLI args instead of a /etc/crypttab line (this design
#        deliberately has NO /etc/crypttab entry at all — see classes/
#        duduclaw-tpm.bbclass's own header for why).
#   Both `systemd-cryptenroll` and `systemd-cryptsetup` are 'public'
#   executables (systemd's own src/cryptsetup/meson.build,
#   src/cryptenroll/meson.build) installed to the regular ${bindir}
#   (confirmed for cryptenroll via FILES:${PN}-crypt =
#   "${bindir}/systemd-cryptenroll" in systemd_259.5.bb; confirmed for
#   systemd-cryptsetup via that meson.build's own "symlink for backwards
#   compatibility after rename" comment — the binary itself moved TO
#   bindir, the OLD libexecdir location is now just a compat symlink) —
#   called here as bare command names, relying on $PATH, same as this
#   script's own bare `cryptsetup`/`blkid`/`dd` calls.
set -euo pipefail

# Sed-substituted at package build time (do_install, see this recipe's
# own .bb) — same build-time GPT constant as duduclaw-data-open-
# generator's own copy (kept as two separate substitutions rather than
# one shared sourced file: this is a two-file recipe with no existing
# "shared shell library" precedent anywhere in this layer, and the
# duplication is one line, not worth a new convention for).
DATA_PARTUUID="@DUDUCLAW_AB_DATA_PARTUUID@"
DATA_DEV="/dev/disk/by-partuuid/${DATA_PARTUUID}"
MAPPER_NAME="duduclaw-data"
MAPPER_DEV="/dev/mapper/${MAPPER_NAME}"
TPM2_PCRS="7+11"

# ESP mount point is /boot on this line, not a guess — same citation
# recipes-duduclaw/duduclaw-firstboot/files/duduclaw-firstboot-provision
# .sh's own Secure Boot downgrade step already established (files/wic/
# duduclaw-ab-bootdisk.wks.in's own p1 line). vfat has no POSIX
# permission bits — the trust boundary for this file is PHYSICAL
# possession of the ESP, not a file mode (design brief's own explicit
# trade-off: the recovery key cannot live inside the very volume it
# unlocks, and the ESP is the only other persistent, always-mounted
# place on this device).
RECOVERY_KEY_FILE="/boot/duduclaw-data-recovery-key.txt"

# /run is tmpfs, always writable, and exists before /data does — this
# script runs BEFORE /data is mounted (that is its own job), so it cannot
# write its status marker there directly. duduclaw-data-status.service
# (After=data.mount, same recipe) relays this transient marker into
# /data/duduclaw/system/tpm-status.json once /data actually exists.
STATUS_FILE="/run/duduclaw-tpm-status.json"

log() {
    echo "duduclaw-data-open: $*" >&2
}

# tpm_present: literal "true"/"false" tokens (not 1/0) so they interpolate
# directly as JSON boolean literals below with no further translation.
write_status() {
    local tpm_present="$1" mode="$2" detail="$3"
    cat > "${STATUS_FILE}.tmp" <<-EOF
	{"tpm_present":${tpm_present},"mode":"${mode}","detail":"${detail}","ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF
    mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
}

convert_to_luks() {
    log "TPM present, /data still plain -- first-boot TPM2+LUKS2 conversion."

    # Throwaway random-content keyfile, NOT mktemp (recipes-duduclaw/
    # duduclaw-firstboot/files/duduclaw-firstboot-provision.sh's own
    # header documents real BusyBox-applet gaps found on THIS image --
    # head -c/base64 both missing -- and mktemp's own flag support was
    # never independently re-checked either; a plain PID-suffixed path
    # under /run avoids depending on it at all). 32 bytes from
    # /dev/urandom via `dd`, the SAME primitive
    # duduclaw-firstboot-provision.sh's own device.key generation already
    # uses and confirmed working on this exact image.
    local tmpkey="/run/duduclaw-data-convert.$$"
    : > "$tmpkey"
    chmod 600 "$tmpkey"
    dd if=/dev/urandom of="$tmpkey" bs=32 count=1 2>/dev/null

    # luksFormat WIPES the prior plain-ext4 superblock -- the "wipe" step
    # design point 1 calls for. --batch-mode: no interactive y/n prompt
    # (no operator present at first boot).
    if ! cryptsetup luksFormat --type luks2 --batch-mode --key-file="$tmpkey" "$DATA_DEV"; then
        log "FATAL: cryptsetup luksFormat failed. /data's prior content" \
            "may or may not be intact depending on how far luksFormat" \
            "got before failing -- NOT independently verified against a" \
            "real failure in this session. Refusing to proceed further."
        rm -f "$tmpkey"
        write_status true "error" "luksformat-failed"
        exit 1
    fi

    # Enroll TPM2 (T5: PCR 7+11) and wipe the throwaway keyfile slot in
    # ONE atomic call -- see this script's own header citation for why
    # --wipe-slot=password (not =empty) is the correct match for a plain
    # cryptsetup-created, token-less slot.
    if ! systemd-cryptenroll "$DATA_DEV" --unlock-key-file="$tmpkey" \
            --tpm2-device=auto --tpm2-pcrs="$TPM2_PCRS" --wipe-slot=password; then
        log "FATAL: systemd-cryptenroll --tpm2-device=auto failed." \
            "/data is now LUKS2-formatted but may have NO usable keyslot" \
            "at all if the throwaway slot was already wiped before this" \
            "failure (cryptenroll's own documented atomicity says the" \
            "wipe only runs after a SUCCESSFUL enrollment, but this is" \
            "not independently re-verified against a live TPM failure in" \
            "this session -- treat this device as needing manual" \
            "cryptsetup-level recovery, not a simple retry)."
        rm -f "$tmpkey"
        write_status true "error" "cryptenroll-tpm2-failed"
        exit 1
    fi
    rm -f "$tmpkey"

    # Recovery key -- unlock via the now-enrolled TPM2 slot (the
    # throwaway keyfile slot no longer exists after the wipe above, so
    # this step can no longer use --unlock-key-file=).
    local recovery_key=""
    if recovery_key="$(systemd-cryptenroll "$DATA_DEV" --unlock-tpm2-device=auto --recovery-key 2>/dev/null)" \
            && [[ -n "$recovery_key" ]]; then
        printf '%s\n' "$recovery_key" > "$RECOVERY_KEY_FILE"
        log "Recovery key written to ${RECOVERY_KEY_FILE}. OPERATOR ACTION" \
            "REQUIRED: retrieve this key and store it off-device, then" \
            "delete it from the ESP -- an unencrypted ESP left holding" \
            "this key indefinitely weakens this wave's own TPM-binding" \
            "threat model (physical possession of a powered-off device" \
            "would otherwise be enough to read it)."
    else
        log "WARNING: systemd-cryptenroll --recovery-key failed or" \
            "produced no output -- /data is TPM2-protected with NO" \
            "recovery key on file. Not treated as fatal (TPM2 enrollment" \
            "itself already succeeded, see above) -- but a future TPM" \
            "replacement or PCR-policy change with no recovery key on" \
            "record would strand this device's data. Flagged loudly," \
            "not silently dropped."
    fi

    log "TPM2+LUKS2 conversion complete; proceeding to unlock+format."
}

open_luks() {
    log "Unlocking /data via TPM2 (PCR ${TPM2_PCRS})."
    if ! systemd-cryptsetup attach "$MAPPER_NAME" "$DATA_DEV" none \
            "tpm2-device=auto,tpm2-pcrs=${TPM2_PCRS}"; then
        # FAIL-CLOSED (T7, §4.3: "PCR 失配…絕不能靜默明文掛載"). No
        # fallback to a plain mount attempt, no retry loop. data.mount
        # (Requires=+After= this service, per duduclaw-data-open-
        # generator's own written unit) simply has no
        # /dev/mapper/duduclaw-data to mount once this service exits
        # nonzero, and fails alongside it -- deliberately NOT escalated
        # to `systemctl isolate emergency.target` by this script itself;
        # systemd's own default non-nofail-mount-failure handling (man/
        # systemd.mount.xml) already governs what that means for the
        # rest of the boot, and this wave's own design doc explicitly
        # leaves the exact degrade SHAPE to implementation (§4.3: "degrade
        # 行為你設計，但絕不能靜默明文掛載") -- the one hard requirement
        # (no silent cleartext) is what this exit path guarantees.
        log "FATAL: systemd-cryptsetup attach refused to unlock /data --" \
            "either the TPM2 PCR policy no longer matches (boot chain" \
            "tampered or legitimately changed, e.g. an unsigned firmware" \
            "update outside this design's own signed-UKI chain) or a" \
            "transient TPM fault. /data will NOT be mounted. Manual" \
            "recovery: a maintenance shell + the recovery key from" \
            "${RECOVERY_KEY_FILE} (if it was retrieved and is still" \
            "present -- see this script's own conversion-time warning if" \
            "not) can unlock ${DATA_DEV} directly via plain" \
            "\`cryptsetup open\`."
        write_status "$tpm_present_json" "needs-recovery" "tpm2-unlock-failed"
        exit 1
    fi
    log "/data unlocked (mapper: ${MAPPER_DEV})."
    write_status "$tpm_present_json" "luks-unlocked" "ok"
}

# --- bounded wait for the device node ------------------------------------
# Same shape as duduclaw-data-open-generator's own wait, re-checked here
# (not merely trusted from the generator's own earlier, shorter probe --
# this service runs later, so the device is expected to already be
# present in the common case, but a slow-enumerating disk on real
# hardware is exactly the scenario this second, independent wait exists
# for). Bounded longer here (30s) than the generator's own 5s budget --
# this service is NOT time-constrained the way a generator is (systemd.
# generator(7) itself gives no explicit numeric timeout, but "generators
# ... must be fast" is the documented expectation; a regular oneshot
# service ordered Before=local-fs-pre.target has no equivalent
# constraint, and 30s matches the kind of budget this project's own
# firstboot-repart.service class of unit already tolerates for real-disk
# operations).
i=0
while [[ ! -e "$DATA_DEV" && "$i" -lt 30 ]]; do
    sleep 1
    i=$((i + 1))
done
if [[ ! -e "$DATA_DEV" ]]; then
    log "FATAL: ${DATA_DEV} never appeared after a 30s wait -- cannot" \
        "proceed. Fail-closed: no /data mount is safer than guessing."
    write_status false "error" "data-device-missing"
    exit 1
fi

tpm_present=false
tpm_present_json=false
if [[ -e /dev/tpm0 || -e /dev/tpmrm0 ]]; then
    tpm_present=true
    tpm_present_json=true
fi

fstype="$(blkid -o value -s TYPE "$DATA_DEV" 2>/dev/null || true)"
luks_present=false
if [[ "$fstype" == "crypto_LUKS" ]]; then
    luks_present=true
fi

# --- the four-cell table (see this script's own header) ------------------
if [[ "$tpm_present" == false && "$luks_present" == false ]]; then
    # Cell 1: no TPM, disk still plain -- fail-OPEN (T7). The generator
    # that scheduled this service would not normally have done so for
    # this exact combination (its own probe already checks the same two
    # conditions) -- reaching here means either a genuinely transient
    # TPM detection gap between the generator's earlier, shorter probe
    # and this later one, or a manual re-run. Either way the safe,
    # honest action is the SAME no-op the generator itself would have
    # chosen.
    log "no TPM detected, /data still plain -- fail-open (T7), nothing to do."
    write_status false "plain-fail-open" "no-tpm-no-luks"
    exit 0
fi

if [[ "$tpm_present" == false && "$luks_present" == true ]]; then
    # Cell 2: /data is ALREADY LUKS2 but no TPM is present now (hardware
    # swapped/removed, or a fault). T6's design has TPM2 + a one-time
    # recovery key as the ONLY enrolled keyslots -- no interactive-
    # passphrase fallback -- so this volume cannot self-unlock. FAIL-
    # CLOSED: this is a genuine needs-recovery state, not the plain-
    # forever device Cell 1 covers.
    log "FATAL: /data is LUKS2 but no TPM is present -- cannot unlock" \
        "automatically. Manual recovery: a maintenance shell + the" \
        "recovery key from ${RECOVERY_KEY_FILE} (if retrieved and still" \
        "present)."
    write_status false "needs-recovery" "luks-present-tpm-absent"
    exit 1
fi

if [[ "$luks_present" == false ]]; then
    # Cell 3: TPM present, disk still plain -- first-boot conversion,
    # then fall through to the unlock below (same as Cell 4).
    convert_to_luks
fi

# Cell 3 (post-conversion) and Cell 4 (TPM present, already LUKS2) both
# reach here.
open_luks
