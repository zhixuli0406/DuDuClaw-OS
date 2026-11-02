#!/usr/bin/env python3
"""DHCPv6 reply regression: pure policy checks and isolated Linux packet tests."""
import argparse
import ctypes
import hashlib
import json
import multiprocessing
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
CONFIGS = (
    ROOT / 'meta-duduclaw/recipes-duduclaw/duduclaw-firewall/files/nftables.conf',
    ROOT / 'appliance/mkosi.extra/etc/nftables.conf',
)
RULE = 'ip6 saddr fe80::/10 ip6 daddr fe80::/10 udp sport 547 udp dport 546 accept'
COMMENT = ' comment "DHCPv6 client replies (link-local)"'
RULE_LINE = '\t\t' + RULE + COMMENT + '\n'
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C'}


def require(value, message):
    if not value:
        raise RuntimeError(message)


def private_namespace():
    require(sys.platform.startswith('linux') and os.geteuid() == 0, 'Linux root required')
    for kind in ('net', 'mnt'):
        require(os.readlink('/proc/self/ns/' + kind) != os.readlink('/proc/1/ns/' + kind),
                'Run under unshare --mount --net --fork; host namespace refused')


def run(argv, **kwargs):
    private_namespace()
    return subprocess.run(argv, env=ENV, check=True, capture_output=True, timeout=5, **kwargs)


def configure(interface, address):
    run(['ip', 'link', 'set', interface, 'up'])
    run(['ip', '-6', 'address', 'add', address + '/64', 'dev', interface, 'nodad'])
    run(['ip', '-6', 'route', 'add', 'ff02::/16', 'dev', interface])


def server(control):
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        require(libc.unshare(0x40000000) == 0, 'server private network namespace failed')
        private_namespace()
        control.send('namespace-ready')
        require(control.recv() == 'configure', 'server setup protocol')
        configure('server0', 'fe80::2')
        run(['ip', '-6', 'address', 'add', 'fe80::3/64', 'dev', 'server0', 'nodad'])
        run(['ip', '-6', 'address', 'add', '2001:db8:26::2/64', 'dev', 'server0', 'nodad'])
        index = socket.if_nametoindex('server0')
        with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'server0\0')
            listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_JOIN_GROUP,
                                socket.inet_pton(socket.AF_INET6, 'ff02::1:2') + struct.pack('@I', index))
            listener.bind(('::', 547))
            listener.settimeout(2)
            control.send('ready')
            while True:
                job = control.recv()
                if job == 'quit':
                    break
                packet, peer = listener.recvfrom(256)
                require(packet == b'\x01' + bytes.fromhex(job['transaction']), 'actual multicast Solicit missing')
                source, port = job['source'], job['source_port']
                if source.startswith('fe80::') and port == 547:
                    pktinfo = socket.inet_pton(socket.AF_INET6, source) + struct.pack('@I', index)
                    listener.sendmsg([b'\x07' + packet[1:]], [(socket.IPPROTO_IPV6, socket.IPV6_PKTINFO, pktinfo)],
                                     0, (job['destination'], job['destination_port'], 0, index))
                else:
                    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as reply:
                        reply.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                        reply.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'server0\0')
                        reply.bind((source, port, 0, index))
                        reply.sendto(b'\x07' + packet[1:], (job['destination'], job['destination_port'], 0, index))
                control.send({'solicit_received': True, 'client_source_port': peer[1], 'reply_sent': True})
        control.send('closed')
    except BaseException as error:
        try:
            control.send({'server_error_class': type(error).__name__})
        except BaseException:
            pass
        raise
    finally:
        control.close()


def new_reply_count():
    table = json.loads(run(['nft', '-j', 'list', 'table', 'inet', 'dhcp6_fixture']).stdout)
    return sum(expr['counter']['packets'] for row in table['nftables'] if 'rule' in row
               for expr in row['rule']['expr'] if 'counter' in expr)


def exchange(control, client, transaction, source='fe80::2', source_port=547,
             destination='fe80::1', destination_port=546):
    job = dict(transaction=transaction, source=source, source_port=source_port,
               destination=destination, destination_port=destination_port)
    control.send(job)
    index = socket.if_nametoindex('client0')
    before = new_reply_count()
    client.sendto(b'\x01' + bytes.fromhex(transaction), ('ff02::1:2', 547, 0, index))
    require(control.poll(3), 'server did not observe multicast request')
    server_result = control.recv()
    require(server_result == {'solicit_received': True, 'client_source_port': 546, 'reply_sent': True},
            'server did not send actual reply')
    try:
        packet, peer = client.recvfrom(256)
        received = packet == b'\x07' + bytes.fromhex(transaction) and peer[1] == source_port
    except socket.timeout:
        received = False
    count = new_reply_count() - before
    return {'received': received, 'reply_ct_new_packets': count, **server_result}


def integration(configs):
    private_namespace()  # Must precede every link/firewall/route mutation.
    run(['mount', '--make-rprivate', '/'])
    run(['ip', 'link', 'add', 'client0', 'type', 'veth', 'peer', 'name', 'server0'])
    parent, child = multiprocessing.Pipe()
    process = multiprocessing.get_context('fork').Process(target=server, args=(child,))
    process.start()
    child.close()
    results = []
    try:
        require(parent.poll(3) and parent.recv() == 'namespace-ready', 'server namespace not ready')
        run(['ip', 'link', 'set', 'server0', 'netns', str(process.pid)])
        configure('client0', 'fe80::1')
        run(['ip', '-6', 'address', 'add', '2001:db8:26::1/64', 'dev', 'client0', 'nodad'])
        parent.send('configure')
        require(parent.poll(3) and parent.recv() == 'ready', 'server setup failed')
        with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as client, tempfile.TemporaryDirectory(prefix='duduclaw-dhcp6-') as directory:
            client.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'client0\0')
            client.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_IF, socket.if_nametoindex('client0'))
            client.bind(('fe80::1', 546, 0, socket.if_nametoindex('client0')))
            client.settimeout(.4)
            counter = 0
            for config_number, (name, candidate) in enumerate(configs):
                normal_source = 'fe80::' + str(config_number + 2)
                require(candidate.count(RULE_LINE) == 1, 'candidate rule missing or duplicated')
                original = candidate.replace(RULE_LINE, '', 1)
                for phase, text in (('original', original), ('fixed', candidate)):
                    file = Path(directory) / 'rules.nft'
                    file.write_text(text)
                    run(['nft', '-f', str(file)])  # flush ruleset is confined to this anonymous namespace.
                    run(['nft', 'add', 'table', 'inet', 'dhcp6_fixture'])
                    run(['nft', 'add', 'chain', 'inet', 'dhcp6_fixture', 'observe',
                         '{ type filter hook input priority -5; policy accept; }'])
                    run(['nft', 'add', 'rule', 'inet', 'dhcp6_fixture', 'observe',
                         'meta', 'nfproto', 'ipv6', 'udp', 'dport', '546', 'ct', 'state', 'new', 'counter'])
                    counter += 1
                    good = exchange(parent, client, f'{counter:06x}', normal_source)
                    require(good['reply_ct_new_packets'] >= 1, 'reply was not observed as ct NEW')
                    require(good['received'] is (phase == 'fixed'), 'unexpected DHCPv6 policy verdict')
                    row = {'config': name, 'phase': phase, 'normal_link_local_reply': good}
                    if phase == 'fixed':
                        negatives = []
                        for source, port in ((normal_source, 548), ('2001:db8:26::2', 547)):
                            counter += 1
                            result = exchange(parent, client, f'{counter:06x}', source, port)
                            require(not result['received'] and result['reply_ct_new_packets'] >= 1,
                                    'unrelated UDP input accepted')
                            negatives.append({'source_scope': 'link_local' if source.startswith('fe80') else 'documentation_global',
                                              'source_port': port, **result})
                        row['negative_packets'] = negatives
                    results.append(row)
        parent.send('quit')
        require(parent.poll(3) and parent.recv() == 'closed', 'server did not close cleanly')
    finally:
        process.join(timeout=2)
        if process.is_alive():
            process.terminate()
            process.join(timeout=2)
        if process.is_alive():
            process.kill(); process.join(timeout=2)
        parent.close()
        require(not process.is_alive() and process.exitcode == 0, 'owned server cleanup failed')
    return {'status': 'ISOLATED_KERNEL_DHCP6_REGRESSION_PASS', 'results': results,
            'boundary': 'Actual multicast UDP Solicit/unicast Reply and nft ct NEW, not DHCP lease assignment or GCP image acceptance.',
            'cleanup': {'owned_server_reaped': True, 'anonymous_namespaces_exit_with_process': True,
                        'host_network_namespace_never_entered': True}}


class PolicyTests(unittest.TestCase):
    def test_both_images_have_exact_narrow_rule(self):
        for path in CONFIGS:
            with self.subTest(path=path):
                text = path.read_text()
                self.assertEqual(text.count(RULE_LINE), 1)
                self.assertLess(text.index('ct state invalid drop'), text.index(RULE))
                self.assertIn('type filter hook input priority filter; policy drop;', text)

    def test_no_catch_all_dhcp6_port_rule(self):
        for path in CONFIGS:
            rules = [line.strip() for line in path.read_text().splitlines() if 'udp dport 546' in line]
            self.assertEqual(rules, [(RULE + COMMENT)])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--integration', action='store_true')
    args, remaining = parser.parse_known_args()
    if args.integration:
        require(not remaining, 'unexpected integration arguments')
        signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError('fixture deadline')))
        signal.alarm(45)
        print(json.dumps(integration([(str(p.relative_to(ROOT)), p.read_text()) for p in CONFIGS]), indent=2))
    else:
        unittest.main(argv=[sys.argv[0], *remaining])
