# dig — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-06-19 (0.3.4 — toolchain 6.2.24 + taar 0.3.0 dep bump).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.3.4** (MVP line; toolchain + taar dep refresh) |
| Status | MVP shipping. Real DNS queries fly against arbitrary resolvers; 9 RR types parse. |
| Build size | ~103 KB (8 modules wired; DCE-disabled — `CYRIUS_DCE=1` trims ~58 KB unreachable stdlib) |
| Module footprint | 8 src/ modules, 1410 lines (cli 278, dns 327, output 232, main 165, platform_linux 130, resolv 124, query 71, ipv4 59, platform 13) |
| Cyrius pin | 6.2.24 |
| taar dep | `[deps.taar]` tag **0.3.0** (`dist/taar.cyr`) — dig consumes the `ipv4` codec; taar's socket/dns modules ride along unreachable |
| Tests | 70 assertions in `tests/dig.tcyr` covering ipv4, query construction byte layout, name encode/decode, **name-compression cycle detection** (security-critical), header accessors, resolv.conf parsing, RR parsing, TC-bit detection |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | Second entry in network-tools family (after yo) — **`taar` extraction trigger FIRED 2026-06-15** (shared `ipv4` codec folded at dig 0.3.3 / yo 0.5.5) |

## In-flight work

0.3.x MVP landed 2026-05-23. Real DNS queries verified live against `8.8.8.8`, `1.1.1.1`, and `/etc/resolv.conf`-discovered local resolvers (systemd-resolved at `127.0.0.53`). Per-type rdata formatting verified end-to-end for A / AAAA / MX / NS / CNAME / SOA / PTR / SRV (TXT bounces off the 512-byte UDP cap until `+tcp` lands at 0.4.x — TC=1 warning surfaces in the meantime).

Next bite per `roadmap.md`: **0.4.x — full RR-type coverage + advanced flags**. TCP fallback on TC=1, EDNS(0) (4096-byte UDP buffers + DO bit), `+trace` recursive walk from root, DNSSEC validation primitives (RRSIG/DNSKEY/DS/NSEC/NSEC3 parse + chain validation). IPv6 transport once the platform layer grows AAAA-sockaddr.

## Dependencies (current — `cyrius.cyml [deps].stdlib`)

```
string fmt alloc io vec str syscalls assert bench args flags
```

`args` + `flags` added at 0.3.0 (CLI parsing). Will grow:

- **0.4.x**: + DNSSEC validation primitives (RRSIG / DNSKEY / DS / NSEC / NSEC3), EDNS(0) OPT pseudo-RR handling. May vendor a chunk of `sigil` for the crypto primitives or add it as an explicit dep.
- **0.6.x**: **`taar` extraction — IN PROGRESS** (trigger fired 2026-06-15, ahead of the 0.6.x slot). `taar` 0.1.0 is scaffolded and the shared **`ipv4` codec already moved OUT** of `dig` into `taar` (consumed via `cyrius.cyml [deps.taar]` → `dist/taar.cyr`). The remaining primitives (`src/dns.cyr`, the `platform_*` UDP/TCP socket surface, `src/resolv.cyr`) fold in incrementally as the per-protocol modules grow. yo + dig consume taar today; whirl joins as the third consumer.

## Sovereignty posture (per-backend rule)

Same posture as yo: pragmatic POSIX `socket()` on the Linux backend; the AGNOS backend (`src/platform_agnos.cyr`) uses the sovereign `udp_bind`/`udp_send`/`udp_recv`/`udp_unbind` kernel primitives (#51-54, landed agnos 1.45.3, via the cyrius ≥ 6.2.6 peer) and resolves real names end-to-end on agnos. The v1.0 release gate enforces **no-POSIX on the AGNOS backend only**. (Both the roadmap § 0.2.x kernel-exposure block and the r8169 RX dependency are cleared — r8169 RX solved 2026-05-25.)

## Sibling repos

- **yo** — 0.3.0 shipping. ICMP echo probe. First entry in the family. Same per-backend sovereignty posture.
- **whirl** — planned, NOT yet scaffolded. HTTP/HTTPS transfer (curl + wget equivalent). The third taar consumer — adds `taar/src/tcp.cyr` + `tls.cyr` + `http.cyr` when it lands (taar itself already exists at 0.1.0).
- **taar** — **0.1.0 scaffolded 2026-06-15.** Network-probe substrate library. The yo/dig duplication was the trigger: their byte-identical `ipv4` codec was the first module lifted into `taar` (ships `dist/taar.cyr`; dig + yo consume it via `[deps.taar]`). Per-protocol modules (`icmp`, `dns`, `socket`) fold in per second-consumer trigger; whirl later adds `tcp`/`tls`/`http`.

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| AGNOS-backend sovereign UDP path | ✅ done — UDP #51-54 landed agnos 1.45.3; r8169 RX solved 2026-05-25; `src/platform_agnos.cyr` resolves end-to-end | agnos + dig |
| `taar` substrate extraction | ✅ fired 2026-06-15 — `ipv4` module lifted into taar 0.1.0 (dig 0.3.3 + yo 0.5.5 consume it); dns/socket modules fold in incrementally | dig + yo + taar |
| LAN-on-iron validation | syscall exposure + r8169 both cleared; remaining = the actual archaemenid run | dig (iron run) |
| QEMU + SLIRP DNS validation | ✅ done — agnos `net-tool-smoke.sh` resolves `example.com` via SLIRP 10.0.2.3 | agnos + dig |

## Consumers

None yet. dig IS a leaf consumer of the kernel; once it ships, `whirl` will eventually consume `taar.dns` (extracted from dig) for hostname resolution.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- [agnosticos r8169-rx-path-audit.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — the iron dependency
- [agnosticos shared-crates.md § dig + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate-extraction plan
- [agnosticos memory: tools-stable ideas](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/project_tools_stable_ideas.md) — original brainstorm + revised extraction ordering
