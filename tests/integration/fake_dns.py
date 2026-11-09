#!/usr/bin/env python3
"""Scriptable DNS responder for dig's network-path integration tests.

Answers on 127.0.0.1:53, UDP and (per mode) TCP, with replies built to drive one
code path in dig each: the TC=1 -> TCP fallback, forged and torn TCP replies,
slow-drip TCP, malformed rdata, EDNS edge cases. Port 53 needs
CAP_NET_BIND_SERVICE, so run it inside `unshare -rn` (see net.sh), never as root.

    fake_dns.py MODE LOGFILE

Every query is logged as one line, `udp <id> <src-port>` or `tcp <id>`, so the
runner can count tries and see whether each try used a fresh source port. The
line `ready` is written once both sockets are bound.

Modes:
  ok              A 1.2.3.4
  silent          never answers (UDP queries are still logged)
  late_dup        first a reply with the wrong ID, then the right one
  opcode          right ID and question, opcode STATUS (2)
  formerr_noq     FORMERR with QDCOUNT=0 (no question echoed)
  multi_opt       an answer plus TWO OPT records
  opt_ext         an answer plus an OPT whose extended RCODE is 1 (BADVERS)
  oversize        four 200-byte TXT strings, 881 bytes, TC=0 whatever was asked
  overclaim       ANCOUNT=3 but only one A record present
  txt_empty       a TXT record with RDLENGTH 0
  bad_a           an A record with RDLENGTH 5, then a good A 5.6.7.8
  tc_ok           UDP: TC=1, prefix 1.1.1.1.  TCP: 1.2.3.4 and 1.2.3.5
  tc_wrongq       UDP as tc_ok.  TCP: answers a DIFFERENT question, 6.6.6.6
  tc_wrongid      UDP as tc_ok.  TCP: wrong ID, 6.6.6.6
  tc_noqr         UDP as tc_ok.  TCP: QR clear, 6.6.6.6
  tc_partial      UDP as tc_ok.  TCP: all but the last 5 bytes, then close
  tc_slow         UDP as tc_ok.  TCP: one byte every 0.9 s
  tc_tcptc        UDP as tc_ok.  TCP: TC=1 set on the TCP reply, 1.2.3.4
  tc_notcp        UDP: TC=1, one TXT "record-1-of-3".  No TCP listener.
  tc_notcp_empty  UDP: TC=1, no records.  No TCP listener.
  tcp_hang        TCP: reads the query, then never answers
"""
import socket
import struct
import sys
import threading
import time

MODE = sys.argv[1]
LOG = open(sys.argv[2], "a", buffering=1)
ADDR = ("127.0.0.1", 53)

QR, TC, RD, RA = 0x8000, 0x0200, 0x0100, 0x0080
NO_TCP = ("tc_notcp", "tc_notcp_empty")


def log(line):
    print(line, file=LOG)


def parse_query(q):
    qid = struct.unpack(">H", q[0:2])[0]
    i = 12
    while q[i] != 0:
        i += 1 + q[i]
    i += 1
    qtype, qclass = struct.unpack(">HH", q[i:i + 4])
    return qid, q[12:i] + struct.pack(">HH", qtype, qclass)


def hdr(qid, flags, qd, an, ns, ar):
    return struct.pack(">HHHHHH", qid, flags, qd, an, ns, ar)


def rr(rtype, rdata, owner=b"\xc0\x0c", ttl=60):
    return owner + struct.pack(">HHIH", rtype, 1, ttl, len(rdata)) + rdata


def a(ip):
    return rr(1, socket.inet_aton(ip))


def txt(s):
    return rr(16, bytes([len(s)]) + s.encode())


def opt(ext=0):
    return b"\0" + struct.pack(">HHBBHH", 41, 1232, ext, 0, 0, 0)


def name(n):
    out = b""
    for label in n.split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\0"


def udp_replies(q):
    qid, question = parse_query(q)
    ok = QR | RD | RA
    if MODE == "silent":
        return []
    if MODE == "late_dup":
        return [hdr(qid ^ 1, ok, 1, 1, 0, 0) + question + a("6.6.6.6"),
                hdr(qid, ok, 1, 1, 0, 0) + question + a("1.2.3.4")]
    if MODE == "opcode":
        return [hdr(qid, ok | (2 << 11), 1, 1, 0, 0) + question + a("6.6.6.6")]
    if MODE == "formerr_noq":
        return [hdr(qid, QR | RD | 1, 0, 0, 0, 0)]
    if MODE == "multi_opt":
        return [hdr(qid, ok, 1, 1, 0, 2) + question + a("1.2.3.4") + opt(0) + opt(1)]
    if MODE == "opt_ext":
        return [hdr(qid, ok, 1, 1, 0, 1) + question + a("1.2.3.4") + opt(1)]
    if MODE == "oversize":
        body = b"".join(txt("x" * 200) for _ in range(4))
        return [hdr(qid, ok, 1, 4, 0, 0) + question + body]
    if MODE == "overclaim":
        return [hdr(qid, ok, 1, 3, 0, 0) + question + a("1.2.3.4")]
    if MODE == "txt_empty":
        return [hdr(qid, ok, 1, 1, 0, 0) + question + rr(16, b"")]
    if MODE == "bad_a":
        return [hdr(qid, ok, 1, 2, 0, 0) + question + rr(1, b"\1\2\3\4\5") + a("5.6.7.8")]
    if MODE == "tc_notcp":
        return [hdr(qid, ok | TC, 1, 1, 0, 0) + question + txt("record-1-of-3")]
    if MODE == "tc_notcp_empty":
        return [hdr(qid, ok | TC, 1, 0, 0, 0) + question]
    if MODE.startswith("tc_"):
        return [hdr(qid, ok | TC, 1, 1, 0, 0) + question + a("1.1.1.1")]
    return [hdr(qid, ok, 1, 1, 0, 0) + question + a("1.2.3.4")]


def tcp_reply(c, qid, question):
    ok = QR | RD | RA
    if MODE == "tc_wrongq":
        evil = name("exampl3.com") + question[-4:]
        return hdr(qid, ok, 1, 1, 0, 0) + evil + a("6.6.6.6")
    if MODE == "tc_wrongid":
        return hdr(qid ^ 0x5555, ok, 1, 1, 0, 0) + question + a("6.6.6.6")
    if MODE == "tc_noqr":
        return hdr(qid, RD | RA, 1, 1, 0, 0) + question + a("6.6.6.6")
    if MODE == "tc_tcptc":
        return hdr(qid, ok | TC, 1, 1, 0, 0) + question + a("1.2.3.4")
    return hdr(qid, ok, 1, 2, 0, 0) + question + a("1.2.3.4") + a("1.2.3.5")


def tcp_handle(c):
    try:
        ln = struct.unpack(">H", c.recv(2))[0]
        q = b""
        while len(q) < ln:
            q += c.recv(ln - len(q))
        qid, question = parse_query(q)
        log("tcp %d" % qid)
        if MODE == "tcp_hang":
            time.sleep(30)
            return
        m = tcp_reply(c, qid, question)
        framed = struct.pack(">H", len(m)) + m
        if MODE == "tc_partial":
            c.sendall(framed[:-5])
            time.sleep(0.2)
            return
        if MODE == "tc_slow":
            for b in framed:
                c.sendall(bytes([b]))
                time.sleep(0.9)
            return
        c.sendall(framed)
        time.sleep(0.2)
    except OSError:
        pass
    finally:
        c.close()


def tcp_server(s):
    while True:
        c, _ = s.accept()
        threading.Thread(target=tcp_handle, args=(c,), daemon=True).start()


u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
u.bind(ADDR)
if MODE not in NO_TCP:
    t = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    t.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    t.bind(ADDR)
    t.listen(8)
    threading.Thread(target=tcp_server, args=(t,), daemon=True).start()
log("ready")

while True:
    q, peer = u.recvfrom(65535)
    log("udp %d %d" % (struct.unpack(">H", q[0:2])[0], peer[1]))
    for r in udp_replies(q):
        u.sendto(r, peer)
