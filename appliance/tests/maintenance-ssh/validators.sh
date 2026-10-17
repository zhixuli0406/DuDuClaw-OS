#!/bin/sh
# Pure validators shared by the guest baseline and the host regression tests.

maint_has_token() {
    printf '%s\n' "$1" | awk -v want="$2" '{ for (i=1;i<=NF;i++) if ($i==want) found=1 } END { exit !found }'
}

maint_same_tokens() {
    maint_left=$(printf '%s\n' "$1" | tr ' ' '\n' | awk 'NF' | sort)
    maint_right=$(printf '%s\n' "$2" | tr ' ' '\n' | awk 'NF' | sort)
    [ "$maint_left" = "$maint_right" ]
}

# systemctl show's single command record. The argv must be exact; reject a
# second command record even if the first one matches.
maint_exec_exact() {
    [ "$(printf '%s' "$1" | tr -cd '{' | wc -c | tr -d ' ')" = 1 ] || return 1
    [ "$(printf '%s' "$1" | tr -cd '}' | wc -c | tr -d ' ')" = 1 ] || return 1
    case "$1" in
        "{ path=$2 ; argv[]=$3 ; "*" }") return 0 ;;
        *) return 1 ;;
    esac
}

# Strip only nft's dynamic counters and operator comments. Rules are kept in
# order. Headers / braces are not rules; unknown statements remain visible
# and therefore cannot accidentally equal an expected rule.
maint_nft_rules() {
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
        sed 's/ counter packets [0-9][0-9]* bytes [0-9][0-9]*//; s/ comment ".*"$//' |
        awk 'NF && $0 !~ /^table / && $0 !~ /^chain / && $0 !~ /^type / && $0 != "}" && $0 !~ /^#/ {print}'
}

maint_nft_output_ok() {
    maint_rules=$(printf '%s\n' "$1" | maint_nft_rules)
    [ "$(printf '%s\n' "$maint_rules" | sed -n '1p')" = 'oif "lo" jump duduclaw_maint_egress' ] &&
        printf '%s\n' "$1" | grep -Eq 'type filter hook output priority (filter|0); policy accept;'
}

maint_nft_egress_ok() {
    if printf '%s\n' "$1" | grep -Eq '^[[:space:]]*type '; then return 1; fi
    maint_rules=$(printf '%s\n' "$1" | maint_nft_rules)
    [ "$maint_rules" = 'meta skuid 4800 reject' ]
}

# Compare the complete numeric source-set membership, including rejecting
# extra elements. Missing/unrecognised elements= output never becomes empty
# success. nft -nn avoids resolving ids / addresses to names.
maint_nft_sources_ok() {
    maint_elements=$(printf '%s\n' "$1" | awk '
        /elements = \{/ { inside=1; sub(/^.*elements = \{/, "") }
        inside { if (index($0,"}")) { sub(/}.*/, ""); print; exit } print }
    ' | tr ',' '\n' | awk '{$1=$1; if (length($0)) print}' | sort)
    maint_expected=$(printf '%s\n' "$2" | tr ' ' '\n' | awk 'NF' | sort)
    [ -n "$maint_elements" ] && [ "$maint_elements" = "$maint_expected" ]
}

maint_nft_empty_ports_ok() {
    printf '%s\n' "$1" | grep -Eq '^[[:space:]]*type inet_service;?[[:space:]]*$' || return 1
    # nft omits elements= for an empty set. An explicit empty set is also
    # safe; reject every nonempty or unfamiliar elements declaration.
    maint_element_lines=$(printf '%s\n' "$1" | grep 'elements' || :)
    [ -z "$maint_element_lines" ] ||
        printf '%s\n' "$maint_element_lines" | grep -Eq '^[[:space:]]*elements = \{[[:space:]]*\};?[[:space:]]*$'
}

maint_nft_input_ok() {
    maint_rules=$(printf '%s\n' "$1" | maint_nft_rules)
    # nft orders ICMP set members by their numeric protocol value, which can
    # differ from the source recipe. Compare complete memberships first.
    maint_icmp=$(printf '%s\n' "$maint_rules" | sed -n 's/^icmp type { \(.*\) } accept$/\1/p' | tr ',' ' ')
    maint_icmp6=$(printf '%s\n' "$maint_rules" | sed -n 's/^icmpv6 type { \(.*\) } accept$/\1/p' | tr ',' ' ')
    maint_same_tokens "$maint_icmp" 'echo-request destination-unreachable time-exceeded' || return 1
    maint_same_tokens "$maint_icmp6" 'echo-request nd-neighbor-solicit nd-neighbor-advert nd-router-advert destination-unreachable time-exceeded packet-too-big' || return 1
    maint_rules=$(printf '%s\n' "$maint_rules" | sed 's/^icmp type { .* } accept$/icmp checked-set accept/; s/^icmpv6 type { .* } accept$/icmpv6 checked-set accept/')
    # Match the whole shipped input chain, not three rules hidden behind an
    # earlier accept/jump. A legitimate firewall change requires re-review.
    maint_expected='iif "lo" accept
ct state established,related accept
ct state invalid drop
icmp checked-set accept
icmpv6 checked-set accept
udp dport 5353 accept
tcp dport 18789 accept
ip saddr @maintenance_src4 tcp dport @maintenance_tcp_ports accept
ip6 saddr @maintenance_src6 tcp dport @maintenance_tcp_ports accept
tcp dport @maintenance_tcp_ports reject with tcp reset'
    [ "$maint_rules" = "$maint_expected" ] &&
        printf '%s\n' "$1" | grep -Eq 'type filter hook input priority (filter|0); policy drop;'
}

maint_kernel_bpf_ok() {
    printf '%s\n' "$1" | grep -qx 'CONFIG_CGROUP_BPF=y'
}
