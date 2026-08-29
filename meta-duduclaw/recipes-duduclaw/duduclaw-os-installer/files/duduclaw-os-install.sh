#!/bin/sh
# DuDuClaw OS installer (Y19, 2026-08-28).
#
# Runs INSIDE the live environment (duduclaw-image-live). Its one job: take
# the already-built, already-signed production A/B disk image that the live
# ISO carries as install material (duduclaw-install.wic.zst — the .wic output
# of duduclaw-image-ab.bb, produced by scripts/release-os.sh, zstd-compressed
# and dropped into the ISO9660 tree by duduclaw-image-live.bb's
# populate_live:append) and write it, whole-disk, onto the target machine's
# internal storage. Then reboot lands on the real UKI+systemd-boot A/B system.
#
# WHY WHOLE-DISK dd, NOT per-partition copy (design doc §3.2.c): the A/B .wic
# is a complete GPT image — ESP (with the build-time-signed UKI whose
# root=PARTUUID= is a fixed constant baked at build), root-A (populated),
# root-B (_empty sysupdate target), /data. The UKI's signature and its
# root=PARTUUID= binding are produced at build time and MUST NOT be
# regenerated at install time — so the correct install is to copy the finished
# artifact byte-for-byte, never to re-expand a rootfs tree the way oe-core's
# stock init-install-efi.sh does. dd of the whole .wic preserves every GPT
# entry, PARTUUID, and the signed UKI exactly as shipped.
#
# AFTER dd: `sgdisk -e` moves the GPT backup header from the image tail (where
# a smaller-than-disk image leaves it) to the real end of the target disk, so
# the kernel reads a clean GPT and the shipped firstboot unit
# (duduclaw-firstboot-repart.sh → systemd-repart against repart.d/30-data.conf)
# can grow /data to fill the disk on first boot. Installer does NOT grow /data
# itself — that is the production system's existing, already-verified job
# (Y11-2). Installer stays minimal: dd + fix GPT + sync + tell the user to
# reboot. Everything else (data growth, OOBE/firstboot provisioning) is the
# real system's first-boot responsibility (design doc §3.4).
#
# AUTOMATION HOOKS (for QEMU end-to-end verification, and for an unattended
# factory flow): DUDUCLAW_INSTALL_TARGET=<disk basename, e.g. vda> selects the
# target non-interactively; DUDUCLAW_INSTALL_YES=1 skips the destructive-write
# confirmation. Absent either, the installer is fully interactive.
#
# DUDUCLAW_INSTALL_PROGRESS=1 (Y20-P3, 2026-08-29): emits machine-readable
# `DUDUCLAW_PROGRESS:<0-100>` lines on THIS SCRIPT's own stdout while the dd
# step runs, so a graphical front end (duduclaw-shell's `live_install`
# module) can drive a determinate progress bar instead of an indeterminate
# spinner. See §5 below for the full wire-format contract and the `pv -n`
# mechanics behind it. No effect when unset/0, or when `pv` is not on PATH —
# the dd step then behaves exactly as it always has (indeterminate `pv`
# bar, or plain `dd` with neither).
#
# DUDUCLAW_INSTALL_OOBE_STATE_FILE / DUDUCLAW_INSTALL_PENDING_ACCOUNT_FILE
# (WP2, 2026-08-29, `DESIGN-installer-settings-integration-2026-08.md`
# §3.2/§4/§8/§9): absolute paths to two scratch JSON files that
# `duduclaw-shell`'s live installer wizard writes BEFORE spawning this
# script (`install_runner.rs`'s `build_oobe_state_json`/
# `build_pending_account_json`, via `serde` — this script never generates
# or reshapes their content, only copies the bytes onto the target disk;
# hand-formatting JSON in `sh`, especially a password that might contain a
# `"` or `\`, is exactly the "format drift" risk the design doc's §8.2
# calls out). See §7 below for the injection step itself. Target paths on
# the target disk's /data partition (wks layout: ESP=1/root-a=2/root-b=3/
# data=4):
#   $DUDUCLAW_INSTALL_OOBE_STATE_FILE      -> duduclaw-kiosk/shell/oobe_state.json
#   $DUDUCLAW_INSTALL_PENDING_ACCOUNT_FILE -> duduclaw/pending-account.json
# Both unset (an operator who backed out of the account step, or a build
# from before this WP) -> §7 is skipped entirely, byte-identical to before
# this round.
set -eu

INSTALL_IMAGE_NAME="duduclaw-install.wic.zst"

c_info='\033[1;36m'; c_warn='\033[1;33m'; c_err='\033[1;31m'; c_ok='\033[1;32m'; c_off='\033[0m'
log()  { printf "${c_info}[installer]${c_off} %s\n" "$*"; }
warn() { printf "${c_warn}[installer]${c_off} %s\n" "$*"; }
err()  { printf "${c_err}[installer] 錯誤:${c_off} %s\n" "$*" >&2; }
ok()   { printf "${c_ok}[installer]${c_off} %s\n" "$*"; }

fail() { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Locate the install material on the live medium.
#    IMPORTANT (verified against oe-core init-live.sh + a live VM): the
#    image-live.bbclass live boot mounts the medium at /run/media/<disk> only
#    during the INITRAMFS phase, then `mount -n --move`s it to /media/realroot
#    just before switch_root (init-live.sh lines 88-89). This installer runs as
#    an ordinary package in the switched-into live rootfs, AFTER that move — so
#    the ISO is at /media/realroot and /run/media/* no longer exists. Search
#    realroot first (the guaranteed path for this topology), then /run/media/*
#    and /media/* as fallbacks for other live topologies (e.g. USB via
#    udev-extraconf auto-mount), then any mounted filesystem as a last resort.
# ---------------------------------------------------------------------------
IMG=""
for d in /media/realroot /run/media/*/ /media/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    if [ -f "${d}/${INSTALL_IMAGE_NAME}" ]; then
        IMG="${d}/${INSTALL_IMAGE_NAME}"
        break
    fi
done
if [ -z "$IMG" ]; then
    # Last resort: scan every mounted filesystem for the install material.
    for d in $(findmnt -rn -o TARGET 2>/dev/null); do
        if [ -f "${d}/${INSTALL_IMAGE_NAME}" ]; then
            IMG="${d}/${INSTALL_IMAGE_NAME}"
            break
        fi
    done
fi
[ -n "$IMG" ] || fail "找不到安裝素材 ${INSTALL_IMAGE_NAME}（已掃 /media/realroot、/run/media/*、/media/* 及所有掛載點；live 媒介未掛載或 ISO 未含安裝映像）"
log "安裝素材：$IMG ($(du -h "$IMG" 2>/dev/null | cut -f1))"

# Which physical disk carries the install material — it must be excluded from
# the target list (never overwrite the medium we are reading from).
SRC_MOUNT="$(dirname "$IMG")"
SRC_PART="$(findmnt -n -o SOURCE --target "$SRC_MOUNT" 2>/dev/null || true)"
SRC_DISK=""
if [ -n "$SRC_PART" ]; then
    SRC_DISK="$(lsblk -no PKNAME "$SRC_PART" 2>/dev/null | head -n1 || true)"
    # Optical media: /dev/sr0 has no parent (PKNAME empty) — the device itself
    # is the disk to exclude.
    [ -n "$SRC_DISK" ] || SRC_DISK="$(basename "$SRC_PART")"
fi
[ -n "$SRC_DISK" ] && log "安裝媒介承載於 /dev/${SRC_DISK}（將自目標清單排除）"

# ---------------------------------------------------------------------------
# 2. Enumerate candidate target disks (TYPE=disk; drop optical/loop/ram and
#    the install medium itself).
# ---------------------------------------------------------------------------
CANDIDATES=""
for disk in $(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); do
    case "$disk" in
        loop*|ram*|sr*|fd*) continue ;;
    esac
    [ -n "$SRC_DISK" ] && [ "$disk" = "$SRC_DISK" ] && continue
    CANDIDATES="$CANDIDATES $disk"
done
CANDIDATES="$(echo "$CANDIDATES" | xargs -n1 2>/dev/null || echo "$CANDIDATES")"
[ -n "$CANDIDATES" ] || fail "找不到任何可安裝的目標磁碟（僅偵測到安裝媒介本身）"

# ---------------------------------------------------------------------------
# 3. Select the target (env override, single-candidate auto, or interactive).
# ---------------------------------------------------------------------------
TARGET=""
if [ -n "${DUDUCLAW_INSTALL_TARGET:-}" ]; then
    for disk in $CANDIDATES; do
        [ "$disk" = "$DUDUCLAW_INSTALL_TARGET" ] && TARGET="$disk" && break
    done
    [ -n "$TARGET" ] || fail "指定的目標 /dev/${DUDUCLAW_INSTALL_TARGET} 不在可安裝清單內：$CANDIDATES"
    log "目標磁碟（環境變數指定）：/dev/${TARGET}"
else
    log "可安裝的目標磁碟："
    for disk in $CANDIDATES; do
        size="$(lsblk -dno SIZE "/dev/${disk}" 2>/dev/null | xargs || echo '?')"
        model="$(lsblk -dno MODEL "/dev/${disk}" 2>/dev/null | xargs || true)"
        printf '    /dev/%s  %s  %s\n' "$disk" "$size" "$model"
    done
    n=0; for disk in $CANDIDATES; do n=$((n+1)); done
    if [ "$n" -eq 1 ]; then
        TARGET="$CANDIDATES"
        log "僅一顆候選磁碟，選定 /dev/${TARGET}"
    else
        printf '請輸入目標磁碟名稱（如 vda / sda / nvme0n1）: '
        read -r ans
        for disk in $CANDIDATES; do
            [ "$disk" = "$ans" ] && TARGET="$disk" && break
        done
        [ -n "$TARGET" ] || fail "'$ans' 不是有效的候選磁碟"
    fi
fi

TARGET_DEV="/dev/${TARGET}"
[ -b "$TARGET_DEV" ] || fail "$TARGET_DEV 不是 block device"

# Size sanity: the target must be at least as large as the DECOMPRESSED image.
# We can't cheaply know the decompressed size without reading the zstd frame
# header; require the target to be at least the compressed size × 3 as a floor,
# and let dd itself hard-fail if the disk is genuinely too small.
TARGET_BYTES="$(blockdev --getsize64 "$TARGET_DEV" 2>/dev/null || echo 0)"
IMG_BYTES="$(stat -c '%s' "$IMG" 2>/dev/null || echo 0)"
if [ "$TARGET_BYTES" -gt 0 ] && [ "$IMG_BYTES" -gt 0 ]; then
    floor=$((IMG_BYTES * 3))
    if [ "$TARGET_BYTES" -lt "$floor" ]; then
        warn "目標磁碟 $(($TARGET_BYTES/1024/1024))MiB 可能太小（安裝映像壓縮後 $(($IMG_BYTES/1024/1024))MiB，解壓後更大）"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Confirm the destructive write.
# ---------------------------------------------------------------------------
warn "即將把 DuDuClaw OS 寫入 ${TARGET_DEV}，該磁碟上的所有資料將被清除且無法復原。"
if [ "${DUDUCLAW_INSTALL_YES:-0}" != "1" ]; then
    printf '確定要繼續嗎？輸入大寫 YES 確認: '
    read -r confirm
    [ "$confirm" = "YES" ] || fail "使用者取消安裝"
fi

# ---------------------------------------------------------------------------
# 5. Write the image (decompress-stream straight to the disk).
# ---------------------------------------------------------------------------
log "正在寫入映像到 ${TARGET_DEV}（解壓串流，請勿中斷電源）…"
# umount anything auto-mounted off the target before writing.
for p in $(lsblk -lno NAME "$TARGET_DEV" 2>/dev/null | tail -n +2); do
    umount "/dev/$p" 2>/dev/null || true
done
# DUDUCLAW_INSTALL_PROGRESS=1 (Y20-P3, 2026-08-29): machine-readable
# progress for a graphical front end. Interface (defined here, consumed by
# `live_install/steps` + `install_runner.rs` in duduclaw-shell — the two
# sides were versioned together in the same round): every line of the exact
# shape `DUDUCLAW_PROGRESS:<0-100>` on THIS SCRIPT's own stdout is a
# percentage sample (integers, not necessarily monotonic to the last digit —
# see below); a final `DUDUCLAW_PROGRESS:100` is always emitted once dd/sync
# settle, regardless of what the last `pv` sample said. No other stdout line
# uses this prefix, so the consumer can filter on it with a plain anchored
# match. When this variable is unset/0, or `pv` is not on PATH, behavior is
# BYTE-IDENTICAL to before this round — the two branches below are
# untouched.
#
# Percent math: `pv -n -s <total>` (numeric mode — one integer 0..100 per
# line on ITS OWN stderr, see pv(1)) needs a byte total up front. The exact
# decompressed size is available WITHOUT a second decompression pass via
# `zstd -lv` (verbose long-listing)'s own "Decompressed Size: ... (<exact
# bytes> B)" line — the parenthesized figure is always the precise byte
# count regardless of which human-readable unit precedes it (verified
# against a live capture: "Decompressed Size: 4.77 MiB (5000000 B)"). If
# that parse ever fails (a future zstd release reformats the line, or a
# multi-frame image this awk doesn't expect), this falls back to
# `IMG_BYTES * 3` — the SAME floor-check ratio the size-sanity warning above
# already uses for the identical "we don't know the exact decompressed
# size" situation — so a percentage still renders, just potentially not
# landing exactly on 100 the instant dd's last byte lands (the script's own
# final `DUDUCLAW_PROGRESS:100` line is what guarantees the consumer always
# sees a clean 100 once the write step is actually done, regardless of what
# pv's own numeric stream reported up to that point).
#
# POSIX `sh` has no process substitution, so pv's numeric stderr stream is
# routed through a named pipe read by a background prefixing loop rather
# than `<(...)` — portable across dash/busybox sh, not just bash.
if [ "${DUDUCLAW_INSTALL_PROGRESS:-0}" = "1" ] && command -v pv >/dev/null 2>&1; then
    TOTAL_BYTES="$(zstd -lv "$IMG" 2>&1 | awk -F'[()]' '/Decompressed Size/{print $2}' | awk '{print $1}')"
    case "$TOTAL_BYTES" in
        ''|*[!0-9]*) TOTAL_BYTES=$((IMG_BYTES * 3)) ;;
    esac
    [ "$TOTAL_BYTES" -gt 0 ] 2>/dev/null || TOTAL_BYTES=$((IMG_BYTES * 3))

    PROGRESS_FIFO="$(mktemp -u "${TMPDIR:-/tmp}/duduclaw-install-progress.XXXXXX")"
    mkfifo "$PROGRESS_FIFO"
    ( while IFS= read -r pct; do
          case "$pct" in *[!0-9]*|'') continue ;; esac
          [ "$pct" -gt 100 ] 2>/dev/null && pct=100
          printf 'DUDUCLAW_PROGRESS:%s\n' "$pct"
      done < "$PROGRESS_FIFO" ) &
    PROGRESS_READER_PID=$!

    zstd -dc "$IMG" | pv -n -s "$TOTAL_BYTES" 2>"$PROGRESS_FIFO" | dd of="$TARGET_DEV" bs=4M conv=fsync 2>/dev/null

    wait "$PROGRESS_READER_PID" 2>/dev/null || true
    rm -f "$PROGRESS_FIFO"
    printf 'DUDUCLAW_PROGRESS:100\n'
elif command -v pv >/dev/null 2>&1; then
    zstd -dc "$IMG" | pv | dd of="$TARGET_DEV" bs=4M conv=fsync 2>/dev/null
else
    zstd -dc "$IMG" | dd of="$TARGET_DEV" bs=4M conv=fsync
fi
log "映像寫入完成，同步中…"
sync

# ---------------------------------------------------------------------------
# 6. Repair the GPT: move the backup header to the real end of the target
#    disk so the kernel sees a clean table and firstboot systemd-repart can
#    grow /data to fill it.
# ---------------------------------------------------------------------------
log "修正 GPT 備援標頭至磁碟末端（讓首次開機自動擴充 /data）…"
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -e "$TARGET_DEV" >/dev/null 2>&1 || warn "sgdisk -e 回報非零（首次開機的 systemd-repart 仍會重整 GPT）"
else
    warn "找不到 sgdisk，跳過 GPT 末端修正（首次開機的 systemd-repart 會自行處理）"
fi
partprobe "$TARGET_DEV" 2>/dev/null || true
sync

# ---------------------------------------------------------------------------
# 7. Inject the live wizard's collected settings onto the target /data
#    partition (WP2, 2026-08-29 — see this script's own header comment for
#    the full `DUDUCLAW_INSTALL_OOBE_STATE_FILE`/
#    `DUDUCLAW_INSTALL_PENDING_ACCOUNT_FILE` env-var contract).
#
#    Failure semantics here are FAIL-LOUD, not silent: by this point `dd`
#    has already written the whole target disk, so a failed injection costs
#    nothing to retry (re-running the installer is harmless — it just
#    overwrites the same disk again), but a SILENT skip would ship a
#    machine with no way to log in, which is strictly worse than an
#    installer that stops and says so.
# ---------------------------------------------------------------------------
if [ -n "${DUDUCLAW_INSTALL_OOBE_STATE_FILE:-}" ] || [ -n "${DUDUCLAW_INSTALL_PENDING_ACCOUNT_FILE:-}" ]; then
    log "寫入初始設定至目標系統..."

    # /data is partition 4 of the wks layout regardless of disk naming
    # scheme — but the PARTITION NODE name differs: a plain "vda"/"sda"
    # style disk suffixes the partition number directly ("vda4"), while an
    # "nvme0n1"/"mmcblk0" style disk (whose own name already ends in a
    # digit) needs a "p" separator ("nvme0n1p4") so the partition number
    # can't be misread as part of the disk name.
    case "$TARGET_DEV" in
        *[0-9]) DATA_PART="${TARGET_DEV}p4" ;;
        *) DATA_PART="${TARGET_DEV}4" ;;
    esac

    # The partition node may take a moment to appear after `partprobe`
    # above — poll rather than assume it is already there. Busybox `sleep`
    # only accepts whole seconds (no `sleep 0.5`), so this is a coarse
    # ~10-try/~10s ceiling, not a tight poll.
    tries=0
    while [ ! -b "$DATA_PART" ]; do
        tries=$((tries + 1))
        if [ "$tries" -ge 10 ]; then
            fail "等待 ${DATA_PART} 裝置節點出現逾時（partprobe 後應立即可見；安裝映像已完整寫入，可重試安裝以再次注入初始設定）"
        fi
        sleep 1
    done

    MNT="$(mktemp -d)"
    mount "$DATA_PART" "$MNT" || fail "掛載 ${DATA_PART} 失敗，無法寫入初始設定（安裝映像已完整寫入，可重試安裝）"

    # From here on, every failure must unmount before exiting — this
    # script sets no EXIT trap (matching its own pre-existing style
    # elsewhere), so each step below checks its own result explicitly
    # through this helper rather than relying on a bare `set -e` exit that
    # would leave $MNT mounted.
    inject_fail() {
        err "$1"
        umount "$MNT" 2>/dev/null || true
        rmdir "$MNT" 2>/dev/null || true
        exit 1
    }

    if [ -n "${DUDUCLAW_INSTALL_OOBE_STATE_FILE:-}" ]; then
        mkdir -p "$MNT/duduclaw-kiosk/shell" || inject_fail "建立 ${MNT}/duduclaw-kiosk/shell 失敗"
        cp "$DUDUCLAW_INSTALL_OOBE_STATE_FILE" "$MNT/duduclaw-kiosk/shell/oobe_state.json" || inject_fail "寫入 oobe_state.json 失敗"
    fi

    if [ -n "${DUDUCLAW_INSTALL_PENDING_ACCOUNT_FILE:-}" ]; then
        mkdir -p "$MNT/duduclaw" || inject_fail "建立 ${MNT}/duduclaw 失敗"
        cp "$DUDUCLAW_INSTALL_PENDING_ACCOUNT_FILE" "$MNT/duduclaw/pending-account.json" || inject_fail "寫入 pending-account.json 失敗"
        chmod 600 "$MNT/duduclaw/pending-account.json" || inject_fail "設定 pending-account.json 權限失敗"
    fi

    sync
    umount "$MNT" || inject_fail "卸載 ${MNT} 失敗"
    rmdir "$MNT" 2>/dev/null || true

    ok "初始設定已寫入目標系統。"
fi

ok "安裝完成。"
ok "請移除安裝媒介（光碟／USB）後重新開機，系統將從 ${TARGET_DEV} 啟動。"
# The first-boot description depends on whether §7 injected settings: with an
# injected oobe_state.json the target boots straight to the desktop (no OOBE),
# so promising "初始設定（OOBE）" there would be wrong.
if [ -n "${DUDUCLAW_INSTALL_OOBE_STATE_FILE:-}" ]; then
    log "首次開機會自動擴充 /data 至整顆磁碟，並套用安裝時完成的初始設定，直接進入桌面。"
else
    log "首次開機會自動擴充 /data 至整顆磁碟並執行初始設定（OOBE）。"
fi

# In the automated/QEMU path, power off so the harness can detect completion
# and reboot from the target disk deterministically.
if [ "${DUDUCLAW_INSTALL_POWEROFF:-0}" = "1" ]; then
    log "DUDUCLAW_INSTALL_POWEROFF=1 — 安裝完成，關機。"
    sync
    poweroff -f
fi
