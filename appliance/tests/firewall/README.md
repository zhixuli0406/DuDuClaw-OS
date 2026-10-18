# DHCPv6 firewall regression

The current Yocto firewall permits UDP replies from source port 547 to client
port 546 only when both IPv6 addresses are link-local (`fe80::/10`). The frozen
Debian firewall reference carries the same exception; this does not resume
Debian image builds. SSH source restrictions, TCP rejection and UID-based
egress rules are unchanged.

GCE assigns VM IPv6 addresses through DHCPv6 and advertises the default route
separately through router advertisements. Seeing an RA route therefore does
not establish that address assignment succeeded. See [Google's IPv6
configuration documentation](https://docs.cloud.google.com/compute/docs/ip-addresses/configure-ipv6-address).
[systemd-networkd](https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html)
can start DHCPv6 in response to RA flags.

[RFC 9915, sections 5 and 7](https://www.rfc-editor.org/rfc/rfc9915.html)
defines the link-scoped server multicast group `ff02::1:2`, client port 546,
and server/relay port 547. The policy allows the standard-port, link-local
bootstrap exchange; it does not generally open UDP 546 or allow replies from
global server addresses. A multicast request and unicast reply can form
different conntrack tuples, so accepting established/related traffic alone
is insufficient for that exchange.

## Run

From the repository root, the policy checks require only Python's standard
library:

```sh
python3 -B appliance/tests/firewall/test_dhcpv6_reply.py
```

The packet test requires Linux, root, and existing `unshare`, `mount`, `ip`,
`nft` and Python 3 tools. Run in fresh anonymous mount and network namespaces:

```sh
sudo unshare --mount --net --fork python3 -B appliance/tests/firewall/test_dhcpv6_reply.py --integration
```

The test refuses PID 1's mount or network namespace. It creates its own veth
pair and server network namespace, loads each full firewall configuration
only inside the test namespace, then reaps its own server process. No external
network or production guest is needed. The test process has a 45-second
alarm; each command/socket operation is bounded.

## Evidence and limits

The Linux packet regression sends a multicast Solicit header and receives a
unicast Reply header with the same transaction ID. It checks actual server
receipt, `ct state new` counters and client delivery:

- Removing only the new rule reproduces a dropped reply for both policies.
- Each unchanged candidate policy accepts the standard link-local reply.
- Replies from source port 548 or a global IPv6 source remain dropped.

This is a kernel packet-filter regression, not a complete DHCPv6 lease
implementation. Both policies passed these checks on an isolated Linux
fixture. The check does not prove that GCP's actual reply uses these source
addresses, that the firewall is the sole cause of a missing address, or that
a released image has been repaired. Those require a rebuilt image and a
normal GCP boot that obtains an IPv6 address automatically.
