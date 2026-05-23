# dig — Roadmap

> **Status**: Active | **Last Updated**: 2026-05-23
>
> Milestone path from scaffold (0.1.0) through v1.0 (full BIND `dig` parity + LAN-on-iron + `taar` extraction trigger fired). Per first-party-documentation roadmap shape: **Completed** / **Backlog** / **Future** / **v1.0 criteria**.
>
> Volatile state (binary size, test count, current cycle) lives in [`state.md`](state.md). This file is the milestone plan; state.md is the live snapshot.

---

## Completed

| Version | Landed | Items |
|---|---|---|
| **0.1.0** | 2026-05-23 | Initial `cyrius init` scaffold. README + CLAUDE.md + LICENSE + CHANGELOG + cyrius.cyml + tests/dig.{tcyr,bcyr,fcyr} + `.github/workflows/{ci,release}.yml`. Stub `main.cyr` prints `hello from dig`. Stdlib vendored in `lib/` (81 modules incl. `net.cyr`). |

---

## Backlog — path to v1.0

Ordered by dependency. Items further down depend on items earlier.

### 0.2.x — Kernel UDP-53 / TCP-53 primitives (kernel-side, in `agnos`)

**Blocked on**: r8169 RX-path 5-part bundle iron-validating (Attempt 97 pending — same dependency yo carries). Kernel UDP path already exists from the 1.32.0 networking arc (DHCP client uses it); dig adds the consumer-side surface for arbitrary UDP queries.

- [ ] Cyrius-native `udp_send(dst_ip, dst_port, payload, len)` / `udp_recv(listener_id, buf, maxlen, &src_ip, &src_port, timeout_ms)` exposed to userland. The kernel already has these primitives internally per `agnos/kernel/core/net.cyr:142-217` — exposing them via syscall is the bite. Per [[project_agnos_kernel_growth_rules]] — narrow surface, not POSIX socket emulation.
- [ ] `tcp_connect(dst_ip, dst_port, timeout_ms) → conn_id` / `tcp_send(conn_id, buf, len)` / `tcp_recv(conn_id, buf, maxlen, timeout_ms)` / `tcp_close(conn_id)` for DNS-over-TCP (`+tcp` flag, large responses). TCP client primitives also already exist in `net.cyr`; same exposure pattern as UDP.
- [ ] Optional: source-port randomization for DNS (RFC 5452) — security mitigation against off-path cache-poisoning. May land at v0.2.x or defer to v0.4.x.
- [ ] QEMU-side smoke: `qemu-dns-smoke.sh` boots kernel + queries a local DNS resolver running on the host (or SLIRP's built-in DNS at 10.0.2.3) for `example.com`, asserts an A-record comes back.

### 0.3.x — dig MVP (basic A-record resolution)

**Blocked on**: 0.2.x kernel syscall exposure.

- [ ] `src/main.cyr` argument parsing via `lib/args.cyr` and `lib/flags.cyr`. Positional args: `dig [@server] [name] [type]`. Flags: `+short` (one-line output), `+tcp` (force TCP), `+timeout=N` (default 5s), `+retry=N` (default 3), `+nodnssec` (skip DNSSEC validation).
- [ ] DNS query packet construction per RFC 1035 § 4.1 (header + question section). Random 16-bit query ID. Standard query, recursion-desired bit set.
- [ ] DNS response parsing per RFC 1035 § 4.1: header, question section echo-back, answer section. RR types: A (1), NS (2), CNAME (5), SOA (6), PTR (12), MX (15), TXT (16), AAAA (28), SRV (33).
- [ ] Name compression decoding (RFC 1035 § 4.1.4) — back-pointer chasing, with cycle-detection guard (kernel-mode security: a malicious response could otherwise lock the parser).
- [ ] Default resolver discovery: read `/etc/resolv.conf` if present, else fall back to `192.168.1.1` (gateway) or `8.8.8.8` (public). User can override via `@server` arg.
- [ ] BIND-shape output: `; <<>> dig X.Y.Z <<>> name`, `;; QUESTION`, `;; ANSWER`, `;; Query time: N ms · server: X · proto: udp/tcp`.

### 0.4.x — Full record-type coverage + advanced flags

- [ ] Additional RR types: TXT multi-string parsing, SOA (master/admin/serial/refresh/retry/expire/minimum), HINFO, RRSIG, DNSKEY, DS, NSEC, NSEC3 (the DNSSEC ladder).
- [ ] `+trace` flag — manual recursion from root servers. Walks root → TLD → authoritative chain, prints each step. Useful for diagnosing delegation issues.
- [ ] `+dnssec` flag — request DNSKEY + RRSIG; validate chain of trust against the root KSK (RFC 4034 + RFC 5155). Defer the cryptographic-validation work to a `taar.dnssec` submodule.
- [ ] EDNS(0) support (RFC 6891) — OPT pseudo-RR, larger UDP buffer (4096), DO bit signaling DNSSEC-OK.
- [ ] IPv6 transport: query via `udp_send` against `2001:4860:4860::8888` (Google) etc.; AAAA queries are already in 0.3.x record-type list.

### 0.5.x — Iron validation + parity check

**Blocked on**: r8169 RX-path 5-part bundle iron-validating at Attempt 97 (yo carries the same dependency).

- [ ] First iron run: `dig example.com` on archaemenid against `192.168.1.1`. Expected: A record returned, query time < 50 ms.
- [ ] First WAN run: `dig @8.8.8.8 google.com`. Expected: A + AAAA, query time in 10-50 ms range from a US residential connection.
- [ ] First DNSSEC run: `dig +dnssec example.com`. Expected: chain validates against the root KSK.
- [ ] Parity benchmark vs BIND's `dig` on the same host — query latency + memory footprint + binary size. Target: ≤ 25 ms median, ≤ 5 MB RSS, ≤ 40 KB binary.

### 0.6.x — `taar` EXTRACTION (the trigger fires)

**This is the load-bearing milestone — dig completion is the second-consumer-trigger that shapes the network-probe substrate library.**

- [ ] Open `/home/macro/Repos/taar/` via `cyrius init taar`. Per-protocol submodule layout: `taar/src/icmp.cyr` (from yo) + `taar/src/dns.cyr` (from dig) + `taar/src/socket.cyr` (the union of UDP + TCP primitives) + `taar/src/kernel.cyr` (the syscall shim).
- [ ] Move yo's local ICMP framing + DNS shim (if any) into `taar`. Move dig's local DNS framing into `taar/src/dns.cyr`.
- [ ] Refactor `yo/cyrius.cyml` + `dig/cyrius.cyml` to depend on `taar`. CLI surfaces of both tools stay byte-stable across the refactor (verifiable via `scripts/test.sh` regression + the `+short` output diff against BIND).
- [ ] Bump yo + dig to consume `taar` without API change.
- [ ] Per [[feedback_dep_lockin_sandhi_unlock]] — extraction trigger fires NOW; don't let the lib stay private just because dig is "almost done." This IS the moment.
- [ ] When `whirl` arrives (post-taar-extraction), it adds `taar/src/tcp.cyr` + `taar/src/tls.cyr` + `taar/src/http.cyr` as additive submodules — no refactor of the icmp/dns/socket modules.

---

## Future (post-1.0)

Lower priority. Item shape pinned for orientation; specific versions TBD.

- [ ] **Bulk query mode** (`dig -f queryfile`) — BIND parity for batch DNS-audit workflows.
- [ ] **Reverse-DNS-only shortcut** (`dig -x 192.168.1.1`) — convenience for the PTR lookup.
- [ ] **JSON output** (`dig +json`) — machine-readable, for piping into other tools (`yo --diag`, `aegis`, `phylax` audit chains).
- [ ] **Audit-chain integration** — when `libro` lands, log every `dig` invocation + result to the audit chain. Forensic value: *"who queried what, when, with what outcome."*
- [ ] **DNS-over-HTTPS (DoH) / DNS-over-TLS (DoT)** — RFC 8484 / RFC 7858. Naturally lands after whirl ships (HTTPS), as it consumes `taar.http` + `taar.tls`.
- [ ] **DNSSEC trust-anchor management** — manage the local trust-anchor file (root KSK rollover); separate sub-command (`dig trust-anchor refresh`).

---

## v1.0 criteria (release gate)

Ship 1.0 when all of these are true. Pre-1.0 minor cycles can land partial subsets; the v1.0 tag is the all-of-these gate.

- [ ] **Feature parity with BIND `dig`**: A / AAAA / MX / TXT / NS / CNAME / SOA / SRV / PTR / DNSKEY / RRSIG / DS / NSEC / NSEC3, `+short` / `+trace` / `+tcp` / `+dnssec` / `+timeout` / `+retry`, IPv4 + IPv6 transport, EDNS(0).
- [ ] **`taar` extracted** as a separate repo. `dig` depends on `taar`; the kernel network primitives are not vendored back into `dig`.
- [ ] **LAN-on-iron validated** on archaemenid against the home gateway resolver (`192.168.1.1`) and at least one public resolver (`8.8.8.8`, `1.1.1.1`).
- [ ] **QEMU validated** via `scripts/qemu-smoke.sh` — boots a kernel with dig in the initrd, queries SLIRP's built-in DNS at `10.0.2.3` for `example.com`, asserts an A-record comes back.
- [ ] **No POSIX `socket()`** anywhere in `dig` or `taar`. Sovereign kernel primitives only. Audit pass per [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md#security-hardening-required-before-every-release).
- [ ] **Tests**: `scripts/test.sh` ≥ 40 assertions covering arg parsing, every RR-type parse path, name-compression cycle detection, EDNS(0) edge cases. `tests/dig.fcyr` fuzz harness for the response-frame parser (the security-critical path — DNS responses are the classic supply-chain compromise vector). `tests/dig.bcyr` benchmark vs BIND's `dig`.
- [ ] **Docs**: ADR for the resolver-discovery decision (`/etc/resolv.conf` vs hardcoded fallback vs runtime config), architecture note for the name-compression cycle-detection invariant, guide for the DNSSEC trust-anchor workflow.
- [ ] **CI green**: `.github/workflows/{ci,release}.yml` both green on the v1.0 candidate commit. Release workflow auto-uploads `build/dig` to the GitHub release.

---

## Out of scope (for v1.0)

Deliberate exclusions — keeps future contributors from adding to v1.0 by accident.

- **Authoritative-server mode** — `dig` is a resolver client, not a server. The AGNOS authoritative-DNS-server, if/when it lands, will be a separate repo with its own naming-lane decision.
- **Caching resolver mode** — same lane separation. dig is one-shot query-and-print; the local-caching-resolver concern (Unbound-equivalent) is separate.
- **GUI / TUI front-end** — dig is CLI-only.
- **Windows / macOS host targets** — dig targets the AGNOS kernel + the Cyrius cross-platform stdlib. macOS / Windows ports defer to when the broader Cyrius stdlib gains those targets at parity.

---

## Cross-references

- **Substrate (extracted via dig)**: [taar (planned, dig is extraction trigger)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Sibling tools**: [yo (already scaffolded)](https://github.com/MacCracken/yo), [whirl (planned, post-taar-extraction)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Iron dependency**: [agnos r8169 RX-path 5-part bundle](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — LAN-on-iron path unblocks when Attempt 97 validates.
- **Kernel-growth posture**: AGNOS `state.md` + memory [[project_agnos_kernel_growth_rules]].
- **Naming lane**: English-wordplay / trickster lane (cultural-reference path: Cyrus from The Warriors → Cyrius the language) per [[feedback_naming_lanes]] memory. Family: cmdrs, bnrmr, iam, hapi, kii, yo, **dig**, whirl.
