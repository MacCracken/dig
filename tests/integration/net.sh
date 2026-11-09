#!/usr/bin/env bash
# dig — network-path integration tests.
#
# tests/dig.tcyr covers the parsers and policies a function at a time; none of
# it runs main(), so the transport flow — UDP send/recv/retry, the TC=1 -> TCP
# fallback, which buffer ends up printed, what goes to stdout vs stderr, the
# exit code — had no test at all through 0.5.1. That is how a rejected TCP
# reply came to be printed as the answer with exit 0. This runs the real binary
# against tests/integration/fake_dns.py, which serves crafted replies on
# 127.0.0.1:53, and checks what dig printed and how it exited.
#
# Port 53 needs CAP_NET_BIND_SERVICE, so every case runs in its own
# `unshare -rnm`: a private user + network + mount namespace where we hold the
# capability, loopback is ours, and /etc/resolv.conf can be bind-mounted over
# for the discovery cases. No root; nothing on the host changes.
#
#   tests/integration/net.sh            # builds its own binary from this checkout
#   tests/integration/net.sh <binary>   # or tests one you built
#
# Needs python3 and iproute2's `ip`. Each case runs under `timeout`, so a
# regression that hangs fails in a minute instead of stalling the run.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CASE_TIMEOUT=60

if [ $# -ge 1 ]; then
    BIN="$(realpath "$1")"
else
    BIN="$WORK/dig"
    if ! (cd "$ROOT" && cyrius build src/main.cyr "$BIN") >"$WORK/build.log" 2>&1; then
        cat "$WORK/build.log"; echo "build failed"; exit 1
    fi
fi

if ! unshare -rnm true 2>/dev/null; then
    echo "unshare -rnm is not permitted here; the integration cases cannot run" >&2
    exit 2
fi

OUT="$WORK/out"; ERR="$WORK/err"; SRVLOG="$WORK/srv.log"; MSF="$WORK/ms"; COMB="$WORK/comb"
export BIN OUT ERR SRVLOG MSF COMB
RC=0; MS=0; RESOLV=""

# run MODE DIG-ARGS...   One case: start fake_dns.py in MODE (or no server at
# all for MODE=down), run dig, and record RC, MS, stdout, stderr and the
# server's query log. STOPCONT=1 stops dig for 0.5 s one second in. RESOLV=file
# bind-mounts that file over /etc/resolv.conf first. COMBINED=1 runs dig a second
# time into one 2>&1 stream, $COMB, to check the two streams' ORDER.
run() {
    local mode="$1"; shift
    : > "$SRVLOG"; : > "$OUT"; : > "$ERR"; : > "$COMB"; echo 0 > "$MSF"
    MODE="$mode" STOPCONT="${STOPCONT:-0}" COMBINED="${COMBINED:-0}" RESOLV="$RESOLV" FAKE="$HERE/fake_dns.py" \
    timeout "$CASE_TIMEOUT" unshare -rnm bash -c '
        ip link set lo up || exit 3
        if [ -n "$RESOLV" ]; then mount --bind "$RESOLV" /etc/resolv.conf || exit 4; fi
        if [ "$MODE" != down ]; then
            python3 -I "$FAKE" "$MODE" "$SRVLOG" &
            srv=$!
            for _ in $(seq 100); do grep -q "^ready" "$SRVLOG" 2>/dev/null && break; sleep 0.02; done
        fi
        s=$(date +%s%N)
        "$BIN" "$@" >"$OUT" 2>"$ERR" &
        dig=$!
        if [ "$STOPCONT" = 1 ]; then
            sleep 1; kill -STOP $dig; sleep 0.5; kill -CONT $dig
        fi
        wait $dig
        rc=$?
        echo $(( ($(date +%s%N) - s) / 1000000 )) >"$MSF"
        if [ "$COMBINED" = 1 ]; then "$BIN" "$@" >"$COMB" 2>&1; fi
        [ -n "${srv:-}" ] && kill $srv 2>/dev/null
        exit $rc
    ' bash "$@"
    RC=$?
    MS=$(cat "$MSF")
}

n=0; fail=0
expect() {
    local what="$1"; shift
    n=$((n + 1))
    if "$@"; then
        echo "  ok   $what"
    else
        fail=$((fail + 1))
        echo "  FAIL $what"
        echo "       rc=$RC ms=$MS stdout=[$(head -c 300 "$OUT" | tr '\n' '|')] stderr=[$(head -c 300 "$ERR" | tr '\n' '|')]"
    fi
}
rc_is()     { [ "$RC" = "$1" ]; }
out_is()    { [ "$(cat "$OUT")" = "$1" ]; }
out_has()   { grep -qF -- "$1" "$OUT"; }
out_lacks() { ! grep -qF -- "$1" "$OUT"; }
err_has()   { grep -qF -- "$1" "$ERR"; }
err_lacks() { ! grep -qF -- "$1" "$ERR"; }
ms_under()  { [ "$MS" -lt "$1" ]; }
ms_over()   { [ "$MS" -ge "$1" ]; }
queries()   { [ "$(grep -c "^$1 " "$SRVLOG")" = "$2" ]; }
fresh_ports() { [ "$(awk '/^udp /{print $3}' "$SRVLOG" | sort -u | wc -l)" = "$(grep -c '^udp ' "$SRVLOG")" ]; }
no_esc()    { ! LC_ALL=C grep -q $'\x1b' "$OUT" "$ERR"; }
lines()     { [ "$(wc -l <"$OUT")" = "$1" ]; }
# The fixed strings, in this order, each on a later line of the 2>&1 stream.
in_order()  { awk -v a="$1" -v b="$2" -v c="$3" 'index($0,a)&&!x{x=NR} index($0,b)&&x&&!y&&NR>x{y=NR} index($0,c)&&y&&!z&&NR>y{z=NR} END{exit !(x&&y&&z)}' "$COMB"; }

S="@127.0.0.1 example.com"

echo "=== UDP transport"
run ok $S +short
expect "plain answer, exit 0"                         rc_is 0
expect "  printed on stdout"                          out_is "1.2.3.4"
run late_dup $S +short
expect "wrong-ID datagram skipped, right one taken"   out_is "1.2.3.4"
run silent $S +tries=2 +timeout=1
expect "+tries=2 sends two queries"                   queries udp 2
expect "  from a fresh source port each"              fresh_ports
expect "  then times out, exit 9"                     rc_is 9
expect "  saying so"                                  err_has "connection timed out"
run silent $S +retry=1 +timeout=1
expect "+retry=1 is two tries, as in BIND"            queries udp 2
run silent $S +timeout=1
expect "default is three tries"                       queries udp 3
run down $S
expect "refused port: exit 9"                         rc_is 9
expect "  reported as refused, not timed out"         err_has "connection refused"
expect "  without waiting out the timeout"            ms_under 1000
run down $S +tcp
expect "refused TCP port reported as refused"         err_has "connection refused"
# +retry=0 (one try) rather than +tries=1: 0.5.1 did not know +tries, ignored
# it, ran three tries, and so passed this check for the wrong reason.
STOPCONT=1 run silent $S +timeout=3 +retry=0
expect "SIGSTOP/SIGCONT does not end the try early"   ms_over 2700
expect "  and it is still one try"                    ms_under 4500
STOPCONT=1 run tcp_hang $S +tcp +timeout=3
expect "  nor a TCP read"                             ms_over 2700
expect "  which then times out"                       err_has "timed out"
STOPCONT=0

echo "=== TC=1 -> TCP fallback"
run tc_ok $S
expect "fallback answer, exit 0"                      rc_is 0
expect "  the TCP answer is printed"                  out_has "1.2.3.5"
expect "  footer says tcp"                            out_has "proto: tcp"
for m in tc_wrongq tc_wrongid tc_noqr; do
    run $m $S +short
    expect "$m: rejected TCP reply is NOT printed"   out_is "1.1.1.1"
    expect "  the UDP prefix is flagged on stderr"    err_has "TCP retry failed"
    expect "  and the run fails, exit 9"              rc_is 9
done
run tc_partial $S +tcp +short
expect "torn TCP stream: exit 9, nothing printed"     out_is ""
expect "  reported as end of file"                    err_has "end of file"
run tc_slow $S +tcp +timeout=1 +short
expect "slow-drip TCP bounded by +timeout"            ms_under 3000
expect "  and fails, exit 9"                          rc_is 9
run tc_tcptc $S
expect "TC on a TCP reply is ignored"                 rc_is 0
expect "  no truncation warning"                      err_lacks "truncated"
run tc_notcp $S TXT +short
expect "TC + no TCP: the prefix shows"                out_is '"record-1-of-3"'
expect "  flagged on stderr"                          err_has "TCP retry failed"
expect "  exit 9"                                     rc_is 9
run tc_notcp $S TXT +short +ignore
expect "+ignore keeps the prefix, exit 0"             rc_is 0
expect "  and says so"                                err_has "+ignore kept"
run tc_notcp $S TXT +short +notcp
expect "+notcp does not suppress the fallback (BIND)" rc_is 9
run tc_notcp_empty $S TXT +short
expect "TC to nothing + no TCP: not silent"           err_has "TCP retry failed"
expect "  nothing on stdout, exit 9"                  rc_is 9

echo "=== reply checks"
run opcode $S +timeout=1 +tries=1
expect "opcode STATUS reply not accepted"             out_lacks "6.6.6.6"
run formerr_noq $S
expect "question-less FORMERR reported, exit 0"       out_has "status: FORMERR"
expect "  with a warning"                             err_has "no question section"
run multi_opt $S
expect "two OPT records: malformed, exit 9"           err_has "more than one OPT"
run opt_ext $S +noedns
expect "OPT in reply to +noedns not folded in"        out_has "status: NOERROR"
run opt_ext $S
expect "extended RCODE 16 named BADVERS"              out_has "status: BADVERS"
run oversize $S TXT +noedns +short
expect "oversize UDP read whole, not cut at 512"      lines 4
expect "  exit 0"                                     rc_is 0
run overclaim $S +short
expect "ANCOUNT overclaim: stdout holds rdata only"   out_is "1.2.3.4"
expect "  counts go to stderr"                        err_has "truncated after 1 of 3"
COMBINED=1 run overclaim $S
expect "  and land between the record and the footer" in_order "1.2.3.4" "truncated after 1 of 3" "Query time"
COMBINED=0
run txt_empty $S TXT +short
expect "empty TXT: no blank line on stdout"           out_is ""
expect "  malformed, exit 9"                          rc_is 9
run bad_a $S +short
expect "malformed A: no stray newline on stdout"      out_is "5.6.7.8"

echo "=== echoes of argv"
run ok @127.0.0.1 $'x\e]0;PWNED\a\e[2J.example'
expect "a hostile query name never writes ESC"        no_esc
run ok $'\e[31m'"$(printf 'a%.0s' $(seq 70))"
expect "  nor does the illegal-name error"            no_esc
run ok $S +bogus$'\e[2J'
expect "  nor does an invalid-option error"           no_esc
expect "  which is a usage error, exit 1"             rc_is 1

echo "=== resolv.conf discovery"
RESOLV="$WORK/rc.good"; printf 'nameserver 127.0.0.1\n' >"$RESOLV"
run ok example.com +short
expect "resolv.conf nameserver used"                  out_is "1.2.3.4"
RESOLV="$WORK/rc.v6"; printf 'nameserver ::1\n' >"$RESOLV"
run ok example.com +short
expect "IPv6-only resolv.conf fails closed, exit 9"   rc_is 9
expect "  says why"                                   err_has "no usable nameserver"
expect "  and sends nothing anywhere"                 queries udp 0
# `nameserver 127.0.0.12` with its final `2` at byte 16384: a read capped at
# 16 KiB used to see `127.0.0.1`, a different valid address, and query it.
RESOLV="$WORK/rc.cut"
{ printf '#%.0s' $(seq 16363); printf '\nnameserver 127.0.0.12\n'; } >"$RESOLV"
run ok example.com +short
expect "a line cut at the 16 KiB cap is not used"     queries udp 0
expect "  fails closed, exit 9"                       rc_is 9
RESOLV="$WORK/rc.none"; printf 'search example.com\n' >"$RESOLV"
run ok example.com +short +timeout=1 +tries=1
expect "no nameserver line: warned public fallback"   err_has "falling back to 8.8.8.8"
RESOLV=""

echo
if [ $fail -eq 0 ]; then echo "all $n checks passed"; else echo "$fail of $n checks FAILED"; fi
exit $(( fail > 0 ))
