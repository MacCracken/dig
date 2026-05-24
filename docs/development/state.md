# dig — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-05-23 (0.3.0 MVP cut).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.3.0** (MVP — first end-to-end resolution) |
| Status | MVP shipping. Real DNS queries fly against arbitrary resolvers; 9 RR types parse. |
| Build size | ~103 KB (8 modules wired; DCE-disabled — `CYRIUS_DCE=1` trims ~58 KB unreachable stdlib) |
| Module footprint | 8 src/ modules, 1410 lines (cli 278, dns 327, output 232, main 165, platform_linux 130, resolv 124, query 71, ipv4 59, platform 13) |
| Cyrius pin | 6.0.1 |
| Tests | 70 assertions in `tests/dig.tcyr` covering ipv4, query construction byte layout, name encode/decode, **name-compression cycle detection** (security-critical), header accessors, resolv.conf parsing, RR parsing, TC-bit detection |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | Second entry in network-tools family (after yo) — **`taar` extraction trigger pending dig 1.0** |

## In-flight work

0.3.x MVP landed 2026-05-23. Real DNS queries verified live against `8.8.8.8`, `1.1.1.1`, and `/etc/resolv.conf`-discovered local resolvers (systemd-resolved at `127.0.0.53`). Per-type rdata formatting verified end-to-end for A / AAAA / MX / NS / CNAME / SOA / PTR / SRV (TXT bounces off the 512-byte UDP cap until `+tcp` lands at 0.4.x — TC=1 warning surfaces in the meantime).

Next bite per `roadmap.md`: **0.4.x — full RR-type coverage + advanced flags**. TCP fallback on TC=1, EDNS(0) (4096-byte UDP buffers + DO bit), `+trace` recursive walk from root, DNSSEC validation primitives (RRSIG/DNSKEY/DS/NSEC/NSEC3 parse + chain validation). IPv6 transport once the platform layer grows AAAA-sockaddr.

## Dependencies (current — `cyrius.cyml [deps].stdlib`)

```
string fmt alloc io vec str syscalls assert bench args flags
```

`args` + `flags` added at 0.3.0 (CLI parsing). Will grow:

- **0.4.x**: + DNSSEC validation primitives (RRSIG / DNSKEY / DS / NSEC / NSEC3), EDNS(0) OPT pseudo-RR handling. May vendor a chunk of `sigil` for the crypto primitives or add it as an explicit dep.
- **0.6.x**: **`taar` extraction trigger fires.** Network primitives (`src/dns.cyr`, `src/ipv4.cyr`, `src/platform_linux.cyr` UDP/TCP surface, `src/resolv.cyr`) move OUT of `dig` INTO the new `taar` repo. `cyrius.cyml [deps]` gains `taar = { path = "../taar" }` or registry equivalent. yo + dig + whirl all consume taar from there forward.

## Sovereignty posture (per-backend rule)

Same posture as yo: pragmatic POSIX `socket()` on the Linux backend today; AGNOS backend will use sovereign `udp_send` / `udp_recv` kernel primitives once roadmap § 0.2.x lands (kernel UDP-53 syscall exposure, blocked on agnos r8169 RX-path Attempt 97). The v1.0 release gate enforces **no-POSIX on the AGNOS backend only**. This keeps dig moving while iron-validation is blocked, instead of freezing the whole resolver behind a hardware-driver dependency.

## Sibling repos

- **yo** — 0.3.0 shipping. ICMP echo probe. First entry in the family. Same per-backend sovereignty posture.
- **whirl** — planned, NOT yet scaffolded. HTTP/HTTPS transfer (curl + wget equivalent). Arrives after the taar extraction triggered by dig completion.
- **taar** — planned, NOT yet scaffolded. Network-probe substrate library. **dig is the extraction-trigger consumer** — the duplication friction between yo (ICMP + UDP for resolv.conf reads) and dig (DNS + UDP/TCP-53 sockets) shapes taar's API honestly. dig 0.3.x already shows what duplicates: `ipv4_parse` is verbatim across both; `platform_linux.cyr` UDP primitives differ only in which port/protocol constants are used.

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| AGNOS-backend sovereign UDP path | r8169 RX-path 5-part bundle iron-validating | agnos (Attempt 97 pending) |
| `taar` substrate extraction | dig 1.0 completion (dig IS the extraction trigger) | dig + future taar repo |
| LAN-on-iron validation | Kernel UDP/TCP syscall exposure + r8169 iron-clear | agnos + dig |
| QEMU + SLIRP DNS validation | Kernel UDP syscall exposure | agnos + dig |

## Consumers

None yet. dig IS a leaf consumer of the kernel; once it ships, `whirl` will eventually consume `taar.dns` (extracted from dig) for hostname resolution.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- [agnosticos r8169-rx-path-audit.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — the iron dependency
- [agnosticos shared-crates.md § dig + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate-extraction plan
- [agnosticos memory: tools-stable ideas](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/project_tools_stable_ideas.md) — original brainstorm + revised extraction ordering
