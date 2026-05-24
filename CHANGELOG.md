# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
- 0.2.x kernel UDP-53 syscall exposure remains blocked on agnos r8169 RX-path Attempt 97. Taking yo's per-backend route to keep momentum — Linux backend is pragmatic POSIX today, AGNOS backend reaches no-POSIX at v1.0 gate.
- TCP transport (`+tcp` flag) accepted but no-op for 0.3.x — full TCP handling lands at 0.4.x alongside EDNS(0). Truncated responses currently surface a warning + empty answer rather than auto-retrying.

## [0.1.0]

### Added
- Initial project scaffold
