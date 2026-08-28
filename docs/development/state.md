# dig — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-08-28 (0.3.7 — P-1 audit/hardening sweep).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.3.7** (MVP line; P-1 audit + hardening cut) |
| Status | MVP shipping. Real DNS queries fly against arbitrary resolvers; 9 RR types parse. |
| Build size | 159 KB host (163,016 B), 159 KB `--agnos` (162,872 B) — up ~30 KB at 0.3.7 from the cmdit bundle, which DCE at 6.5.35 NOPs in place rather than removing |
| Module footprint | 9 src/ modules, 1767 lines (dns 400, cli 337, output 243, main 199, platform_linux 196, resolv 131, platform_agnos 128, query 109, platform 24) — excludes the 14-line `test.cyr` entry. Growth at 0.3.7 is doc comments + the hardening guards, not new features |
| Cyrius pin | 6.5.35 (family-wide — `taar`, `yo` and `whirl` match) |
| taar dep | `[deps.taar]` tag **0.5.0** (`dist/taar.cyr`) — dig consumes the `ipv4_*` codec only; taar's socket/dns modules ride along unreachable |
| cmdit dep | `[deps.cmdit]` tag **1.2.4** (`dist/cmdit.cyr`) — adopted 0.3.7 for `--help`/`--version`/argv-materialize/exit codes. The `@server`/`+flag` tokenizer stays in `src/cli.cyr`: dig's grammar is not getopt-long, and cmdit names dig as its `cmdit_raw_argv` escape-hatch case |
| Quality gates | `cyrius audit` green on all four dimensions (fmt / lint / docs / tests) as of 0.3.7 — first time |
| Tests | **128** assertions in `tests/dig.tcyr` (70 → 128 at 0.3.7) covering ipv4, query construction byte layout, name encode/decode, **name-compression cycle detection**, **RFC 5452 §9.1 question matching** and **presentation escaping** (all security-critical), header accessors, resolv.conf parsing, RR parsing, TC-bit detection, **RFC 1035 §5.1 presentation escaping**, CLI bounds clamping, unknown-type rejection. Every 0.3.7 repair is mutation-checked |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | Second entry in network-tools family (after yo) — **`taar` extraction trigger FIRED 2026-06-15** (shared `ipv4` codec folded at dig 0.3.3 / yo 0.5.5) |

## In-flight work

0.3.x MVP landed 2026-05-23. Real DNS queries verified live against `8.8.8.8`, `1.1.1.1`, and `/etc/resolv.conf`-discovered local resolvers (systemd-resolved at `127.0.0.53`). Per-type rdata formatting verified end-to-end for A / AAAA / MX / NS / CNAME / SOA / PTR / SRV (TXT bounces off the 512-byte UDP cap until `+tcp` lands at 0.4.x — TC=1 warning surfaces in the meantime).

**0.3.7 (2026-08-28) was an audit/hardening cut, not a feature cut.** It found that `--aarch64` had been building a binary that called the wrong syscalls entirely (`platform_linux.cyr` hardcoded an x86_64 table while `platform.cyr` routes every non-AGNOS target through it — `nanosleep` 35 is `unlinkat` on aarch64), that `+timeout=0` hung the process forever, and that three classes of reply dig should have dropped were reaching the user. See CHANGELOG [0.3.7]. All repaired and mutation-checked.

Next bite per `roadmap.md`: **0.4.x — full RR-type coverage + advanced flags**. TCP fallback on TC=1, EDNS(0) (4096-byte UDP buffers + DO bit), `+trace` recursive walk from root, DNSSEC validation primitives (RRSIG/DNSKEY/DS/NSEC/NSEC3 parse + chain validation). IPv6 transport once the platform layer grows AAAA-sockaddr.

## Dependencies (current — `cyrius.cyml [deps].stdlib`)

```
string fmt alloc io vec str syscalls assert bench args
```

Plus two first-party distlib deps: **`taar` 0.5.0** (ipv4 codec) and **`cmdit` 1.2.4** (CLI scaffolding, adopted 0.3.7).

`flags` was **dropped at 0.3.7**: declared at 0.3.0 for "CLI parsing" and never referenced by a single line of dig — `cli.cyr` was hand-rolled precisely because `lib/flags.cyr`'s `--long` grammar does not fit BIND's `@server`/`+flag` shape. `args` stays because cmdit calls it. Will grow:

- **0.4.x**: + DNSSEC validation primitives (RRSIG / DNSKEY / DS / NSEC / NSEC3), EDNS(0) OPT pseudo-RR handling. May vendor a chunk of `sigil` for the crypto primitives or add it as an explicit dep.
- **0.6.x**: **`taar` extraction — dig's share is DONE; the rest went a different way.** The trigger fired 2026-06-15, ahead of the 0.6.x slot, and the shared **`ipv4` codec moved OUT** of `dig` into `taar` (consumed via `cyrius.cyml [deps.taar]` → `dist/taar.cyr`). taar has since reached **0.5.0** with `socket` (UDP + TCP) and `dns` modules — but those arrived on **whirl's** pull, written in taar, not lifted out of dig. So the once-planned fold of `src/dns.cyr` / `src/resolv.cyr` / the `platform_*` socket surface into taar has **not** happened and is no longer automatic: dig would now be *migrating onto* taar's independent implementations rather than donating its own. Worth deciding deliberately at 0.4.x, when `+tcp` lands and taar 0.4.0's TC-fallback path becomes the obvious alternative to writing dig's own. All three consumers (yo, dig, whirl) pin taar 0.5.0.

## Sovereignty posture (per-backend rule)

Same posture as yo: pragmatic POSIX `socket()` on the Linux backend; the AGNOS backend (`src/platform_agnos.cyr`) uses the sovereign `udp_bind`/`udp_send`/`udp_recv`/`udp_unbind` kernel primitives (#51-54, landed agnos 1.45.3, via the cyrius ≥ 6.2.6 peer) and resolves real names end-to-end on agnos. The v1.0 release gate enforces **no-POSIX on the AGNOS backend only**. (Both the roadmap § 0.2.x kernel-exposure block and the r8169 RX dependency are cleared — r8169 RX solved 2026-05-25.)

**Neither backend hardcodes an arch-specific syscall table** as of 0.3.7. `platform_linux.cyr`'s private `_LX_SYS_*` table — x86_64 numbers used on every non-AGNOS target, including aarch64 — is gone in favour of the stdlib's arch-dispatched wrappers. Two calls (`clock_gettime`, `nanosleep`) have no wrapper and no named constant anywhere in the stdlib and remain arch-guarded literals; that gap is worth filing upstream.

**No raw syscall literals remain on the AGNOS backend** as of 0.3.6. The last one — `syscall(61, 3)` for the DHCP-leased resolver — became `sys_net_dns_server()` when cyrius 6.5.35 shipped the `sys_net_config` peer wrappers. Every AGNOS-side call now goes through a named stdlib wrapper. `src/platform_linux.cyr` still uses raw numbered syscalls by design: that is the pragmatic-POSIX arm, and the sovereignty gate does not cover it.

## Sibling repos

- **yo** — **0.6.0** shipping. ICMP echo probe. First entry in the family. Same per-backend sovereignty posture. On cyrius 6.5.35 + taar 0.5.0.
- **whirl** — **0.6.13 shipping** (no longer "planned": 11 src/ modules incl. `http`, `transport`, `crawl`, `links`). HTTP/HTTPS transfer, curl + wget equivalent. The third taar consumer, and the one that drove taar's TCP surface — its `transport.cyr` composes `taar_resolve_ipv4` + taar's TCP helpers, with TLS coming from cyrius's `tls_native` rather than a taar module. On cyrius 6.5.35 + taar 0.5.0.
- **taar** — **0.5.0.** Network-probe substrate library; three bundled modules (`src/ipv4.cyr`, `src/socket.cyr`, `src/dns.cyr` → `dist/taar.cyr`). The yo/dig duplication was the trigger: their byte-identical `ipv4` codec was the first module lifted in. `socket` (UDP **and** TCP) and `dns` followed on whirl's pull. `icmp` and `tls`/`http` stay parked pending a second consumer. All three consumers (yo, dig, whirl) now pin 0.5.0.

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| AGNOS-backend sovereign UDP path | ✅ done — UDP #51-54 landed agnos 1.45.3; r8169 RX solved 2026-05-25; `src/platform_agnos.cyr` resolves end-to-end | agnos + dig |
| `taar` substrate extraction | ✅ fired 2026-06-15 — `ipv4` lifted into taar (dig 0.3.3 + yo 0.5.5). taar is now 0.5.0 with its own `socket`/`dns`; dig's remaining fold is a **migration decision**, not a pending extraction — see Dependencies § 0.6.x | dig + yo + taar |
| LAN-on-iron validation | syscall exposure + r8169 both cleared; remaining = the actual archaemenid run | dig (iron run) |
| QEMU + SLIRP DNS validation | ✅ done — agnos `net-tool-smoke.sh` resolves `example.com` via SLIRP 10.0.2.3 | agnos + dig |

## Consumers

None. dig IS a leaf consumer of the kernel. The once-anticipated dig→whirl hand-off did **not** happen the way it was planned: `whirl` 0.6.13 resolves hostnames through `taar`'s own `dns` module (which arrived via whirl's pull, not by extraction from dig), so dig's `src/dns.cyr` was never lifted. dig remains the only consumer of its own DNS code.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- [agnosticos r8169-rx-path-audit.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — the iron dependency
- [agnosticos shared-crates.md § dig + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate-extraction plan
- [agnosticos memory: tools-stable ideas](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/project_tools_stable_ideas.md) — original brainstorm + revised extraction ordering
