#!/usr/bin/env python3
"""Minimal WebSocket JSON-RPC client for the DuDuClaw gateway dashboard API.

Why this exists: the gateway's `network.*` RPC surface lives ONLY on the `/ws`
WebSocket endpoint (the first-run HTTP routes are a separate, deliberately
narrower pre-auth surface with no `wifi_forget`), and the appliance image ships
neither `websocat` nor any Python websocket library. Hand-rolling the ~100 lines
of RFC 6455 that a single request/response round trip needs is cheaper than
adding a dependency to a shipped image just to test it.

Scope is deliberately tiny and matched to this test harness:
  * client-to-server text frames only, always masked (RFC 6455 requires it)
  * server frames up to the 1 MiB the gateway itself caps at
  * ping frames answered with a pong; close frames end the read loop
  * no fragmentation on send (every payload here is a few hundred bytes)

Usage:
    ws_rpc.py --url ws://127.0.0.1:18789/ws --jwt <token> [--read-timeout S] <method> [json-params]

Prints the response frame's JSON payload to stdout and exits 0 when the frame
reports ok; prints the error object and exits 1 otherwise. Any transport or
protocol failure exits 2 — deliberately a DIFFERENT code from "the RPC said no",
so a test script can tell "the feature refused" from "the harness broke".
"""

import argparse
import base64
import json
import os
import socket
import struct
import sys
import urllib.parse

READ_TIMEOUT_SECS = 30.0
MAX_FRAME_BYTES = 1024 * 1024


class ProtocolError(Exception):
    """Anything that means the transport misbehaved, not that the RPC failed."""


def _recv_exactly(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ProtocolError(f"connection closed after {len(buf)} of {n} bytes")
        buf += chunk
    return buf


def _handshake(sock, host, port, path):
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(request.encode("ascii"))

    # Read just the response headers, byte at a time. Slow, but a handshake is
    # a few hundred bytes and reading greedily risks swallowing the first data
    # frame into a buffer this function would then have to hand back.
    raw = b""
    while b"\r\n\r\n" not in raw:
        byte = sock.recv(1)
        if not byte:
            raise ProtocolError("connection closed during handshake")
        raw += byte
        if len(raw) > 8192:
            raise ProtocolError("handshake response exceeded 8 KiB")

    status_line = raw.split(b"\r\n", 1)[0].decode("latin-1")
    if " 101 " not in status_line:
        raise ProtocolError(f"upgrade refused: {status_line}")


def _send_text(sock, text):
    payload = text.encode("utf-8")
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))

    header = bytearray([0x81])  # FIN + opcode 1 (text)
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header += struct.pack(">H", length)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", length)
    sock.sendall(bytes(header) + mask + masked)


def _recv_frame(sock):
    """Returns (opcode, payload bytes). Server frames are never masked."""
    b0, b1 = _recv_exactly(sock, 2)
    opcode = b0 & 0x0F
    masked = bool(b1 & 0x80)
    length = b1 & 0x7F
    if length == 126:
        (length,) = struct.unpack(">H", _recv_exactly(sock, 2))
    elif length == 127:
        (length,) = struct.unpack(">Q", _recv_exactly(sock, 8))
    if length > MAX_FRAME_BYTES:
        raise ProtocolError(f"server frame of {length} bytes exceeds the 1 MiB cap")
    mask = _recv_exactly(sock, 4) if masked else None
    payload = _recv_exactly(sock, length) if length else b""
    if mask:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def _recv_json_response(sock, want_id):
    """Reads frames until the response with `want_id` arrives.

    The gateway pushes unsolicited `event` frames on the same socket, so a
    naive "first frame is my answer" read is wrong — it would randomly pick up
    an activity-feed broadcast and report it as the RPC result.
    """
    while True:
        opcode, payload = _recv_frame(sock)
        if opcode == 0x9:  # ping -> pong, keep the session alive
            _send_pong(sock, payload)
            continue
        if opcode == 0xA:  # pong, ignore
            continue
        if opcode == 0x8:  # close
            raise ProtocolError("server closed the connection before answering")
        if opcode != 0x1:
            continue
        try:
            frame = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ProtocolError(f"server frame was not JSON text: {exc}") from exc
        if frame.get("type") == "res" and frame.get("id") == want_id:
            return frame


def _send_pong(sock, payload):
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes([0x8A, 0x80 | len(payload)]) + mask + masked)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="ws://127.0.0.1:18789/ws")
    parser.add_argument("--jwt", required=True)
    parser.add_argument("method")
    parser.add_argument("params", nargs="?", default="{}")
    # Default stays 30s (every network.* call answers in milliseconds). The
    # override exists for RPCs that legitimately hold the socket for minutes:
    # `device.update_apply` downloads a multi-gigabyte OS payload before it
    # answers, and a 30s read timeout would report a transport failure for a
    # call that is working perfectly.
    parser.add_argument("--read-timeout", type=float, default=READ_TIMEOUT_SECS,
                        help="seconds to wait for each server frame (default: 30)")
    args = parser.parse_args()

    parsed = urllib.parse.urlparse(args.url)
    if parsed.scheme != "ws":
        print(f"only ws:// is supported, got {parsed.scheme!r}", file=sys.stderr)
        return 2
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or 80
    path = parsed.path or "/ws"

    try:
        params = json.loads(args.params)
    except json.JSONDecodeError as exc:
        print(f"params is not valid JSON: {exc}", file=sys.stderr)
        return 2

    sock = socket.create_connection((host, port), timeout=READ_TIMEOUT_SECS)
    sock.settimeout(args.read_timeout)
    try:
        _handshake(sock, host, port, path)

        # The gateway resolves a UserContext from the FIRST frame, which must
        # be a `connect` request carrying the JWT (server.rs, handle_socket).
        _send_text(sock, json.dumps({"type": "req", "id": "auth", "method": "connect", "params": {"jwt": args.jwt}}))
        auth = _recv_json_response(sock, "auth")
        if not auth.get("ok"):
            print(json.dumps(auth.get("error"), ensure_ascii=False), file=sys.stderr)
            return 2

        _send_text(sock, json.dumps({"type": "req", "id": "call", "method": args.method, "params": params}, ensure_ascii=False))
        answer = _recv_json_response(sock, "call")
    except (ProtocolError, OSError) as exc:
        print(f"transport failure: {exc}", file=sys.stderr)
        return 2
    finally:
        sock.close()

    if answer.get("ok"):
        print(json.dumps(answer.get("payload"), ensure_ascii=False))
        return 0
    print(json.dumps(answer.get("error"), ensure_ascii=False))
    return 1


if __name__ == "__main__":
    sys.exit(main())
