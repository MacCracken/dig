# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
