#!/usr/bin/env bash
#
# sb-keygen.sh — UEFI Secure Boot self-signed key production line for
# DuDuClaw OS (trust-chain P1, wave SB-1).
#
# Produces a full self-signed PK/KEK/db chain (design doc T1=A, "自簽全鏈"
# — see commercial/docs/DESIGN-os-trust-chain-2026-09.md §2.1/§2.5, and
# T3=A, "build host 檔案" key custody). Runs on the BUILD HOST (macOS or
# Linux dev box), never inside a target device image. Depends on openssl
# for all key/cert generation (portable, always present); ESL and .auth
# generation each need one additional tool detected at runtime — see the
# "tool selection" section below for exactly which, and what happens when
# it is missing.
#
# WHAT THIS PRODUCES (fixed layout, do not rename — see "key layout
# contract" below):
#   PK.key   PK.crt    -- Platform Key (root of trust; self-signed)
#   KEK.key  KEK.crt    -- Key Exchange Key (self-signed by KEK, chained
#                           to PK via PK.auth/KEK.auth below)
#   db.key   db.crt     -- primary signature-database key, used to sign
#                           every UKI at build time (ukify
#                           --secureboot-private-key/--secureboot-certificate,
#                           see meta-duduclaw/classes/duduclaw-rescue-boot.bbclass
#                           and oe-core's uki.bbclass, both read
#                           UKI_SB_KEY/UKI_SB_CERT)
#   db-backup.crt        -- SECOND, independently generated cert enrolled
#                           into the same db (risk-table mitigation in the
#                           design doc §6 "金鑰遺失＝磚": db needs at least
#                           two independent certs so a lost/compromised
#                           primary db key does not brick every shipped
#                           device). Its PRIVATE KEY
#                           (offline-backup/db-backup.key) is generated
#                           locally once, then this script's summary tells
#                           you to move it off this machine immediately —
#                           it is never meant to stay here long-term.
#   GUID.txt              -- owner GUID for all signature-list entries
#                           (generated once, reused on every re-run)
#   PK.esl KEK.esl db.esl -- EFI Signature List form of each cert (db.esl
#                           carries BOTH db.crt and db-backup.crt)
#   PK.auth KEK.auth db.auth
#                         -- signed EFI_VARIABLE_AUTHENTICATION_2 blobs.
#                           systemd-boot's `secure-boot-enroll` loader.conf
#                           setting reads exactly these three files from
#                           /loader/keys/<NAME>/{PK,KEK,db}.auth (see
#                           loader.conf(5) — one-hand-verified against the
#                           design doc's own citation). PK.auth is
#                           self-signed by PK; KEK.auth is signed by PK;
#                           db.auth is signed by KEK — that chain is what
#                           makes an unattended `secure-boot-enroll=force`
#                           factory-boot install all three atomically.
#
# TOOL SELECTION (queried against the real tools, not guessed):
#   - Key/cert generation: openssl only. No fallback needed, no fallback
#     exists — if openssl is missing this script cannot do anything.
#   - ESL generation: prefers `cert-to-efi-sig-list` (efitools) if present
#     in PATH; otherwise `virt-fw-sigdb` (pip package `virt-firmware`,
#     verified 2026-09 against virt-firmware 26.8.1's actual --help output
#     — its real flags are `--add-cert GUID FILE` [repeatable] and
#     `-o FILE`, not guessed). Neither present => hard error with install
#     instructions; ESL is NOT optional output, one of these two tools is
#     required.
#   - .auth generation: requires `sign-efi-sig-list` (efitools). IMPORTANT
#     finding from verifying virt-firmware's source
#     (virt/firmware/varstore/authfiles.py) on 2026-09: virt-fw-vars
#     `--output-auth` writes a DUMMY EFI_VARIABLE_AUTHENTICATION_2 header
#     with NO real PKCS#7 signature — it exists to pre-seed QEMU/OVMF_VARS
#     files directly (bypassing runtime signature verification entirely),
#     not to produce files a real UEFI firmware's SetVariable() call would
#     accept. virt-firmware ships no genuine authenticated-variable
#     signer anywhere in its source. So: if `sign-efi-sig-list` is not in
#     PATH, this script prints a clear error + install guidance and SKIPS
#     just the .auth step — key and ESL generation still complete and are
#     valid, standalone deliverables. This is the expected degrade path on
#     macOS (efitools has no Homebrew formula as of this writing); it is
#     designed-for, not a bug.
#
# KEY LAYOUT CONTRACT (do not rename these files — a second agent's kas
# overlay at meta-duduclaw/kas/sb-signing.yml depends on this exact set of
# names existing under the output directory):
#   ~/.duduclaw-sb/{PK,KEK,db}.{key,crt} db-backup.crt GUID.txt
#   ~/.duduclaw-sb/{PK,KEK,db}.esl {PK,KEK,db}.auth
#   ~/.duduclaw-sb/offline-backup/db-backup.key
#
# HANDOFF TO THE KAS OVERLAY: meta-duduclaw/kas/sb-signing.yml (built by a
# different wave of this same effort) reads its UKI signing key/cert from
# `/workspace/sb-keys/db.key` and `/workspace/sb-keys/db.crt` INSIDE the
# builder container — `/workspace` is the container's mount of the repo
# root, so that maps to `<repo>/sb-keys/db.key` / `<repo>/sb-keys/db.crt`
# on the host. The overlay ALSO points DUDUCLAW_SB_ENROLL_KEYDIR at that
# same directory, from which duduclaw-secure-boot.bbclass stages
# PK.auth/KEK.auth/db.auth onto the ESP (/loader/keys/auto/) for the
# factory auto-enroll flow. This script does NOT copy files there
# automatically (it never touches the repo tree) — copy db.key, db.crt AND
# the three .auth files into `<repo>/sb-keys/` yourself once you are ready
# to build a signed image; the summary this script prints at the end
# repeats this as the first "next step". The PK/KEK PRIVATE keys are not
# needed by any build step (UEFI validates loaded images against db; PK/KEK
# only act through the pre-signed .auth payloads) so they never need to
# leave ~/.duduclaw-sb/.
#
# KEY CUSTODY (design doc T3=A): private keys live as plain files on this
# build host, 0600, in a 0700 directory — same discipline this project
# already uses for its minisign release keys (~/.minisign/, see
# commercial/docs/DESIGN-os-trust-chain-2026-09.md §2.5 and
# reference_license_v2_signing_key notes). PK.key/KEK.key are MORE
# sensitive than db.key: losing PK.key means the device's trust chain can
# NEVER be changed again (not even to add a new db signer); losing db.key
# "only" means no new UKIs can be signed while already-enrolled db entries
# still boot. Back all three up to a separate location you control; never
# commit any of them to git (see the .gitignore entry this change also
# adds for sb-keys/).
#
# USAGE:
#   ./sb-keygen.sh [--out DIR] [--force] [-h|--help]
#     --out DIR   output directory (default: ~/.duduclaw-sb)
#     --force     regenerate keys/ESL/auth that already exist. DANGEROUS:
#                 any device already enrolled with the OLD PK/KEK/db will
#                 PERMANENTLY lose trust in its own boot chain unless it
#                 is physically re-enrolled with the new keys. GUID.txt is
#                 NEVER regenerated by --force (an owner GUID is not a
#                 secret and changing it on a rotation serves no purpose).
#   Idempotent by default: every artifact this script can produce is
#   skipped (not overwritten) if it already exists, so re-running after a
#   partial failure (e.g. .auth skipped because efitools was missing) only
#   fills in what is still missing.

set -euo pipefail

SCRIPT_NAME="sb-keygen"
DEFAULT_OUT="${HOME}/.duduclaw-sb"
VALIDITY_DAYS=7300 # 20 years, per design doc §2 (PK/KEK/db all self-signed)
KEY_BITS=2048

OUT_DIR="$DEFAULT_OUT"
FORCE=0

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--out DIR] [--force] [-h|--help]

  --out DIR   output directory (default: ${DEFAULT_OUT})
  --force     regenerate keys/ESL/auth files that already exist.
              Any device already enrolled with the old PK/KEK/db
              PERMANENTLY loses trust in its boot chain unless it is
              physically re-enrolled with the new keys. GUID.txt is
              never regenerated, --force or not.
  -h, --help  show this help and exit

See the header comment in this script for the full artifact list, the
tool-selection matrix, and the key-layout contract shared with
meta-duduclaw/kas/sb-signing.yml.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] || die "--out requires an argument"
      OUT_DIR="$2"
      shift 2
      ;;
    --out=*)
      OUT_DIR="${1#--out=}"
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1 (see --help)"
      ;;
  esac
done

if [ "$FORCE" -eq 1 ]; then
  cat >&2 <<'EOF'
######################################################################
[sb-keygen] --force: EXISTING KEYS WILL BE OVERWRITTEN.
[sb-keygen] Any device already enrolled with the CURRENT PK/KEK/db will
[sb-keygen] PERMANENTLY lose trust in its own boot chain unless it is
[sb-keygen] physically re-enrolled with the newly generated keys. There
[sb-keygen] is no remote/automatic recovery path for an already-shipped
[sb-keygen] device -- its firmware simply stops trusting any UKI signed
[sb-keygen] after this point.
######################################################################
EOF
fi

have_cmd openssl || die "openssl not found in PATH -- required, no fallback exists for key/cert generation"

# ---------------------------------------------------------------------
# output layout
# ---------------------------------------------------------------------
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

OFFLINE_DIR="$OUT_DIR/offline-backup"
mkdir -p "$OFFLINE_DIR"
chmod 700 "$OFFLINE_DIR"

PK_KEY="$OUT_DIR/PK.key";   PK_CRT="$OUT_DIR/PK.crt"
KEK_KEY="$OUT_DIR/KEK.key"; KEK_CRT="$OUT_DIR/KEK.crt"
DB_KEY="$OUT_DIR/db.key";   DB_CRT="$OUT_DIR/db.crt"
DB_BACKUP_CRT="$OUT_DIR/db-backup.crt"
DB_BACKUP_KEY="$OFFLINE_DIR/db-backup.key"
GUID_FILE="$OUT_DIR/GUID.txt"
PK_ESL="$OUT_DIR/PK.esl";   KEK_ESL="$OUT_DIR/KEK.esl";   DB_ESL="$OUT_DIR/db.esl"
PK_AUTH="$OUT_DIR/PK.auth"; KEK_AUTH="$OUT_DIR/KEK.auth"; DB_AUTH="$OUT_DIR/db.auth"

log "output directory: $OUT_DIR"

# ---------------------------------------------------------------------
# owner GUID (reused across re-runs regardless of --force)
# ---------------------------------------------------------------------
gen_guid() {
  if have_cmd uuidgen; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif have_cmd python3; then
    python3 -c "import uuid; print(uuid.uuid4())"
  else
    die "neither uuidgen nor python3 found in PATH -- cannot generate the owner GUID"
  fi
}

if [ -s "$GUID_FILE" ]; then
  GUID="$(cat "$GUID_FILE")"
  log "reusing existing owner GUID from GUID.txt: $GUID"
else
  GUID="$(gen_guid)"
  printf '%s\n' "$GUID" > "$GUID_FILE"
  log "generated owner GUID: $GUID"
fi

# ---------------------------------------------------------------------
# key/cert generation (openssl only)
# ---------------------------------------------------------------------
# skip_check: "both" (default) requires key+cert to both exist to treat
# this pair as already-provisioned; "crt_only" requires only the cert --
# used for db-backup, whose private key is EXPECTED to be moved off this
# host after generation (see header). Without this distinction, a re-run
# after the user correctly follows the "move the backup key offline"
# instruction would see the private key missing and silently regenerate a
# brand-new orphan backup cert, invalidating the one already carried
# offline.
gen_keypair() {
  local label="$1" cn="$2" keyfile="$3" crtfile="$4" skip_check="${5:-both}"
  local already=0
  if [ "$skip_check" = "crt_only" ]; then
    [ -f "$crtfile" ] && already=1
  else
    if [ -f "$keyfile" ] && [ -f "$crtfile" ]; then
      already=1
    fi
  fi
  if [ "$already" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
    if [ ! -f "$keyfile" ]; then
      log "$label: cert already exists at $crtfile (private key not present locally -- expected once it has been moved offline) -- skip"
    else
      log "$label: keypair already exists at $(basename "$keyfile") / $(basename "$crtfile") -- skip (use --force to regenerate)"
    fi
    return 0
  fi
  log "$label: generating RSA-${KEY_BITS} self-signed cert (CN=\"${cn}\", ${VALIDITY_DAYS}d validity)"
  local tmp_key="${keyfile}.tmp.$$" tmp_crt="${crtfile}.tmp.$$"
  rm -f "$tmp_key" "$tmp_crt"
  if ! (umask 077 && openssl req -x509 -sha256 -newkey "rsa:${KEY_BITS}" -nodes \
        -keyout "$tmp_key" -out "$tmp_crt" \
        -days "$VALIDITY_DAYS" -subj "/CN=${cn}/") ; then
    rm -f "$tmp_key" "$tmp_crt"
    die "$label: openssl req failed -- see output above"
  fi
  mv -f "$tmp_key" "$keyfile"
  mv -f "$tmp_crt" "$crtfile"
  chmod 600 "$keyfile"
  chmod 644 "$crtfile"
  log "$label: wrote $(basename "$keyfile") (0600) and $(basename "$crtfile")"
}

gen_keypair "PK"        "DuDuClaw OS Platform Key"                    "$PK_KEY"        "$PK_CRT"
gen_keypair "KEK"       "DuDuClaw OS Key Exchange Key"                "$KEK_KEY"       "$KEK_CRT"
gen_keypair "db"        "DuDuClaw OS Signature Database"              "$DB_KEY"        "$DB_CRT"
gen_keypair "db-backup" "DuDuClaw OS Signature Database (Backup)"     "$DB_BACKUP_KEY" "$DB_BACKUP_CRT" "crt_only"

# ---------------------------------------------------------------------
# key<->cert self-verification (catches a corrupt/mismatched pair before
# it ever reaches ESL/auth generation, instead of failing mysteriously
# later or -- worse -- silently shipping a broken chain)
# ---------------------------------------------------------------------
verify_keypair() {
  local label="$1" keyfile="$2" crtfile="$3"
  if [ ! -f "$keyfile" ] || [ ! -f "$crtfile" ]; then
    warn "$label: verify skipped (key and/or cert not present locally)"
    return 0
  fi
  local key_mod crt_mod
  key_mod="$(openssl rsa -in "$keyfile" -noout -modulus 2>/dev/null)" || die "$label: openssl could not read modulus from $keyfile"
  crt_mod="$(openssl x509 -in "$crtfile" -noout -modulus 2>/dev/null)" || die "$label: openssl could not read modulus from $crtfile"
  [ "$key_mod" = "$crt_mod" ] || die "$label: private key does NOT match certificate (modulus mismatch) -- $keyfile / $crtfile"
  openssl verify -CAfile "$crtfile" "$crtfile" >/dev/null 2>&1 || die "$label: openssl verify failed on self-signed $crtfile"
  log "$label: verified (key<->cert match, self-signature OK)"
}

verify_keypair "PK"        "$PK_KEY"        "$PK_CRT"
verify_keypair "KEK"       "$KEK_KEY"       "$KEK_CRT"
verify_keypair "db"        "$DB_KEY"        "$DB_CRT"
verify_keypair "db-backup" "$DB_BACKUP_KEY" "$DB_BACKUP_CRT"

# ---------------------------------------------------------------------
# ESL generation
# ---------------------------------------------------------------------
ESL_BACKEND=""
if have_cmd cert-to-efi-sig-list; then
  ESL_BACKEND="efitools"
elif have_cmd virt-fw-sigdb; then
  ESL_BACKEND="virt-firmware"
else
  die "no ESL generation tool found in PATH. Install ONE of:
  - efitools (provides cert-to-efi-sig-list) -- e.g. 'apt install efitools' / 'dnf install efitools' / 'pacman -S efitools'
  - virt-firmware (provides virt-fw-sigdb)    -- 'pip3 install virt-firmware' (pure Python, works on macOS and Linux; on
    Apple Silicon Macs use an arm64-native python3, e.g. the system /usr/bin/python3 -- a Homebrew Intel/x86_64 python3
    running under Rosetta can fail to build the 'cryptography' dependency's wheel from source)"
fi
log "ESL backend: $ESL_BACKEND"

gen_esl_single() {
  local label="$1" crtfile="$2" eslfile="$3"
  if [ -f "$eslfile" ] && [ "$FORCE" -ne 1 ]; then
    log "$label: ESL already exists at $(basename "$eslfile") -- skip"
    return 0
  fi
  log "$label: generating ESL from $(basename "$crtfile")"
  local tmp="${eslfile}.tmp.$$"
  case "$ESL_BACKEND" in
    efitools)
      cert-to-efi-sig-list -g "$GUID" "$crtfile" "$tmp" || { rm -f "$tmp"; die "$label: cert-to-efi-sig-list failed"; }
      ;;
    virt-firmware)
      virt-fw-sigdb --add-cert "$GUID" "$crtfile" -o "$tmp" || { rm -f "$tmp"; die "$label: virt-fw-sigdb failed"; }
      ;;
  esac
  mv -f "$tmp" "$eslfile"
  log "$label: wrote $(basename "$eslfile")"
}

gen_esl_db() {
  local eslfile="$1" crt_main="$2" crt_backup="$3"
  if [ -f "$eslfile" ] && [ "$FORCE" -ne 1 ]; then
    log "db: ESL already exists at $(basename "$eslfile") -- skip"
    return 0
  fi
  log "db: generating combined ESL (primary + backup cert) from $(basename "$crt_main") + $(basename "$crt_backup")"
  local tmp="${eslfile}.tmp.$$"
  case "$ESL_BACKEND" in
    efitools)
      # cert-to-efi-sig-list emits exactly one EFI_SIGNATURE_LIST per
      # invocation; db needs both certs in one blob. Each
      # EFI_SIGNATURE_LIST is self-length-prefixed, so byte-concatenating
      # two complete lists is the standard way multi-cert db blobs are
      # built -- it is exactly what `sig-list-to-certs` (efitools) undoes
      # when splitting a multi-entry db blob back into per-cert files, not
      # an ad-hoc trick invented here.
      local tmp_main="${eslfile}.main.tmp.$$" tmp_bak="${eslfile}.bak.tmp.$$"
      cert-to-efi-sig-list -g "$GUID" "$crt_main" "$tmp_main" || { rm -f "$tmp_main"; die "db: cert-to-efi-sig-list (primary) failed"; }
      cert-to-efi-sig-list -g "$GUID" "$crt_backup" "$tmp_bak" || { rm -f "$tmp_main" "$tmp_bak"; die "db: cert-to-efi-sig-list (backup) failed"; }
      cat "$tmp_main" "$tmp_bak" > "$tmp"
      rm -f "$tmp_main" "$tmp_bak"
      ;;
    virt-firmware)
      virt-fw-sigdb --add-cert "$GUID" "$crt_main" --add-cert "$GUID" "$crt_backup" -o "$tmp" \
        || { rm -f "$tmp"; die "db: virt-fw-sigdb failed"; }
      ;;
  esac
  mv -f "$tmp" "$eslfile"
  log "db: wrote $(basename "$eslfile") (primary + backup cert)"
}

gen_esl_single "PK"  "$PK_CRT"  "$PK_ESL"
gen_esl_single "KEK" "$KEK_CRT" "$KEK_ESL"
gen_esl_db "$DB_ESL" "$DB_CRT" "$DB_BACKUP_CRT"

# ---------------------------------------------------------------------
# .auth generation (needs efitools' sign-efi-sig-list; graceful degrade
# on macOS is the expected path, see header comment)
# ---------------------------------------------------------------------
AUTH_OK=0
AUTH_SKIP_REASON=""

if have_cmd sign-efi-sig-list; then
  gen_auth() {
    local label="$1" varname="$2" signer_crt="$3" signer_key="$4" eslfile="$5" authfile="$6"
    if [ -f "$authfile" ] && [ "$FORCE" -ne 1 ]; then
      log "$label: already exists at $(basename "$authfile") -- skip"
      return 0
    fi
    log "$label: signing $(basename "$eslfile") -> $(basename "$authfile") (signer: $(basename "$signer_crt"))"
    local tmp="${authfile}.tmp.$$"
    # No -a (APPEND_WRITE) flag: -a is for incrementally appending to an
    # ALREADY-enrolled variable later, not for this initial full
    # PK/KEK/db provisioning.
    sign-efi-sig-list -c "$signer_crt" -k "$signer_key" "$varname" "$eslfile" "$tmp" \
      || { rm -f "$tmp"; die "$label: sign-efi-sig-list failed"; }
    mv -f "$tmp" "$authfile"
    log "$label: wrote $(basename "$authfile")"
  }

  gen_auth "PK.auth (self-signed)" "PK"  "$PK_CRT"  "$PK_KEY"  "$PK_ESL"  "$PK_AUTH"
  gen_auth "KEK.auth (signed by PK)" "KEK" "$PK_CRT"  "$PK_KEY"  "$KEK_ESL" "$KEK_AUTH"
  gen_auth "db.auth (signed by KEK)" "db"  "$KEK_CRT" "$KEK_KEY" "$DB_ESL"  "$DB_AUTH"
  AUTH_OK=1
else
  AUTH_SKIP_REASON="sign-efi-sig-list (efitools) not found in PATH"
  warn "$AUTH_SKIP_REASON -- .auth generation SKIPPED. systemd-boot's secure-boot-enroll needs these three files; the key/ESL files generated above are complete and valid on their own."
  cat >&2 <<EOF
[$SCRIPT_NAME] Install efitools to produce .auth files, then re-run this
[$SCRIPT_NAME] script (it will only fill in the missing .auth files --
[$SCRIPT_NAME] everything else is already done and will be skipped):
[$SCRIPT_NAME]   Debian/Ubuntu: apt install efitools
[$SCRIPT_NAME]   Fedora:        dnf install efitools
[$SCRIPT_NAME]   Arch:          pacman -S efitools
[$SCRIPT_NAME]   macOS:         no Homebrew formula as of this writing.
[$SCRIPT_NAME]                  Simplest path: run this script inside the
[$SCRIPT_NAME]                  Yocto builder container or any Linux box,
[$SCRIPT_NAME]                  where efitools is a normal package.
[$SCRIPT_NAME]                  Building efitools from source on macOS is
[$SCRIPT_NAME]                  possible but not tested by this script --
[$SCRIPT_NAME]                  see https://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git/
EOF
fi

# ---------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------
log ""
log "=== summary ==="
log "output directory: $OUT_DIR"
log "owner GUID:        $GUID"
log "ESL backend used:  $ESL_BACKEND"
log ""
log "files:"
for f in PK.key PK.crt KEK.key KEK.crt db.key db.crt db-backup.crt GUID.txt \
         PK.esl KEK.esl db.esl PK.auth KEK.auth db.auth offline-backup/db-backup.key; do
  if [ -f "$OUT_DIR/$f" ]; then
    size="$(wc -c < "$OUT_DIR/$f" 2>/dev/null | tr -d ' ')"
    log "  $(printf '%-30s' "$f") ${size} bytes"
  else
    log "  $(printf '%-30s' "$f") (not present)"
  fi
done
log ""
if [ "$AUTH_OK" -eq 1 ]; then
  log "STATUS: COMPLETE -- all key/ESL/auth artifacts generated."
else
  warn "STATUS: DEGRADED -- key/ESL artifacts complete, .auth generation skipped ($AUTH_SKIP_REASON). Re-run on a host with efitools to fill in the missing .auth files; nothing else needs to change."
fi
log ""
log "NEXT STEPS:"
log "  1. Copy the UKI signing pair AND the enrollment .auth set into the"
log "     repo for container builds:"
log "       cp \"$DB_KEY\" \"$DB_CRT\" \"$OUT_DIR\"/{PK,KEK,db}.auth <repo>/sb-keys/"
log "     (sb-keys/ is gitignored. meta-duduclaw/kas/sb-signing.yml reads"
log "     db.key/db.crt for UKI signing AND points"
log "     DUDUCLAW_SB_ENROLL_KEYDIR at the same directory, from which"
log "     duduclaw-secure-boot.bbclass stages PK.auth/KEK.auth/db.auth"
log "     onto the ESP at /loader/keys/auto/ for factory auto-enroll --"
log "     without the .auth copies, images build signed but"
log "     secure-boot-enroll stays inert. The PK/KEK PRIVATE keys never"
log "     need to leave $OUT_DIR -- UEFI validates loaded images against"
log "     db; PK/KEK only act through the pre-signed .auth payloads.)"
log "  2. Move the OFFLINE backup private key off this machine NOW:"
log "       $DB_BACKUP_KEY"
log "     Copy it to encrypted offline media, verify the copy, then delete"
log "     it from this build host. This is the ONLY recovery path if"
log "     db.key is ever lost or compromised -- without it, every"
log "     already-enrolled device is permanently stuck on a db that can"
log "     never be given a new signer."
log "  3. Backup discipline for PK.key / KEK.key / db.key -- same rigor as"
log "     this project's minisign release keys (~/.minisign/): keep 0600,"
log "     back up to a location you control, never commit to git. PK.key"
log "     and KEK.key need STRICTER custody than db.key: losing PK.key"
log "     means the trust chain can NEVER be changed again (not even to"
log "     add a new db signer); losing db.key only means no new UKIs can"
log "     be signed, already-enrolled db entries still boot."

exit 0
