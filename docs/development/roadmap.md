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
| **0.3.0** | 2026-05-23 | **dig MVP — first end-to-end resolution.** Real UDP queries against arbitrary resolvers; A / AAAA / MX / NS / CNAME / SOA / PTR / TXT / SRV parsed; BIND-shape + `+short` output. 8 src/ modules (cli, dns, ipv4, output, platform/platform_linux, query, resolv) totaling 1410 LOC. 70 test assertions including name-compression cycle detection. Per-backend sovereignty posture: pragmatic POSIX on Linux, AGNOS backend deferred to v1.0 gate (same as yo). At the time, 0.2.x kernel UDP-53 syscall exposure was still pending (the Linux-backend-first bypass kept momentum); that surface has since landed (agnos 1.45.3, #51-54) and the AGNOS backend now resolves end-to-end. |

---

## Backlog — path to v1.0

Ordered by dependency. Items further down depend on items earlier.

### 0.2.x — Kernel UDP-53 / TCP-53 primitives (kernel-side, in `agnos`) ✅ landed

**Landed**: the agnos r8169 RX-path was solved 2026-05-25 (1.32.7 — RX ring 16→64, iron-validated), and the ring-3 net syscalls dig consumes shipped in the 1.45.x arc. The AGNOS backend (`src/platform_agnos.cyr`) is built and resolves real names end-to-end on agnos (dig 0.3.1 returned an A-record for `example.com` over the UDP syscalls in ring 3 — agnos `net-tool-smoke.sh` 2/2).

- [x] Cyrius-native UDP-53 to userland — **landed agnos 1.45.3 as `udp_bind`#51 / `udp_send`#52 / `udp_recv`#53 / `udp_unbind`#54** (listener-id based, non-blocking; per-query bind/unbind reclaim). `src/platform_agnos.cyr` calls them via the cyrius ≥ 6.2.6 peer (`sys_udp_bind`/`sys_udp_send`/`sys_udp_recv`/`sys_udp_unbind`). Narrow surface, not POSIX socket emulation — per [[project_agnos_kernel_growth_rules]].
- [x] TCP-53 client primitives — **landed agnos 1.45.1 as `sock_connect`#47 / `sock_send`#48 / `sock_recv`#49 / `sock_close`#50**. The kernel surface for DNS-over-TCP exists; wiring dig's `+tcp` path onto it is dig-side 0.4.x work (today `+tcp` is accepted-but-no-op).
- [x] source-port randomization for DNS (RFC 5452) — entropy available (`getrandom`#45, agnos 1.45.0); `src/platform_agnos.cyr` binds a randomized ephemeral source port (49152..65535).
- [x] QEMU smoke — covered by agnos `net-tool-smoke.sh` (a `NET_SELFTEST` execs `/bin/dig @10.0.2.3 example.com` → NOERROR A-record over the udp_bind→send→recv path).

### 0.3.x — dig MVP (basic A-record resolution) ✅ landed 2026-05-23

**Per-backend sovereignty rule** — the Linux backend uses POSIX `socket()` pragmatically, same posture as yo; the AGNOS backend (`src/platform_agnos.cyr`) uses the sovereign UDP-53 syscalls (#51-54) with no POSIX. The 0.2.x kernel-exposure block is cleared (landed agnos 1.45.3).

- [x] `src/main.cyr` argument parsing — hand-rolled in `src/cli.cyr` (the BIND `@server` / `+flag` / positional shape doesn't fit `lib/flags.cyr`'s `--long` grammar). Flags: `+short` / `+noshort`, `+tcp` / `+notcp` (accepted, no-op until 0.4.x), `+timeout=N`, `+retry=N`, `+nodnssec` / `+dnssec` (accepted, no validation yet), `-h` / `--help`.
- [x] DNS query packet construction per RFC 1035 § 4.1 — `src/dns.cyr:dns_build_query`. Random 16-bit query ID via `/dev/urandom`. RD bit set.
- [x] DNS response parsing per RFC 1035 § 4.1 — header (`dns_hdr_*`), question skip (`dns_skip_question`), answer section walk (`dns_answer_section_start` + `dns_parse_rr`). RR types A / NS / CNAME / SOA / PTR / MX / TXT / AAAA / SRV all format end-to-end.
- [x] Name compression decoding (RFC 1035 § 4.1.4) — `dns_decode_name` + `dns_skip_name`. **Cycle-detection guard**: pointers must aim backward + hop budget `NAME_DECODE_MAX_HOPS=32`. Self-pointer, forward-pointer, out-of-bounds-pointer, oversized-label all rejected (verified in `tests/dig.tcyr`).
- [x] Default resolver discovery — `src/resolv.cyr` reads `/etc/resolv.conf`, falls back to `8.8.8.8`. User overrides via `@server`.
- [x] BIND-shape output — `src/output.cyr`. Full header + `;; ->>HEADER<<-` + `;; QUESTION` + `;; ANSWER` + `;; Query time: N ms · server: X · proto: udp` footer. `+short` mode prints bare rdata.

### 0.4.x — Full record-type coverage + advanced flags

- [ ] Additional RR types: TXT multi-string parsing, SOA (master/admin/serial/refresh/retry/expire/minimum), HINFO, RRSIG, DNSKEY, DS, NSEC, NSEC3 (the DNSSEC ladder).
- [ ] `+trace` flag — manual recursion from root servers. Walks root → TLD → authoritative chain, prints each step. Useful for diagnosing delegation issues.
- [ ] `+dnssec` flag — request DNSKEY + RRSIG; validate chain of trust against the root KSK (RFC 4034 + RFC 5155). Defer the cryptographic-validation work to a `taar.dnssec` submodule.
- [ ] EDNS(0) support (RFC 6891) — OPT pseudo-RR, larger UDP buffer (4096), DO bit signaling DNSSEC-OK.
- [ ] IPv6 transport: query via `udp_send` against `2001:4860:4860::8888` (Google) etc.; AAAA queries are already in 0.3.x record-type list.

### 0.5.x — Iron validation + parity check

**Status**: the r8169 RX-path dependency cleared (solved 2026-05-25, 1.32.7, iron-validated). dig already resolves `example.com` end-to-end on agnos under QEMU (agnos `net-tool-smoke.sh`); the items below are the remaining real-iron (archaemenid) + parity runs.

- [ ] First iron run: `dig example.com` on archaemenid against `192.168.1.1`. Expected: A record returned, query time < 50 ms.
- [ ] First WAN run: `dig @8.8.8.8 google.com`. Expected: A + AAAA, query time in 10-50 ms range from a US residential connection.
- [ ] First DNSSEC run: `dig +dnssec example.com`. Expected: chain validates against the root KSK.
- [ ] Parity benchmark vs BIND's `dig` on the same host — query latency + memory footprint + binary size. Target: ≤ 25 ms median, ≤ 5 MB RSS, ≤ 40 KB binary.

### 0.6.x — `taar` EXTRACTION (trigger FIRED 2026-06-15, ahead of slot — partially done)

**This is the load-bearing milestone — dig completion is the second-consumer-trigger that shapes the network-probe substrate library.**

- [x] `taar` repo created (0.1.0). Per-protocol submodule layout planned (`icmp`/`dns`/`socket`/`kernel`); **`src/ipv4.cyr` shipped first** (the byte-identical yo/dig codec) → `dist/taar.cyr`. The other modules fold in as consumers need them.
- [ ] Move yo's local ICMP framing + dig's DNS framing into `taar` (`icmp.cyr` / `dns.cyr`) — not yet done; only `ipv4` has moved so far.
- [x] `yo/cyrius.cyml` + `dig/cyrius.cyml` depend on `taar` (`[deps.taar]` git+path, tag 0.1.0, `modules = ["dist/taar.cyr"]`). CLI surfaces stayed byte-stable.
- [x] yo 0.5.5 + dig 0.3.3 consume `taar` without API change.
- [x] Per [[feedback_dep_lockin_sandhi_unlock]] — extraction fired at the duplication point (2026-06-15), not deferred to dig 1.0. The `ipv4` fold was the moment.
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
- [ ] **`taar` extracted** as a separate repo — STARTED (taar 0.1.0; `dig` depends on it via `[deps.taar]`; the `ipv4` codec is lifted out, not vendored). Remaining for v1.0: dig's `dns`/socket primitives also live in `taar` rather than locally.
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

- **Substrate (extracted via dig)**: [taar — 0.1.0 scaffolded 2026-06-15; dig consumes it (ipv4 module)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Sibling tools**: [yo (scaffolded, consumes taar)](https://github.com/MacCracken/yo), [whirl (planned — third taar consumer)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Iron dependency**: [agnos r8169 RX-path 5-part bundle](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — **cleared** (r8169 RX solved 2026-05-25, 1.32.7, iron-validated). The LAN-on-iron path is unblocked; what remains is the actual archaemenid dig run.
- **Kernel-growth posture**: AGNOS `state.md` + memory [[project_agnos_kernel_growth_rules]].
- **Naming lane**: English-wordplay / trickster lane (cultural-reference path: Cyrus from The Warriors → Cyrius the language) per [[feedback_naming_lanes]] memory. Family: cmdrs, bnrmr, iam, hapi, kii, yo, **dig**, whirl.
