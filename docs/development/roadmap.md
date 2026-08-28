# dig — Roadmap

> **Status**: Active | **Last Updated**: 2026-08-28 (0.3.7 — post-audit revisit)
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
| **0.3.7** | 2026-08-28 | **P-1 audit / hardening sweep.** Repaired the aarch64 wrong-syscall defect (`platform_linux.cyr` hardcoded an x86_64 table used on every non-AGNOS target), the `+timeout=0` infinite hang, the silently-discarded unknown record type, and a walkable integer-overflow guard. Hardened the reply path: connected UDP socket, RFC 5452 §9.1 question matching, per-attempt query IDs, fail-closed entropy, and junk datagrams no longer consuming retries. Adopted `[deps.cmdit]` 1.2.4 and dropped the never-referenced stdlib `flags`. 70 → 102 assertions, all four repairs mutation-checked. `cyrius audit` green on all four dimensions for the first time. |

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

### 0.3.8 — the rest of the 0.3.6 audit

The 0.3.7 sweep ran eight lenses over the tree and confirmed **61** findings
against adversarial refutation (0 refuted). Both P1s and the highest-value P2s
landed in 0.3.7. These are the remainder — recorded so they are a backlog rather
than a thing everyone forgets was found. None is a feature; all are repairs on
the existing surface.

**Rendering / correctness — `src/output.cyr`, `src/dns.cyr`**
- [ ] **Propagate `output_print_rdata`'s error.** 13 validation failures return `-1`; both callers discard it and print `\n` anyway. An A record with `rdlength=5` prints an empty rdata field and **exits 0** — in `+short` that is a bare blank line, so `ip=$(dig +short host)` yields `""` and the caller is told it succeeded. Four types (MX/SRV/SOA/TXT) also partially emit before rejecting, so validation must move ahead of the first write.
- [ ] **Bound rdata-embedded names by RDLENGTH, not `msg_len`.** Memory-safe (`dns_parse_rr` caps `rdata + rdlen`), but a name is read out of the *next* record's bytes and printed as this record's authoritative content with a success return. Proven on all six arms: `NS rdlen=0` renders a neighbouring name, rc=0. This violates the contract stated three lines above the accessor in `dns.cyr`.
- [ ] **`dns_skip_name` needs the 255-byte cap `dns_decode_name` has.** It enforces label ≤ 63, the hop budget and the backward-pointer rule, but not total name length.
- [ ] **AAAA rendering is not RFC 5952** — no zero-run suppression, no `::`. The code comments already admit it.
- [ ] Unknown-type hex dump is not injective; answer line hardcodes class `IN`; question line doubles the dot on an FQDN; RCODEs 6-15 print `RCODE?`.

**Semantics — `src/main.cyr`, `src/cli.cyr`, `src/resolv.cyr`**
- [ ] **NXDOMAIN and NODATA exit 9; BIND exits 0.** A script asking "does this name exist" cannot distinguish "no" from "the resolver broke".
- [ ] **The root zone `.` cannot be queried**, and name-encode failures are reported as network faults.
- [ ] `@0.0.0.0` exits 2 with no message at all. `resolv_parse` accepts `0.0.0.0` and aborts the scan. A CRLF `/etc/resolv.conf` silently falls through to `8.8.8.8`. A `resolv.conf` over 4096 bytes is silently truncated. The public fallback is silent, and the fallback chain the docs describe does not exist in the code.
- [ ] **Per-recv timeout is armed with the full budget**, so the worst case is 2x the documented ceiling.
- [ ] Partial answers lose their footer and their counts.

**Coverage**
- [ ] **`tests/dig.fcyr` is a stub** — `if (len == 0) { return 0; } return 0;`. It is described in the v1.0 criteria as the fuzz harness for the response-frame parser, "the security-critical path". Given that this cut found two P1s in exactly that path by hand, a real harness is the highest-value test work available.
- [ ] `output.cyr` (0/8 fns), `query.cyr` (0/1) and `platform_*.cyr` (0/10) have no direct coverage.
- [ ] Dead code to remove: `RESOLV_FALLBACK_GATEWAY`, `_dig_streq_ci`, the `+72 type_seen` slot, `dns_rr_class`, `dns_rr_rdlength` — all with zero production readers.

---

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

- [x] `taar` repo created — **now at 0.5.0**. Per-protocol submodule layout planned (`icmp`/`dns`/`socket`/`kernel`); **`src/ipv4.cyr` shipped first** (the byte-identical yo/dig codec) → `dist/taar.cyr`. `socket` (UDP + TCP) and `dns` have since folded in — on **whirl's** pull, not dig's. `icmp` and `tls`/`http` remain parked pending a second consumer.
- [ ] Move yo's local ICMP framing + dig's DNS framing into `taar` (`icmp.cyr` / `dns.cyr`) — **still not done, and the premise has shifted**: taar now has its own `dns.cyr`, written for whirl rather than lifted from dig. So this is no longer an extraction dig performs; it is a migration dig would *accept*, trading `src/dns.cyr` for taar's independent implementation. Decide deliberately at 0.4.x, when `+tcp` lands and taar 0.4.0's TC-fallback path becomes the obvious alternative to writing dig's own.
- [x] `yo/cyrius.cyml` + `dig/cyrius.cyml` depend on `taar` (`[deps.taar]` git+path, **tag 0.5.0** as of dig 0.3.6, `modules = ["dist/taar.cyr"]`). CLI surfaces stayed byte-stable.
- [x] yo 0.5.5 + dig 0.3.3 consume `taar` without API change.
- [x] Per [[feedback_dep_lockin_sandhi_unlock]] — extraction fired at the duplication point (2026-06-15), not deferred to dig 1.0. The `ipv4` fold was the moment.
- [x] `whirl` arrived (0.6.13) — but **not in this shape**. It did not add `tcp`/`tls`/`http` submodules to taar: TCP went into taar's existing `socket.cyr`, TLS came from cyrius's stdlib `tls_native`, and HTTP stayed in whirl's own `src/http.cyr`. The prediction that the icmp/dns/socket modules would need no refactor did hold.

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

### 0.7.x — Host-target parity (the `platform.cyr` deferral, pulled in)

**Pulled onto the roadmap 2026-08-28**, out of "Out of scope". `src/platform.cyr` had carried a bare `Windows / macOS branches still TODO` since the 2026-06-14 AGNOS breakout, with the roadmap simultaneously declaring those targets excluded — the code said "planned", the plan said "no". The code was right: the stdlib has since grown the macOS and Windows peers dig was waiting on, so the reason for the exclusion has expired.

The 0.3.6 audit found the deferral is not merely a missing feature — **dig's build succeeds on targets it cannot actually run**, which is the more urgent half:

- [x] **`--aarch64` produced a wrong binary and reported OK — FIXED in 0.3.7.** `src/platform_linux.cyr` hardcoded an x86_64 syscall table (`_LX_SYS_*`) while `platform.cyr` selects the Linux backend for *every* non-AGNOS target. On aarch64 those numbers mean unrelated calls — `read` 0 is `io_setup`, `close` 3 is `io_submit`, `sendto` 44 is `fstatfs`, and `nanosleep` **35 is `unlinkat`**, which the retry backoff invoked on every retry. Verified rather than reasoned: the 0.3.6 aarch64 build answers "no servers could be reached" under `qemu-aarch64`; the 0.3.7 build resolves.

  Repaired by moving to the stdlib's arch-dispatched wrappers. **One correction to the original diagnosis**, worth recording because it shaped the fix: `SYS_SENDTO` / `SYS_NANOSLEEP` / `SYS_CLOCK_GETTIME` do **not** exist as per-arch constants — the stdlib names none of the three, on either arch. `sendto` was avoided entirely by switching to connect-then-write (taar's pattern, which also closes an off-path spoofing hole); `clock_gettime` and `nanosleep` remain arch-guarded literals in dig. **That stdlib gap is worth filing upstream against cyrius** — every consumer that needs a monotonic clock or a sleep on Linux currently has to hardcode, and `lib/chrono.cyr` itself hardcodes x86_64's 228, so the toolchain has the same latent bug dig just fixed.
- [ ] **`--win` warns `undefined function 'sys_recvfrom'` / `'sys_openat'` and still exits OK** (still true at 0.3.7 — only the aarch64 half was in scope for that cut). Decide the contract: either `src/platform_windows.cyr` implements the nine-function `platform_*` surface over Winsock, or the build refuses the target outright. Silently emitting an unusable binary is the one option to rule out.
- [ ] `src/platform_macos.cyr` — the nine-function surface over the BSD socket syscalls. Check first whether `lib/syscalls_macos.cyr` actually exposes `socket`/`sendto`/`recvfrom`; at the 6.5.35 snapshot it does **not**, so this is gated on a cyrius-side addition and should be filed there rather than worked around locally.
- [ ] Add the buildable targets to CI. The 0.3.6 sweep found nothing in `.github/workflows/ci.yml` compiles any target but host x86_64 — the AGNOS arm is a headline feature and CI has never built it. Every target dig claims should be compiled in CI, and the ones with executable coverage should be run.
- [ ] Only once a target builds *and* runs should it be claimed in README's feature table.

**Sequencing note**: the aarch64 repair is 0.3.7 because it is a live wrong-syscall bug on a target the toolchain will happily build today. The macOS and Windows branches are genuine ports and stay here.

---

Ship 1.0 when all of these are true. Pre-1.0 minor cycles can land partial subsets; the v1.0 tag is the all-of-these gate.

- [ ] **Feature parity with BIND `dig`**: A / AAAA / MX / TXT / NS / CNAME / SOA / SRV / PTR / DNSKEY / RRSIG / DS / NSEC / NSEC3, `+short` / `+trace` / `+tcp` / `+dnssec` / `+timeout` / `+retry`, IPv4 + IPv6 transport, EDNS(0).
- [ ] **`taar` extracted** as a separate repo — STARTED (taar **0.5.0**; `dig` depends on it via `[deps.taar]`; the `ipv4` codec is lifted out, not vendored). Remaining for v1.0: dig's `dns`/socket primitives also live in `taar` rather than locally — see the 0.6.x note above on why this is now a migration decision rather than an extraction.
- [ ] **LAN-on-iron validated** on archaemenid against the home gateway resolver (`192.168.1.1`) and at least one public resolver (`8.8.8.8`, `1.1.1.1`).
- [x] **QEMU validated** via agnos's `scripts/net-tool-smoke.sh` — boots a kernel with dig in the initrd, queries SLIRP's built-in DNS at `10.0.2.3` for `example.com`, asserts an A-record comes back. (This criterion named a `scripts/qemu-smoke.sh` that has never existed in this repo; the gate is real and green, it just lives in agnos. Corrected 0.3.7.)
- [ ] **No POSIX `socket()`** on the **AGNOS backend** of `dig` or `taar` — already true for both, and re-verified at 0.3.7. The blanket "anywhere in dig or taar" reading was never the actual rule: `src/platform_linux.cyr` is the deliberate pragmatic-POSIX arm and the per-backend posture is what CLAUDE.md and state.md have always said. What v1.0 gates is that the AGNOS arm stays sovereign. Sovereign kernel primitives only, there. Audit pass per [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md#security-hardening-required-before-every-release).
- [ ] **Tests**: `tests/dig.tcyr` via `cyrius test` — the ≥ 40-assertion floor is long cleared (**102** at 0.3.7), so what remains is coverage, not count: every RR-type parse path and EDNS(0) edge cases are still untested. (This criterion named a `scripts/test.sh` that has never existed; corrected 0.3.7.) `tests/dig.fcyr` fuzz harness for the response-frame parser (the security-critical path — DNS responses are the classic supply-chain compromise vector). `tests/dig.bcyr` benchmark vs BIND's `dig`.
- [ ] **Docs**: ADR for the resolver-discovery decision (`/etc/resolv.conf` vs hardcoded fallback vs runtime config) — the material now exists and is scattered across `src/platform_agnos.cyr`'s header and three CHANGELOG entries (0.3.5 kernel-leased preference, 0.3.6 wrapper move, 0.3.7 hardening); it needs writing down, not deciding. Architecture note for the name-compression cycle-detection invariant **and** the RFC 5452 reply-acceptance chain added at 0.3.7 (ID + QR + question + connected socket — four checks whose interaction is the actual security property). Guide for the DNSSEC trust-anchor workflow. `docs/adr/` and `docs/architecture/` are both still empty placeholders.
- [ ] **CI green**: `.github/workflows/{ci,release}.yml` both green on the v1.0 candidate commit. Release workflow auto-uploads `build/dig` to the GitHub release.
- [ ] **CI builds every target dig claims.** Today it compiles host x86_64 only — the AGNOS arm is a headline feature that CI has never built, and the aarch64 defect 0.3.7 fixed would have been caught years earlier by a build job. taar added exactly this gate at its 0.5.0. See § 0.7.x.

---

## Out of scope (for v1.0)

Deliberate exclusions — keeps future contributors from adding to v1.0 by accident.

- **Authoritative-server mode** — `dig` is a resolver client, not a server. The AGNOS authoritative-DNS-server, if/when it lands, will be a separate repo with its own naming-lane decision.
- **Caching resolver mode** — same lane separation. dig is one-shot query-and-print; the local-caching-resolver concern (Unbound-equivalent) is separate.
- **GUI / TUI front-end** — dig is CLI-only.

---

## Cross-references

- **Substrate (extracted via dig)**: [taar — scaffolded 2026-06-15, now 0.5.0; dig consumes it (ipv4 module only)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Sibling tools**: [yo — 0.6.0, consumes taar](https://github.com/MacCracken/yo), [whirl — 0.6.13 shipping, the third taar consumer](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Iron dependency**: [agnos r8169 RX-path 5-part bundle](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — **cleared** (r8169 RX solved 2026-05-25, 1.32.7, iron-validated). The LAN-on-iron path is unblocked; what remains is the actual archaemenid dig run.
- **Kernel-growth posture**: AGNOS `state.md` + memory [[project_agnos_kernel_growth_rules]].
- **Naming lane**: English-wordplay / trickster lane (cultural-reference path: Cyrus from The Warriors → Cyrius the language) per [[feedback_naming_lanes]] memory. Family: cmdrs, bnrmr, iam, hapi, kii, yo, **dig**, whirl.
