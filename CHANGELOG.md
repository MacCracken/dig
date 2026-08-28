# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- **`README.md` made four claims the tree contradicts at 0.3.6.** All four were
  documentation-only; no source changed.
  - The `## What it does` block showed a worked `dig +trace google.com` session
    with root → TLD → auth → final output. `+trace` is a 0.4.x backlog item and
    `src/cli.cyr` has no case for it — it falls through to the soft-accept arm,
    so that command silently runs an ordinary A query. The fake transcript is
    gone, replaced by an explicit *planned, not implemented* note pointing at
    the roadmap. The `+trace +tcp +dnssec` ergonomics example went with it.
  - "RFC 1035 + RFC 3596 (AAAA) + RFC 2782 (SRV) + RFC 4034 (DNSSEC
    RRSIG/DNSKEY) all parsed in Cyrius" overstated by one RFC. DNSSEC rdata is
    not parsed and no chain is validated; `RRSIG` / `DNSKEY` / `DS` / `NSEC`
    exist only as type-code constants in `src/dns.cyr` and mnemonics in
    `output_type_str`. The RFC 4034 clause is dropped and the gap stated.
  - "No POSIX `socket()` — kernel exposes a sovereign `udp_send` / `udp_recv` /
    `tcp_connect` surface" contradicted the actual rule and the actual code:
    `src/platform_linux.cyr` is the pragmatic-POSIX arm and issues raw
    `socket` / `sendto` / `recvfrom` syscalls by design. Restated as the
    per-backend rule already documented in `docs/development/state.md`
    § *Sovereignty posture* — POSIX on Linux, sovereign primitives on AGNOS,
    no-POSIX enforced at the v1.0 gate on the AGNOS backend only.
  - `## Install` told the reader to run `sh scripts/install.sh`. There is no
    `scripts/` directory in this repo and never has been. The block is deleted;
    the "drop the built binary anywhere on `$PATH`" line was already correct and
    is now the whole section.

### Changed
- **`CLAUDE.md` carried the same no-POSIX overclaim in its Goal section** —
  restated as the per-backend rule, matching the README fix above.
- **`CLAUDE.md`'s "Strategic position" paragraph leaked volatile state.** It
  framed the `taar` extraction as still pending ("dig completion is the
  extraction trigger") when the extraction fired 2026-06-15 at dig 0.3.3 /
  yo 0.5.5, taar is 0.5.0, and whirl 0.6.13 is already the third consumer. Per
  this file's own header rule, that status belongs in
  `docs/development/state.md`; the paragraph is trimmed to the durable
  rationale — extract at the duplication point, not at a version milestone.

### Fixed
- **The three test-harness gates could score PASS with 256 failures.**
  `tests/dig.tcyr`, `tests/dig.bcyr` and `tests/dig.fcyr` each ended with a bare
  `syscall(60, r)` passing the harness result straight out as the process exit
  status. A wait status is only 8 bits, so exactly 256 / 512 / 768 failures
  truncate to 0 and the gate reports PASS — `assert_summary()` returns a raw
  failure *count*, not a boolean, so the count is the exit code. All three now
  clamp any non-zero result to 1 before exiting.

  Latent here (dig has 70 assertions, so 256 is not currently reachable) but
  unsound in principle, and reachable in practice next door: sibling `yo` hit it
  with 365 assertions and fixed it at yo 0.5.9, whose trailer shape this matches
  byte for byte — the two repos are meant to stay structurally identical. cyrius
  fixed the same defect in its own `cyrius init` scaffold template at 6.5.6.

### Changed
- **The test harnesses retire this repo's last raw syscall literals.** The same
  three files now call `sys_exit_group(r)` instead of `syscall(60, r)`. The bare
  literal was x86_64-specific — `SYS_EXIT` is 60 on x86_64 Linux but 93 on
  aarch64 and 0 on AGNOS, so the harnesses would have exited via the wrong
  syscall on any non-x86_64 backend. 0.3.6 retired the last raw literal in
  `src/`; `tests/` had been missed. This is the form `src/main.cyr` and
  `src/test.cyr` already used, and the form the pinned 6.5.35 `cyrius init`
  template emits.

## [0.3.6] — 2026-08-27 (toolchain 6.5.35 + taar 0.5.0; the banner stops lying)

Dependency-and-pin refresh that closes a two-release version-reporting bug and
retires this repo's last raw syscall literal. No DNS behaviour changes.

### Fixed
- **The `; <<>> dig X.Y.Z <<>>` banner had reported `0.3.3` since 0.3.4.**
  `src/output.cyr` carried a hand-maintained `_DIG_VERSION_STR = "0.3.3"` that
  nobody bumped at 0.3.4 or 0.3.5, so both of those releases identified
  themselves as 0.3.3 in every non-`+short` query. Rather than bump the literal
  a third time, the constant now derives from the compiler-injected
  `CYRIUS_PKG_VERSION`, which resolves `[package].version` — itself now
  `${file:VERSION}`. `VERSION` is the single source of truth end to end and the
  class of drift is closed, not patched.

  This needs **cyrius ≥ 6.5.34**: the constant was added at 6.5.21 but resolved
  only in the *entry* file until 6.5.34 fixed include visibility, and
  `output.cyr` is included by `main.cyr`, not the entry. The pin bump below is
  what makes the fix expressible.

### Changed
- **Toolchain pin 6.2.24 → 6.5.35** (`cyrius.cyml [package].cyrius`). Three minor
  lines and ~200 patches, and it is **source-clean**: diffing cyrius's
  `docs/api-surface.snapshot` between the two tags, filtered to the eleven stdlib
  modules dig declares, gives **203 → 233 symbols with zero removals and zero
  arity changes**. Nothing dig calls moved. That matters more than usual now that
  6.5.1 made arity mismatch a hard error rather than a warning.

  Clears the wrapper/manifest drift warning (the installed wrapper was already
  6.5.35) and brings the vendored `lib/` snapshot forward — all 26 stdlib modules
  had been frozen at the 6.2.24 snapshot and now match 6.5.35 byte for byte.
  Aligns dig with the rest of the network-tools family: `taar`, `yo` and `whirl`
  are all on 6.5.35.
- **`[package].version` is now `${file:VERSION}`** instead of a duplicated
  literal — see Fixed above.
- **`platform_dns_server` retires its raw `syscall(61, 3)`.** The wrapper the
  0.3.5 code comment was waiting on has existed since **cyrius 6.2.39** —
  `sys_net_config(field)` plus the named accessors (`sys_net_ip` /
  `sys_net_netmask` / `sys_net_gateway` / `sys_net_dns_server`), which closed the
  agnos issue `2026-06-23-agnos-net-config-syscall-wrapper` this very cohort
  filed. dig was pinned at 6.2.24 and so sat 15 patches below its own fix for two
  months; the pin bump is what makes it reachable, not 6.5.35 itself.
  `src/platform_agnos.cyr` now calls `sys_net_dns_server()` — same syscall, same
  field, no magic number, and the last raw syscall literal on the AGNOS backend
  is gone. This is not merely cosmetic: **on Linux, syscall 61 is `wait4`**, so
  the bare number was one misplaced `#ifdef` away from being a live hazard; the
  agnos-only wrapper contains it. Still requires agnos ≥ 1.45.16.
- **`taar` dep 0.3.1 → 0.5.0.** Matches the pins `yo` and `whirl` already carry;
  taar's own 0.4.0/0.5.0 notes name dig 0.3.5 as the last stale consumer, so this
  closes that out. **The stale tag had been masked locally**: `[deps.taar]`
  carries both `path = "../taar"` and `git`+`tag`, and `path` wins for local dev,
  so every build on this machine was already compiling the sibling checkout's
  0.5.0 bundle while CI — which has no sibling and takes the `git`+`tag` path —
  was building 0.3.1. Local and CI were compiling different taar versions and
  nothing said so. They agree again now (tag `0.5.0` = `450745d`, confirmed
  published and byte-identical to the local `dist/taar.cyr`).
  taar 0.4.0 added DNS-over-TCP with RFC 1035 §4.2.2 truncation fallback and
  0.5.0 split the AGNOS `taar_tcp_recv` timeout-vs-clean-close contract — both
  on taar's own DNS path, which dig does not call. dig still consumes only the
  `ipv4_*` codec, so its behavioural surface is unchanged. The bump does resolve
  a real build wart: taar 0.5.0's bundle calls `sys_net_dns_server()`, absent
  from the 6.2.24 stdlib, so the AGNOS build emitted
  `warning: undefined function 'sys_net_dns_server'`. On 6.5.35 the symbol
  exists and the warning is gone.
- **`src/main.cyr` reformatted by the 6.5.35 formatter** — multi-line call
  arguments reindent 8 → 6 spaces. Mechanical, `cyrius fmt` output at the new
  pin; keeps `cyrius audit`'s fmt dimension green.

### Notes
- Host build, `--agnos` build and **70/70 tests** all green at the new pin. Live
  resolution re-smoked against the systemd-resolved stub (`127.0.0.53`) —
  `example.com` returns A records and the banner now reads `0.3.6`.
- **`CYRIUS_DCE=1` no longer shrinks the image.** At 6.5.35 it NOPs unreachable
  code in place rather than eliminating it: 132,472 bytes either way, against
  state.md's 6.2.x-era claim that it trimmed ~58 KB. The size figures there are
  corrected.
- `cyrius audit` still reports 2 lint warnings (>120-char lines in `main.cyr`
  and `output.cyr`), one untracked `TODO` deferral in `platform.cyr`, and 33
  undocumented public fns. All pre-date this release and are untouched here —
  they are a quality sweep, not a pin bump.


## [0.3.5] — 2026-06-23

### Changed
- **AGNOS resolver discovery prefers the kernel-leased DNS server** (`src/resolv.cyr`
  `resolv_discover` + `src/platform_agnos.cyr` `platform_dns_server`). On agnos,
  `resolv_discover` now calls the new **`net_config(3)`#61** syscall first (the DHCP
  option-6 on-subnet resolver) and uses it when `> 0`, before `/etc/resolv.conf` and
  the `8.8.8.8` fallback. **Only affects bare `dig <host>`** (no `@server`) — the
  explicit `@server` path is unchanged. The off-subnet `8.8.8.8` fallback needs working
  gateway routing the kernel can't guarantee on real iron (the same gap that froze
  `yo`/`whirl` on archaemenid; `resolv_discover` went straight to 8.8.8.8 — the
  `RESOLV_FALLBACK_GATEWAY` 192.168.1.1 constant was documented but unused). Linux's
  `platform_dns_server` returns `0`, so the resolv.conf path is unchanged there. Interim
  raw `syscall(61, 3)`. **Requires agnos ≥ 1.45.16.**
- **`taar` dep 0.3.0 → 0.3.1** — regenerated `dist/taar.cyr` bundle; dig still consumes
  only the `ipv4_*` codec (the new modules DCE out of dig's binary).

## [0.3.4] — 2026-06-19 (toolchain 6.2.24 + taar 0.3.0)

### Changed
- **Toolchain pin 6.2.6 → 6.2.24** (`cyrius.cyml [package].cyrius`). Resolves the
  wrapper/manifest drift (the installed wrapper was already 6.2.24); CI derives the
  install version straight from the pin.
- **`[deps.taar]` tag 0.1.0 → 0.3.0.** taar grew its `socket` + `dns` modules at
  0.2.0/0.3.0 (the `whirl` extraction) and gained the AGNOS `#ifdef` socket backend.
  dig still consumes only the `ipv4` codec from the bundle — the added `taar_*`
  socket/dns symbols compile in but are unreachable (DCE-eliminable), so the binary
  surface is unchanged.

### Notes
- Host + `--agnos` both build clean; **70/70 tests** green. Pure dep/pin bump — no
  source change, so the 0.3.2 end-to-end resolution result stands.

## [0.3.3] — 2026-06-15 (fold onto taar — IPv4 codec extracted)

### Changed
- **`src/ipv4.cyr` removed; folds onto `taar` 0.1.0.** dig and `yo` shipped a
  byte-identical IPv4 codec — the documented extraction trigger. The parser +
  `ipv4_format_to_buf` now live in `taar/src/ipv4.cyr`; dig pulls them via
  `[deps.taar]` (`path = "../taar"` for local dev, `git`+`tag` published
  fallback) and `include "lib/taar.cyr"` in `src/main.cyr`. No behavior change
  — `ipv4` is pure code (no syscalls), so the AGNOS backend
  (`platform_agnos.cyr`) is unaffected.

### Notes
- Host + `--agnos` both build clean; **70/70 tests** green (the suite now
  exercises `ipv4` through the taar bundle). Pure-code refactor — no QEMU
  re-smoke needed; the 0.3.2 end-to-end resolution result stands.

## [0.3.2] — 2026-06-14 (pin → 6.2.6; drop the chrono workaround)

### Changed
- **Toolchain pin 6.2.5 → 6.2.6.** cyrius 6.2.6 bound chrono's agnos monotonic clock + sleep to the real kernel
  syscalls and added `sys_uptime_ms`(#40) / `sys_sleep_ms`(#41) peer wrappers (the fix for the gap `dig`/`yo`
  surfaced — cyrius issue `2026-06-14-chrono-agnos-monotonic-sleep-stale-stubs.md`).
- **`src/platform_agnos.cyr` drops the direct `syscall(40)/(41)` workaround** → uses the `sys_uptime_ms`/
  `sys_sleep_ms` wrappers. Still validated end-to-end (`agnos/scripts/net-tool-smoke.sh` 2/2 — dig resolves
  `example.com` over the #51-54 UDP syscalls in ring 3, with the chrono fix now in the path).
- Dropped the regenerated stale `lib/` again (a 6.2.5-era vendored snapshot was shadowing the 6.2.6 stdlib —
  that's why the new wrappers looked "undefined"); the build uses the version-pinned snapshot.

## [0.3.1] — 2026-06-14 (AGNOS breakout — dig builds for the sovereign kernel)

### Added
- **`src/platform_agnos.cyr` — the AGNOS backend.** Replaces the POSIX `socket()` path with the sovereign ring-3
  syscalls via the `CYRIUS_TARGET_AGNOS` peer (cyrius ≥ 6.2.3): UDP over `udp_bind`/`send`/`recv`/`unbind`
  (#51-54), DNS query IDs from `getrandom` (#45), `/etc/resolv.conf` via the FS `open`/`read`/`close` syscalls,
  and timing via `uptime_ms`(#40) / `sleep_ms`(#41) called directly. Two model bridges: AGNOS UDP is listener-id
  based (open binds an ephemeral source port, returns the listener_id as the fd; send packs `(src<<16)|dst`), and
  AGNOS `udp_recv` is non-blocking (the backend polls it against an `uptime_ms` deadline since there's no
  `SO_RCVTIMEO` analog). `src/platform.cyr` now dispatches `#ifdef CYRIUS_TARGET_AGNOS`. **dig now builds for
  AGNOS** (`cyrius build --agnos`).

### Changed
- **Toolchain pin 6.0.1 → 6.2.5** (the cyrius release carrying the AGNOS net peer).
- **Dropped the stale committed `lib/`** (an 81-file vendored stdlib snapshot from the 6.0.1 era that shadowed the
  6.2.5 snapshot — the reference tools `owl`/`kriya`/`agnoshi` don't vendor `lib/` at all). dig now uses the
  version-pinned stdlib snapshot.

### Notes
- Known cyrius-side gap worked around: chrono's agnos `clock_now_ms`/`sleep_ms` are stale stubs (return 0 / no-op)
  — the backend calls `uptime_ms`#40 / `sleep_ms`#41 directly until chrono's agnos branch binds them.

## [0.3.0] — 2026-05-23

### Added
- **dig MVP — first end-to-end DNS resolution.** Issues real UDP queries against arbitrary resolvers; parses A / AAAA / MX / NS / CNAME / SOA / PTR / TXT / SRV responses; prints BIND-shape and `+short` output.
- `src/cli.cyr` — BIND-shape arg parser: `@server`, positional name/type, `+flag` options (`+short` / `+noshort` / `+tcp` / `+notcp` / `+timeout=N` / `+retry=N` / `+nodnssec` / `+dnssec`), `-h` / `--help`.
- `src/dns.cyr` — RFC 1035 query construction + response parsing. Name compression decoder (§4.1.4) with **cycle-detection guard** (hop budget + must-point-backward) — malicious responses can't lock the parser.
- `src/ipv4.cyr` — strict dotted-quad parser + formatter (ports yo's `ipv4_parse` verbatim; the duplication is the extraction signal for `taar`).
- `src/resolv.cyr` — `/etc/resolv.conf` parser; fallback chain to `8.8.8.8` when no nameserver line is found.
- `src/platform.cyr` + `src/platform_linux.cyr` — UDP send/recv, SO_RCVTIMEO, monotonic clock, `/dev/urandom` for RFC 5452 query-ID randomness. Follows yo's per-backend sovereignty rule: pragmatic POSIX `socket()` on Linux; AGNOS backend will use sovereign kernel primitives at v1.0 gate.
- `src/query.cyr` — send/recv orchestration with retry on timeout. Validates the response ID echoes (off-path injection mitigation) and the QR bit is set.
- `src/output.cyr` — BIND-shape printing: `; <<>> dig X.Y.Z <<>> name` header, `;; ->>HEADER<<-` status line, `;; QUESTION` / `;; ANSWER` sections, `;; Query time: N ms · server: X · proto: udp` footer. Per-type rdata formatting for all nine roadmap RR types. Surfaces `;; WARNING: response truncated (TC=1)` on oversize UDP responses.
- `tests/dig.tcyr` — 70 assertions: ipv4 parse, query construction byte layout, name encode/decode, **name-compression cycle detection** (self-pointer, forward-pointer, OOB-pointer all rejected), header accessors, resolv.conf line parsing, RR parsing, TC-bit detection.

### Changed
- `cyrius.cyml [package].version` → `0.3.0`. `[deps].stdlib` gains `args` + `flags`.
- `src/main.cyr` is now the wiring layer (was a stub `hello from dig` print at 0.1.0).

### Notes
- 0.2.x kernel UDP-53 syscall exposure was blocked at the time on the agnos r8169 RX-path. (Since cleared: r8169 RX solved 2026-05-25 / 1.32.7; UDP-53 `udp_bind`#51–`udp_unbind`#54 landed agnos 1.45.3.) Took yo's per-backend route to keep momentum — Linux backend is pragmatic POSIX today, AGNOS backend reaches no-POSIX at v1.0 gate.
- TCP transport (`+tcp` flag) accepted but no-op for 0.3.x — full TCP handling lands at 0.4.x alongside EDNS(0). Truncated responses currently surface a warning + empty answer rather than auto-retrying.

## [0.1.0]

### Added
- Initial project scaffold
