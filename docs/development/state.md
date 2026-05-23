# dig — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-05-23 (scaffold cut).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.1.0** (scaffold) |
| Status | Pre-MVP — kernel UDP-53 / TCP-53 syscall exposure pending |
| Build size | ~28 KB (stub `hello from dig`) |
| Cyrius pin | 6.0.1 |
| Tests | 2 assertions in `tests/dig.tcyr` (placeholder smoke) |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | Second entry in network-tools family (after yo) — **`taar` extraction trigger** |

## In-flight work

Nothing landed beyond the scaffold. Next bite per `roadmap.md` § Backlog is **0.2.x — Kernel UDP-53 / TCP-53 syscall exposure**, blocked on the agnos r8169 RX-path 5-part bundle iron-validating (Attempt 97 pending — same dependency yo carries).

## Dependencies (current — `cyrius.cyml [deps].stdlib`)

```
string fmt alloc io vec str syscalls assert bench
```

Stdlib-only at scaffold. Will grow:

- **0.3.x**: + `args`, `flags` (CLI parsing), local DNS framing helpers + UDP-53 socket primitives (vendored from `agnos/kernel/core/net.cyr` patterns until 0.6.x extraction).
- **0.4.x**: + DNSSEC validation primitives (RRSIG / DNSKEY / DS / NSEC / NSEC3), EDNS(0) OPT pseudo-RR handling.
- **0.6.x**: **`taar` extraction trigger fires.** Network primitives move OUT of `dig`'s vendored stdlib INTO the new `taar` repo. `cyrius.cyml [deps]` gains `taar = { path = "../taar" }` or registry equivalent.

## Sibling repos

- **yo** — scaffolded 2026-05-23. ICMP echo probe (ping equivalent). First entry in the family.
- **whirl** — planned, NOT yet scaffolded. HTTP/HTTPS transfer (curl + wget equivalent). Arrives after the taar extraction triggered by dig completion.
- **taar** — planned, NOT yet scaffolded. Network-probe substrate library. **dig is the extraction-trigger consumer** — the duplication friction between yo (ICMP) and dig (DNS + UDP/TCP-53 sockets) shapes taar's API honestly. Per user direction 2026-05-23.

## Kernel coupling

`dig` depends on Cyrius-native userland UDP / TCP primitives in `agnos/kernel/core/net.cyr` (not POSIX `socket()`). The kernel ALREADY has these internally — they drive the DHCP client (UDP) + TCP listen/connect (1.32.0 networking arc). The 0.2.x bite is **exposing them via syscall** to userland. Shape candidates:

- **Direct mapping**: `udp_send(dst_ip, dst_port, payload, len)` / `udp_recv(lid, buf, maxlen, &src_ip, &src_port, timeout) → bytes`; `tcp_connect(dst_ip, dst_port, timeout) → conn_id` + `tcp_send` / `tcp_recv` / `tcp_close`.
- **Decision deferred to actual implementation cycle** — refined per dig's real-world friction, not pre-designed.

Per [[project_agnos_kernel_growth_rules]] — kernel grows for native workloads, narrow surface.

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| Kernel UDP-53 / TCP-53 syscall exposure | r8169 RX-path 5-part bundle iron-validating | agnos (Attempt 97 pending) |
| `taar` substrate extraction | dig MVP completion (dig IS the extraction trigger) | dig + future taar repo |
| LAN-on-iron validation | Kernel UDP/TCP syscall exposure + r8169 iron-clear | agnos + dig |
| QEMU + SLIRP DNS validation | Kernel UDP syscall exposure | agnos + dig |

## Consumers

None yet. dig IS a leaf consumer of the kernel; once it ships, `whirl` will eventually consume `taar.dns` (extracted from dig) for hostname resolution.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- [agnosticos r8169-rx-path-audit.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — the iron dependency
- [agnosticos shared-crates.md § dig + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate-extraction plan
- [agnosticos memory: tools-stable ideas](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/project_tools_stable_ideas.md) — original brainstorm + revised extraction ordering
