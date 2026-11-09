# dig — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-11-08 (0.5.1 — toolchain 6.7.18, cmdit 1.5.1, taar 0.6.2).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.5.1** (toolchain 6.7.18, cmdit 1.5.1, taar 0.6.2; no dig source change. 0.4.0 remains the last feature cut) |
| Status | Shipping. Real DNS queries against arbitrary resolvers over **UDP and TCP**, EDNS(0) advertised by default; 9 RR types parse. |
| Build size | 235 KB host (241,056 B), 252 KB `--agnos` (257,904 B), 331 KB `--aarch64` (339,280 B) at 6.7.18. The live image is 97,696 B under `CYRIUS_DCE=1`; the rest is unreachable stdlib and dep code (588 fns), which the DCE pass drops. aarch64's text segment is just past 256 KiB (`0x40208`), so its data segment sits at the next 64 KiB file offset: about 64 KiB of that file is alignment padding |
| Module footprint | 9 src/ modules, 2242 lines (output 507, dns 459, cli 330, main 253, platform_linux 179, resolv 174, platform_agnos 167, query 149, platform 24) — excludes the 14-line `test.cyr` entry. Growth across 0.3.7/0.3.8 is doc comments, validation guards and RFC 5952 rendering, not features |
| Cyrius pin | 6.7.18, the latest release. taar 0.6.2, cmdit 1.5.1 and yo 0.8.0 match; whirl 0.6.14 is still on 6.6.2 |
| taar dep | `[deps.taar]` tag **0.6.2** (`dist/taar.cyr`, commit-pinned `d203629`), the latest release. dig consumes the `ipv4_*` codec and, since 0.4.0, the TCP primitives in `src/tcp.cyr`. Since 0.6.2 `taar_tcp_set_timeout_ms` also bounds connect and send, so `+tcp` to a SYN black hole gives up at `+timeout` (2.0 s at `+timeout=2`, was 135 s). `path = "../taar"` is a local-mode-only override (cyrius ≥ 6.7.6: `CYRIUS_LOCAL=1` or `--local`), so a plain build resolves the same tag CI does |
| Transport | UDP-53 via dig's own `platform_*` arms; **TCP-53 via taar's socket primitives** (`src/tcp.cyr`) — taar ships both a POSIX and an AGNOS arm, so TCP works on AGNOS without touching the parked `platform_agnos.cyr`. taar's *DNS* layer is deliberately not adopted |
| cmdit dep | `[deps.cmdit]` tag **1.5.1** (`dist/cmdit.cyr`, commit-pinned `efffc54`, the latest release; `path` is local-mode-only, as for taar) — adopted 0.3.7 for `--help`/`--version`/argv-materialize/exit codes. The `@server`/`+flag` tokenizer stays in `src/cli.cyr`: dig's grammar is not getopt-long, and cmdit names dig as its `cmdit_raw_argv` escape-hatch case |
| Quality gates | `cyrius audit`: fmt clean, tests green. Lint reports 5 warnings (consecutive blank lines in `tests/dig.tcyr`) and docs reports 11 undocumented public fns, the same counts at 6.6.2, 6.6.20, 6.7.9 and 6.7.18. CI gates on deps/build/test only |
| Tests | **260** assertions in `tests/dig.tcyr`, plus **1,560,376** in the `tests/dig.fcyr` fuzz harness. Security-critical coverage: name-compression cycle detection, RFC 5452 §9.1 question matching and its use, RFC 1035 §5.1 presentation escaping, rdata RDLENGTH bounds, name wire-length caps, EDNS OPT wire layout, TCP length framing. Every repair and feature since 0.3.7 is mutation-checked |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | Second entry in network-tools family (after yo) — **`taar` extraction trigger FIRED 2026-06-15** (shared `ipv4` codec folded at dig 0.3.3 / yo 0.5.5) |

## In-flight work

0.3.x MVP landed 2026-05-23. Real DNS queries verified live against `8.8.8.8`, `1.1.1.1`, and `/etc/resolv.conf`-discovered local resolvers (systemd-resolved at `127.0.0.53`). Per-type rdata formatting verified end-to-end for A / AAAA / MX / NS / CNAME / SOA / PTR / SRV (TXT bounces off the 512-byte UDP cap until `+tcp` lands at 0.4.x — TC=1 warning surfaces in the meantime).

**0.4.0 (2026-08-28) is the first feature cut past the MVP line.** The 0.4.x hold — which had held since 0.3.0, gated on the agnos kernel UDP path settling — was lifted by user direction, and 0.4.0 took the two items that gate everything after them: EDNS(0) and DNS over TCP. `dig google.com TXT` returns 16 records where it returned none for eight releases.

Before that, **0.3.7 and 0.3.8 were audit cuts.** An eight-lens sweep over 0.3.6 confirmed 61 findings against adversarial refutation (0 refuted); 0.3.7 took both P1s (aarch64 was building binaries that called the wrong syscalls; any zone owner could write raw terminal control bytes to a looker-up's screen) and 0.3.8 closed the remaining 23. That backlog is empty.

Next bite per `roadmap.md`: the rest of **0.4.x** — `+trace` (the recursive walk from root, unblocked by 0.3.8's NOERROR/ANCOUNT=0 exit-0 fix, since every delegation hop is exactly that shape), then the DNSSEC validation ladder (RRSIG/DNSKEY/DS/NSEC/NSEC3 parse + chain validation against the root KSK). IPv6 transport once the platform layer grows an AAAA sockaddr.

## Dependencies (current — `cyrius.cyml [deps].stdlib`)

```
string fmt alloc io vec str syscalls assert bench args
```

Plus two first-party distlib deps: **`taar` 0.6.2** (ipv4 codec + TCP primitives) and **`cmdit` 1.5.1** (CLI scaffolding, adopted 0.3.7). Both are the latest published releases, and both pin cyrius 6.7.18.

`flags` was **dropped at 0.3.7**: declared at 0.3.0 for "CLI parsing" and never referenced by a single line of dig — `cli.cyr` was hand-rolled precisely because `lib/flags.cyr`'s `--long` grammar does not fit BIND's `@server`/`+flag` shape. `args` stays because cmdit calls it. Will grow:

- **0.4.x**: + DNSSEC validation primitives (RRSIG / DNSKEY / DS / NSEC / NSEC3), EDNS(0) OPT pseudo-RR handling. May vendor a chunk of `sigil` for the crypto primitives or add it as an explicit dep.
- **0.6.x**: **`taar` extraction — dig's share is DONE; the rest went a different way.** The trigger fired 2026-06-15, ahead of the 0.6.x slot, and the shared **`ipv4` codec moved OUT** of `dig` into `taar` (consumed via `cyrius.cyml [deps.taar]` → `dist/taar.cyr`). taar has since reached **0.6.2** with `socket` (UDP + TCP) and `dns` modules — but those arrived on **whirl's** pull, written in taar, not lifted out of dig. So the once-planned fold of `src/dns.cyr` / `src/resolv.cyr` / the `platform_*` socket surface into taar has **not** happened and is no longer automatic: dig would now be *migrating onto* taar's independent implementations rather than donating its own. Worth deciding deliberately at 0.4.x, when `+tcp` lands and taar 0.4.0's TC-fallback path becomes the obvious alternative to writing dig's own. The three consumers pin taar 0.6.2 (yo and dig) and 0.5.0 (whirl).

## Sovereignty posture (per-backend rule)

Same posture as yo: pragmatic POSIX `socket()` on the Linux backend; the AGNOS backend (`src/platform_agnos.cyr`) uses the sovereign `udp_bind`/`udp_send`/`udp_recv`/`udp_unbind` kernel primitives (#51-54, landed agnos 1.45.3, via the cyrius ≥ 6.2.6 peer) and resolves real names end-to-end on agnos. The v1.0 release gate enforces **no-POSIX on the AGNOS backend only**. (Both the roadmap § 0.2.x kernel-exposure block and the r8169 RX dependency are cleared — r8169 RX solved 2026-05-25.)

**Neither backend hardcodes an arch-specific syscall table** as of 0.3.7. `platform_linux.cyr`'s private `_LX_SYS_*` table — x86_64 numbers used on every non-AGNOS target, including aarch64 — is gone in favour of the stdlib's arch-dispatched wrappers. Two calls (`clock_gettime`, `nanosleep`) have no wrapper and no named constant anywhere in the stdlib and remain arch-guarded literals; that gap is worth filing upstream.

**No raw syscall literals remain on the AGNOS backend** as of 0.3.6. The last one — `syscall(61, 3)` for the DHCP-leased resolver — became `sys_net_dns_server()` when cyrius 6.5.35 shipped the `sys_net_config` peer wrappers. Every AGNOS-side call now goes through a named stdlib wrapper. `src/platform_linux.cyr` still uses raw numbered syscalls by design: that is the pragmatic-POSIX arm, and the sovereignty gate does not cover it.

## Sibling repos

- **yo** — **0.8.0** shipping. ICMP echo probe. First entry in the family. Same per-backend sovereignty posture. On cyrius 6.7.18 + taar 0.6.2.
- **whirl** — **0.6.14 shipping** (no longer "planned": 11 src/ modules incl. `http`, `transport`, `crawl`, `links`). HTTP/HTTPS transfer, curl + wget equivalent. The third taar consumer, and the one that drove taar's TCP surface — its `transport.cyr` composes `taar_resolve_ipv4` + taar's TCP helpers, with TLS coming from cyrius's `tls_native` rather than a taar module. On cyrius 6.6.2 + taar 0.5.0.
- **taar** — **0.6.2** latest, and what dig pins. Network-probe substrate library; three bundled modules (`src/ipv4.cyr`, `src/socket.cyr`, `src/dns.cyr` → `dist/taar.cyr`). The yo/dig duplication was the trigger: their byte-identical `ipv4` codec was the first module lifted in. `socket` (UDP **and** TCP) and `dns` followed on whirl's pull. `icmp` and `tls`/`http` stay parked pending a second consumer. The consumers no longer share a pin: yo is on 0.6.2, dig on 0.5.2, whirl on 0.5.0.

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| AGNOS-backend sovereign UDP path | ✅ done — UDP #51-54 landed agnos 1.45.3; r8169 RX solved 2026-05-25; `src/platform_agnos.cyr` resolves end-to-end | agnos + dig |
| `taar` substrate extraction | ✅ fired 2026-06-15 — `ipv4` lifted into taar (dig 0.3.3 + yo 0.5.5). taar is now 0.6.2 (dig pins it) with its own `socket`/`dns`; dig's remaining fold is a **migration decision**, not a pending extraction — see Dependencies § 0.6.x | dig + yo + taar |
| LAN-on-iron validation | syscall exposure + r8169 both cleared; remaining = the actual archaemenid run | dig (iron run) |
| QEMU + SLIRP DNS validation | ✅ done — agnos `net-tool-smoke.sh` resolves `example.com` via SLIRP 10.0.2.3 | agnos + dig |

## Consumers

None. dig IS a leaf consumer of the kernel. The once-anticipated dig→whirl hand-off did **not** happen the way it was planned: `whirl` 0.6.14 resolves hostnames through `taar`'s own `dns` module (which arrived via whirl's pull, not by extraction from dig), so dig's `src/dns.cyr` was never lifted. dig remains the only consumer of its own DNS code.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- [agnosticos r8169-rx-path-audit.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — the iron dependency
- [agnosticos shared-crates.md § dig + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate-extraction plan
- [agnosticos memory: tools-stable ideas](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/project_tools_stable_ideas.md) — original brainstorm + revised extraction ordering
