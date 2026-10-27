#!/bin/sh
# Real-guest baseline. No credential input, journal dump, network connection,
# shell command evaluation or Python dependency. Default mode is read-only.
set -u
set -f
LC_ALL=C
export LC_ALL

mode='readonly'
edition=
fresh=no
while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode) [ "$#" -ge 2 ] || exit 2; mode=$2; shift 2 ;;
        --edition) [ "$#" -ge 2 ] || exit 2; edition=$2; shift 2 ;;
        --fresh-guest) fresh=yes; shift ;;
        *) printf 'FAIL\tusage\tunknown argument\n'; exit 2 ;;
    esac
done
case "$edition" in base|desktop) ;; *) printf 'FAIL\tusage\t--edition base|desktop is required\n'; exit 2 ;; esac
case "$mode:$fresh" in readonly:no|readonly:yes|create-host-key:yes) ;; *) printf 'FAIL\tusage\tcreate-host-key requires --fresh-guest\n'; exit 2 ;; esac
[ "$(id -u)" = 0 ] || { printf 'FAIL\tidentity\tserial root required\n'; exit 2; }
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 2
# shellcheck source=validators.sh
. "$here/validators.sh"

failures=0
result() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3"
    [ "$1" != FAIL ] || failures=$((failures + 1))
}
check() {
    check_id=$1; shift
    if "$@" >/dev/null 2>&1; then result PASS "$check_id" verified; else result FAIL "$check_id" 'missing, unreadable or mismatched evidence'; fi
}
prop_equals() {
    prop_value=$(systemctl show "$1" -p "$2" --value 2>/dev/null) || return 1
    [ -n "$prop_value" ] && [ "$prop_value" = "$3" ]
}
prop_token() {
    prop_value=$(systemctl show "$1" -p "$2" --value 2>/dev/null) || return 1
    maint_has_token "$prop_value" "$3"
}
prop_tokens() {
    prop_value=$(systemctl show "$1" -p "$2" --value 2>/dev/null) || return 1
    [ -n "$prop_value" ] && maint_same_tokens "$prop_value" "$3"
}
prop_paths() {
    prop_value=$(systemctl show "$1" -p "$2" --value 2>/dev/null) || return 1
    prop_value=$(printf '%s\n' "$prop_value" | sed 's/-\//\//g')
    [ -n "$prop_value" ] && maint_same_tokens "$prop_value" "$3"
}
trusted_file() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    [ "$(stat -c '%u:%g:%a' "$1" 2>/dev/null)" = "$2" ]
}
trusted_executable() {
    [ -x "$1" ] && trusted_file "$1" "$2"
}
account_ok() {
    awk -F: '$1=="duduclaw-maint" { n++; if ($3==4800 && $4==4800 && $6=="/usr/share/duduclaw-maint" && $7=="/usr/libexec/duduclaw/maint-shell") good++ } $3==4800 { owners++ } $4==4800 { group_owners++ } END { exit !(n==1 && good==1 && owners==1 && group_owners==1) }' /etc/passwd || return 1
    awk -F: '$1=="duduclaw-maint" { n++; if ($3==4800 && $4=="") good++ } $3==4800 { owners++ } END { exit !(n==1 && good==1 && owners==1) }' /etc/group || return 1
    [ "$(id -G duduclaw-maint)" = 4800 ]
}
shadow_ok() {
    awk -F: '$1=="duduclaw-maint" {n++; if ($2=="*") good++} END {exit !(n==1 && good==1)}' /etc/shadow
}
home_ok() {
    [ -d /usr/share/duduclaw-maint ] && [ ! -L /usr/share/duduclaw-maint ] || return 1
    [ "$(stat -c '%u:%g:%a' /usr/share/duduclaw-maint)" = 0:0:555 ] || return 1
    home_entries=$(find /usr/share/duduclaw-maint ! -path /usr/share/duduclaw-maint -print 2>/dev/null) || return 1
    [ -z "$home_entries" ]
}
no_baked_keys() {
    key_entries=$(find / -xdev \( -name authorized_keys -o -name authorized_keys2 \) -print 2>/dev/null) || return 1
    [ -z "$key_entries" ]
}
dropbear_exec_ok() {
    exec_value=$(systemctl show dropbear@probe.service -p ExecStart --value 2>/dev/null) || return 1
    maint_exec_exact "$exec_value" /usr/sbin/dropbear '/usr/sbin/dropbear -i -r /data/system/dropbear/dropbear_ed25519_host_key -w -s -j -k -m -T 3 -I 1800 -G duduclaw-maint -D /run/duduclaw-maint-ssh -c /usr/libexec/duduclaw/maint-shell'
}
helper_exec_ok() {
    exec_value=$(systemctl show duduclaw-maint-helper@probe.service -p ExecStart --value 2>/dev/null) || return 1
    maint_exec_exact "$exec_value" /usr/libexec/duduclaw/maint-helper /usr/libexec/duduclaw/maint-helper
}
ready_ok() {
    trusted_file /usr/lib/duduclaw/maint-ssh.ready 0:0:644 &&
        printf '1\n' | cmp -s - /usr/lib/duduclaw/maint-ssh.ready
}
no_maint_polkit() {
    [ -d /etc/polkit-1/rules.d ] || [ -d /usr/share/polkit-1/rules.d ] || return 0
    for rule_dir in /etc/polkit-1/rules.d /usr/share/polkit-1/rules.d; do
        [ -d "$rule_dir" ] || continue
        grep -rl 'duduclaw-maint' "$rule_dir" >/dev/null 2>&1; rule_rc=$?
        [ "$rule_rc" = 1 ] || return 1
    done
}
host_key_ok() {
    [ -d /data/system/dropbear ] && [ ! -L /data/system/dropbear ] || return 1
    [ "$(stat -c '%u:%g:%a' /data/system/dropbear)" = 0:0:700 ] || return 1
    trusted_file /data/system/dropbear/dropbear_ed25519_host_key 0:0:600 || return 1
    host_public=$(dropbearkey -y -f /data/system/dropbear/dropbear_ed25519_host_key 2>/dev/null) || return 1
    host_fp=$(printf '%s\n' "$host_public" | sed -n 's/^Fingerprint: \(SHA256:[A-Za-z0-9+/]\{43\}\)$/\1/p')
    [ -n "$host_fp" ] || return 1
    printf 'EVIDENCE\thost_key_fingerprint\t%s\n' "$host_fp"
}
kernel_ok() {
    if [ -r /proc/config.gz ]; then
        kernel_config=$(zcat /proc/config.gz 2>/dev/null) || return 1
    elif [ -r "/boot/config-$(uname -r)" ]; then
        kernel_config=$(cat "/boot/config-$(uname -r)") || return 1
    else
        return 1
    fi
    maint_kernel_bpf_ok "$kernel_config"
}
data_mount_ok() {
    awk '$2=="/data" && $3!="tmpfs" && $3!="ramfs" {found=1} END {exit !found}' /proc/mounts
}
sysd_gate_ok() {
    gate_value=$(systemctl show duduclaw-sysd.service -p ExecStart --value 2>/dev/null) || return 1
    # These are argv tokens, not substrings in paths or help text.
    gate_argv=$(printf '%s\n' "$gate_value" | sed -n 's/^.*argv\[\]=\(.*\) ; ignore_errors=.*$/\1/p')
    maint_exec_exact "$gate_value" /usr/bin/duduclaw-sysd "$gate_argv" || return 1
    printf '%s\n' "$gate_argv" | awk '{for(i=1;i<NF;i++){if($i=="--allowed-uid" && $(i+1)=="1000") uid=1; if($i=="--require-main-pid-of" && $(i+1)=="duduclaw-gateway.service") pid=1}} END {exit !(uid && pid)}'
}
nft_ok() {
    nft_dump=$(nft -nn list "$1" inet filter "$2" 2>/dev/null) || return 1
    case "$2" in
        output) maint_nft_output_ok "$nft_dump" ;;
        duduclaw_maint_egress) maint_nft_egress_ok "$nft_dump" ;;
        input) maint_nft_input_ok "$nft_dump" ;;
        maintenance_src4) maint_nft_sources_ok "$nft_dump" '10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10' ;;
        maintenance_src6) maint_nft_sources_ok "$nft_dump" 'fc00::/7 fe80::/10' ;;
        maintenance_tcp_ports) maint_nft_empty_ports_ok "$nft_dump" ;;
        *) return 1 ;;
    esac
}
desktop_ro() {
    root_options=$(awk '$2=="/"{print $4}' /proc/mounts) || return 1
    [ -n "$root_options" ] || return 1
    case ",$root_options," in *,ro,*) return 0 ;; *) return 1 ;; esac
}

printf 'EVIDENCE\tmode\t%s\nEVIDENCE\tedition\t%s\n' "$mode" "$edition"
for tool in awk sed grep tr sort wc stat find systemctl nft dropbearkey zcat cmp; do
    check "tool.$tool" command -v "$tool"
done
check account.ids account_ok
check account.shadow shadow_ok
check account.home home_ok
check account.shells grep -qxF /usr/libexec/duduclaw/maint-shell /etc/shells
check account.no_polkit_grant no_maint_polkit
check image.no_baked_authorized_keys no_baked_keys
check image.ready_marker ready_ok
check image.persistent_data_mount data_mount_ok
[ "$edition" != desktop ] || check image.readonly_root desktop_ro
check binary.maint-shell trusted_executable /usr/libexec/duduclaw/maint-shell 0:0:755
check binary.maint-helper trusted_executable /usr/libexec/duduclaw/maint-helper 0:0:700
check binary.maint-ssh-close trusted_executable /usr/libexec/duduclaw/maint-ssh-close 0:0:700
check dropbear.exec dropbear_exec_ok
for unit in dropbear@probe.service dropbear.socket; do
    check "$unit.loaded" prop_equals "$unit" LoadState loaded
    check "$unit.binds_to_sysd" prop_token "$unit" BindsTo duduclaw-sysd.service
done
for setting in NoNewPrivileges:yes ProtectSystem:strict ProtectProc:invisible ProtectHome:yes PrivateTmp:yes; do
    check "dropbear.${setting%%:*}" prop_equals dropbear@probe.service "${setting%%:*}" "${setting#*:}"
done
check dropbear.ip_deny prop_tokens dropbear@probe.service IPAddressDeny '0.0.0.0/0 ::/0'
check dropbear.data_mount prop_token dropbear@probe.service RequiresMountsFor /data
check dropbear.inaccessible_paths prop_paths dropbear@probe.service InaccessiblePaths '/data/duduclaw /data/duduclaw-kiosk /data/system/iwd /data/system/containers'
check dropbear.max_connections prop_equals dropbear.socket MaxConnections 16
check dropbear.max_per_source prop_equals dropbear.socket MaxConnectionsPerSource 4
check dropbear.initially_closed prop_equals dropbear.socket ActiveState inactive
check helper.exec helper_exec_ok
for setting in User:root NoNewPrivileges:yes ProtectSystem:strict PrivateNetwork:yes RuntimeDirectoryPreserve:yes RuntimeDirectoryMode:0700 RuntimeDirectory:duduclaw-maint-helper StandardInput:socket StandardOutput:socket StandardError:journal RestrictAddressFamilies:AF_UNIX; do
    check "helper.${setting%%:*}" prop_equals duduclaw-maint-helper@probe.service "${setting%%:*}" "${setting#*:}"
done
check helper.ip_deny prop_tokens duduclaw-maint-helper@probe.service IPAddressDeny '0.0.0.0/0 ::/0'
for setting in LoadState:loaded ActiveState:active SocketUser:root SocketGroup:duduclaw-maint SocketMode:0660 Accept:yes MaxConnections:4; do
    check "helper.socket.${setting%%:*}" prop_equals duduclaw-maint-helper.socket "${setting%%:*}" "${setting#*:}"
done
check helper.socket.listen prop_equals duduclaw-maint-helper.socket Listen '/run/duduclaw-maint-helper.sock (Stream)'
check sysd.main_pid_gate sysd_gate_ok
check sysd.active prop_equals duduclaw-sysd.service ActiveState active
check sysd.user prop_equals duduclaw-sysd.service User root
check kernel.cgroup_bpf kernel_ok
for chain in output duduclaw_maint_egress input; do check "nft.$chain" nft_ok chain "$chain"; done
for source_set in maintenance_src4 maintenance_src6 maintenance_tcp_ports; do check "nft.$source_set" nft_ok set "$source_set"; done
if [ "$mode" = create-host-key ]; then check host_key.create systemctl start dropbearkey.service; fi
# Fingerprints are public evidence. Never print the private key or full logs.
if host_key_ok; then result PASS host_key.metadata verified; else result FAIL host_key.metadata 'missing, unreadable or mismatched host key'; fi
printf 'NOT_RUN\thost_key.reboot_persistence\trequires a second real boot and fingerprint comparison\n'
printf 'NOT_RUN\tlifecycle_and_ssh\tbaseline does not test login, expiry, forwarding or runtime BPF enforcement\n'
printf 'SUMMARY\tfailures\t%s\n' "$failures"
[ "$failures" = 0 ]
