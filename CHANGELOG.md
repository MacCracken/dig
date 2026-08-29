# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.3.8] — 2026-08-28 (the rest of the audit: 23 findings closed, and a real fuzz harness)

0.3.7 repaired both P1s the audit found and left 23 P2/P3 items on the roadmap.
This closes them. Same rule as that cut: no new features, every repair has an
assertion behind it, and every assertion is mutation-checked. The suite goes
128 → **198**, and `tests/dig.fcyr` goes from a two-line stub to **1,560,376**
adversarial assertions.

Two of these were found by the tests rather than by the audit — including an
off-by-one in a guard 0.3.8 itself was adding. Both are called out below.

### Fixed
- **`dns_skip_name` accepted names `dns_decode_name` could not render.** The
  walker capped label length and pointer hops but never total name length,
  while the decoder did — so `dns_parse_rr` returned a valid offset for a
  6×63-label owner name that then failed to decode. The visible result: full
  output printed `;; ANSWER` with **zero records under it** and exit 0, while
  `+short` on the identical bytes printed the address. Two modes of one tool
  disagreeing about the same reply, neither reporting a problem. Both walkers
  now count wire octets against RFC 1035 §2.3.4's 255.

  **The cap was initially one octet lax, and the test caught it, not the
  audit.** The accumulator omitted the root label's own byte, so a 256-octet
  name still passed. The case that exposed it is labels 63/63/63/62 — exactly
  256 wire octets but only 254 presentation characters, which is the single
  window where the new wire cap differs from the presentation cap the decoder
  already had. Both accumulators now seed at 1.
- **Rdata-embedded names were bounded by `msg_len`, not RDLENGTH.** Memory-safe
  — `dns_parse_rr` guarantees `rdata + rdlen <= msg_len` — but the name was read
  out of the **next record's** bytes and printed as this record's authoritative
  content, with a success return. Proven on all six name-bearing arms: an `NS`
  with `rdlen=0` rendered a neighbouring name at rc=0. This violated the
  contract written three lines above the accessor in `dns.cyr`. Every arm now
  post-checks the decoded end offset against `rdoff + rdlen`, with `==` rather
  than `<=` because BIND treats unconsumed trailing rdata as FORMERR too.
- **13 rdata validation failures were discarded by both callers.** They returned
  `-1`; the callers printed the trailing newline regardless. So an A record with
  `rdlength=5` emitted an empty rdata field and **exited 0** — under `+short`, a
  bare blank line, meaning `ip=$(dig +short host)` yielded `""` and the caller
  was told it had succeeded. The status now propagates through
  `output_print_short_rr` / `output_print_answer_rr` into a sticky flag and out
  as exit 9, with the warning on **stderr** so it cannot corrupt the `+short`
  stream scripts parse.
- **MX, SRV, SOA and TXT emitted before validating.** MX wrote its preference,
  SRV its priority/weight/port and SOA *both names* before discovering the rdata
  was short, leaving half-rendered records on stdout. All four now validate
  first; TXT needs a two-pass walk, since each segment is only discoverable by
  walking the one before it.
- **`dig . NS` — the canonical way to fetch root hints — could not be run.** The
  root zone hit `dns_encode_name`'s empty-label rejection, which propagated as
  `QRY_BAD` and printed **`dig: malformed response`** with exit 9, blaming the
  resolver for an argv-shaped input having never sent a packet. The encoder now
  accepts `.` as a whole name — keyed on the whole string, not on position, so
  `.example.com` still refuses rather than silently querying the root. Names
  that genuinely cannot be encoded are now rejected up front in `main.cyr` as a
  usage error naming the input, by the same encoder that would put them on the
  wire.
- **NXDOMAIN and NODATA exited 9.** BIND returns 0 for a successful lookup
  including NXDOMAIN, and reserves its non-zero codes for transport failures —
  so `dig @$NS $ZONE >/dev/null || alert "resolver down"` cried wolf on a
  perfectly healthy negative answer, indistinguishable from a dead resolver.
  Worse, `+short` was inconsistent with *itself*: 9 on NXDOMAIN but 0 on NODATA,
  same wire bytes, the difference being only which loop body never ran. A
  well-formed reply that was received and printed is now exit 0 whatever the
  RCODE says; the status is already reported in the `status:` field, which is
  where BIND puts it. 9 is retained for socket failure and timeout, which is
  what it means. This also unblocks `+trace` at 0.4.x — every hop of a
  delegation walk is NOERROR with ANCOUNT=0.
- **`@0.0.0.0` exited 2 with nothing on stdout or stderr.** `ipv4_parse` returns
  packed 0 for it, which is not `< 0`, so the parse succeeded and 0 landed in
  the slot that also meant "no @server given" — the one input that both parses
  and collides. Presence now has its own flag rather than being inferred from
  the value, so `@0.0.0.0` behaves as an ordinary explicit override (Linux
  remaps `INADDR_ANY` to loopback on connect, the historic `resolver(5)`
  semantic).
- **A `nameserver 0.0.0.0` line aborted the whole `/etc/resolv.conf` scan.**
  `resolv_parse` returned on `addr >= 0`, but 0 is its own documented
  "nothing found" sentinel and the caller tests `> 0` — producer and consumer
  disagreed. Proven with a bind-mounted file: `0.0.0.0` followed by `1.1.1.1`
  made dig query **8.8.8.8**; it now queries 1.1.1.1.
- **A CRLF `/etc/resolv.conf` fell through to 8.8.8.8.** The address token
  terminated on space and tab but not CR, so `1.1.1.1\r` failed to parse and the
  line was skipped. Same bind-mount proof: 8.8.8.8 before, 1.1.1.1 after. (CR is
  deliberately *not* added to the blank-skipper — it is not whitespace in the
  `resolver(5)` grammar, and accepting `nameserver\r 1.2.3.4` would make dig
  laxer than glibc and BIND.)
- **A `/etc/resolv.conf` over 4096 bytes was silently truncated**, and a cut
  landing inside the final octet yields a *different valid address* — 10.0.0.53
  read as 10.0.0.5, with nothing anywhere able to detect it, because the bytes
  the parser was handed are well-formed. Buffer grown to 16 KiB.
- **The fallback to a public resolver was completely silent**, and the chain the
  file documented did not exist: the header promised
  `/etc/resolv.conf → 192.168.1.1 → 8.8.8.8` and declared a
  `RESOLV_FALLBACK_GATEWAY` constant, but there was no gateway step and the
  constant had no readers. That was the most safety-relevant claim in the file
  and it was false. The header now describes the real order, the dead constant
  is gone, and every path that ends at the public fallback prints one line on
  **stderr** — the shared backstop for all four resolv.conf defects above, and
  the only signal under `+short`, which returns before the footer that would
  have shown `server: 8.8.8.8`.
- **A single well-timed junk datagram doubled the query deadline.** SO_RCVTIMEO
  was armed once with the whole budget, and the inner loop bounds when a recv
  may *start*, never when it must *end*. Measured: `+timeout=1 +retry=1` went
  1.06s → 1.92s from one packet, shipped defaults 15.3s → 30.7s. Now re-armed to
  the remaining budget before each recv; measured back to 2.06s for
  `+timeout=2 +retry=1`. Note a *flood* never triggered this — the loop
  condition handled that correctly. Precision was the attack.
- **A truncated answer lost its footer and its counts.** On a mid-loop parse
  failure `main` returned before `output_print_footer`, so the user got N valid
  records, one stderr line, no `;; Query time`, exit 9, and no way to tell how
  many records were missing or whether the ones shown were sound. Reachable with
  no lie at all — the 512-byte UDP cap cuts a larger reply mid-record. Both
  loops now break, warn with `N of M`, and fall through to the footer.

### Changed
- **AAAA rendering is RFC 5952.** dig printed eight fixed 4-hex-digit groups, so
  **every** real-world AAAA differed from BIND, not merely ones with zero runs.
  Now §4.1 leading-zero suppression, §4.2.2/§4.2.3 leftmost-longest `::`
  (single zero fields are not collapsed), §4.3 lowercase, and §5's dotted-quad
  forms as glibc's `inet_ntop6` implements them and BIND therefore inherits —
  without which `::ffff:c000:0201` rendered `::ffff:c000:201` instead of
  `::ffff:192.0.2.1`. Verified field-by-field against `inet_ntop`.
- **Unknown RR types render RFC 3597 `\# <len> <hex>`.** The old dump used the
  VARIABLE-width `fmt_hex` per byte, so distinct rdata collided —
  `{00 01 0a 05}`, `{00 1a 05}` and `{00 01 a5}` all printed `01a5` — while the
  same file already did this correctly for AAAA with fixed-width `fmt_byte`.
  Unknown type codes now print `TYPE<n>` and unknown RCODEs `RESERVED<n>`,
  instead of `TYPE?` / `RCODE?`, which discarded the value. RCODEs 6-10 gained
  their real mnemonics.
- **The answer line prints the reply's own CLASS.** `dns_rr_class` had been
  populated since 0.3.0 and read by no production code, so a reply carrying
  CLASS=CH was displayed as IN. (The QUESTION line's `IN` literal stays — dig
  only ever sends QCLASS=IN, so that one is truthful by construction.)
- **`dig example.com.` no longer prints `;example.com..`.** The wire query was
  always correct; only the display doubled the dot.
- **Dead code removed**: `_dig_streq_ci` (a third comparator variant with
  subtly different semantics from the two in use — a trap), `platform_sleep_ms`
  on both arms (uncalled, and the Linux body held a raw `nanosleep` number that
  means `unlinkat` on aarch64 — a dead function holding a loaded gun),
  `dns_rr_rdlength`, `DNS_FLAG_RA`, `RESOLV_FALLBACK_GATEWAY`, and the
  write-only `type_seen` slot.
- **Every `write(2)` goes through `sys_write`.** Seven raw `syscall(1, ...)`
  sites remained in `src/`. They worked on aarch64 because the toolchain
  translates 1 → 64 — but "it happens to be translated" is exactly the reasoning
  that made `sendto`/44 a P1 in the first place, so they are named now.
- **`DNS_NAME_BUF_LEN`** replaces thirteen hand-written `var nbuf[256]`. The
  contract is a zero-margin exact fit and cyrius cannot take an expression as an
  array size, so a test asserts `DNS_NAME_BUF_LEN == DNS_MAX_NAME_LEN + 1` —
  that assertion is the only thing coupling the two numbers.

### Tests
- **128 → 198 assertions**, in seven new groups: `aaaa_rfc5952`,
  `rdata_validation`, `rcode_names`, `surviving_guards`, `resolv_038`,
  `reply_acceptable`, `name_buf_contract`.
- **`tests/dig.fcyr` is a real fuzz harness.** It was
  `if (len == 0) { return 0; } return 0;` with **no `include` of any `src/`
  module**, called once with the literal `"test"` — and `cyrius fuzz` printed
  PASS, which is worse than having no target at all because it read as coverage.
  Proven: with `dns_parse_rr`'s rdlength bound deleted, the old stub still
  passed. The replacement runs **1,560,376** assertions across five strategies
  (uniform random, mutated valid frames, structure-aware field fuzzing, every
  truncation, scattered compression pointers) against three invariants —
  survival, offset contract, and no-forgery — and drives `output_print_rdata` on
  every record so hostile rdata reaches the escaper and the RDLENGTH checks too.
  It catches the rdlength mutant the stub missed.
- **`query_reply_acceptable` extracted** from the transport loop. All four
  acceptance guards — including the RFC 5452 §9.1 question check 0.3.7 exists to
  have added — could be deleted with the whole suite green, because
  `dns_question_matches` was tested as a function while its *use* was not tested
  at all.
- **Five guards that survived deletion** now have assertions: `dns_parse_rr`'s
  rdlength bound, the compression hop budget in **both** walkers (the existing
  cycle tests fed only self- and forward-pointers, which the backward rule kills
  on its own, so the budget was never the deciding guard — the new case is a
  33-link chain of individually-legal backward pointers), `dns_skip_name`'s
  label-length guard, `dns_skip_question`'s fixed-tail bound, and
  `resolv_parse`'s whitespace guard.
- Several of these tests initially passed **for the wrong reason** and were
  rewritten: the `dns_skip_name` cases were hitting the `msg_len` bound rather
  than the guard under test, which is why the buffers are now deliberately
  oversized. That is the failure mode the whole group exists to prevent.

### Notes
- x86_64, `--aarch64` and `--agnos` all build; x86_64 and aarch64 both resolve
  live. `cyrius audit` green on all four dimensions.
- Binary 163,016 → 167,376 bytes.
- **Still open, deliberately:** the AGNOS arm has no executed coverage, so its
  0.3.7 parity fixes remain review-verified only; there is no CI job building
  any target but host x86_64; and `docs/adr/` and `docs/architecture/` are still
  empty placeholders while the v1.0 gate names two documents that the last three
  releases have now fully supplied the material for. All three are in
  `roadmap.md`.


## [0.3.7] — 2026-08-28 (P-1 audit sweep: wrong syscalls on aarch64, raw control bytes on your terminal)

An audit/hardening/repair cut on the existing surface. No new DNS features.

Two P1s. One made every non-x86_64 build call the wrong kernel entries; the
other let any zone owner write raw terminal control bytes to the screen of
anyone who looked them up. Alongside them: a defect that hung the process
outright, one that answered a different question than the one asked and reported
success, and six that let a reply dig should have dropped reach the user — three
of which were fixed on the Linux arm first and had to be chased onto the AGNOS
arm before the cut was honest.

Every repair below has an assertion behind it, and every assertion is
mutation-checked. The suite goes 70 → **128**.

**This cut does not close the audit.** It ran eight independent lenses over the
0.3.6 tree and confirmed 61 findings against adversarial refutation; both P1s
and the highest-value P2s are repaired here. Twenty-three P2/P3 items remain,
enumerated in `roadmap.md` § 0.3.8 rather than quietly dropped.

### Fixed
- **`--aarch64` built clean and produced a binary that called the wrong kernel
  entries.** `src/platform_linux.cyr` carried a private `_LX_SYS_*` table
  hardcoded to x86_64, while `src/platform.cyr` routes *every* non-AGNOS target
  through that file — aarch64 included, which the toolchain builds without a
  murmur. The numbers are unrelated between the two ABIs: `read` 0 is
  `io_setup`, `close` 3 is `io_submit`, `sendto` 44 is `fstatfs`, and
  `nanosleep` **35 is `unlinkat`**, which the retry backoff invoked on every
  retry. Proven rather than argued: the 0.3.6 aarch64 build answers
  `;; connection timed out; no servers could be reached` under `qemu-aarch64`;
  the 0.3.7 build returns real A records.

  The table is gone. Every call now goes through the stdlib's arch-dispatched
  wrapper — `sys_socket` / `sys_connect` / `sys_write` / `sys_recvfrom` /
  `sys_setsockopt` / `sys_close` / `sys_read` / `sys_open` / `sys_getrandom`,
  all of which exist on both arches and were sitting there unused. `clock_gettime`
  and `nanosleep` have no wrapper and no named constant anywhere in the stdlib,
  so those two are arch-guarded **literals** under `#ifdef CYRIUS_ARCH_AARCH64`
  (113/101 vs 228/35) — literals, not `var`s, because `lib/bench.cyr` documents
  that the macOS/Windows reroute for `syscall(228)` only fires when the argument
  const-folds, and the old table was `var`s. So the AGNOS arm is no longer the
  only one without raw numbered syscalls; the Linux arm now has two, both named
  and both justified in place.
- **`dig +timeout=0` hung forever.** `+timeout` was parsed and stored unchecked,
  and `0` reached `SO_RCVTIMEO` as `{0, 0}` — which Linux reads as *block
  indefinitely*, the exact opposite of what the user asked. `recvfrom` never
  returned and the process could only be killed. Now clamped to
  `[1, 3600]` seconds at the CLI, matching BIND ("if T is less than 1, the query
  timeout is set to 1 second"), with `platform_set_recv_timeout_ms` clamping
  again at the syscall boundary so the contract "this call always bounds the
  wait" holds regardless of caller. `+retry` is likewise clamped to `[1, 100]`.
- **`dig example.com BOGUSTYPE` answered a different question and exited 0.** A
  second bare positional that was not a recognized record type was silently
  *discarded*, so dig queried A and printed it as though that had been the
  request — nothing on stderr, success exit. `DIG_CLI_ERR_BAD_TYPE` had existed
  since 0.3.0 for exactly this and was returned from nowhere in the tree. It is
  now returned, and the case exits 2.
- **`_dig_parse_uint`'s overflow guard could be walked past.** It checked
  `if (v < 0)` after each `v * 10 + d`, but signed overflow wraps, so a long
  enough digit run lands back on a positive value and passes. Confirmed by
  mutation: with the new digit cap removed, `+timeout=99999999999999999999`
  parses successfully. Input is now capped at 10 digits, which cannot overflow
  i64, making the check total rather than probabilistic.

### Security
- **A DNS response could write raw terminal control bytes to your screen.** Both
  channels that carry attacker-chosen octets to stdout — decoded names and TXT
  character-strings — went out verbatim. RFC 1035 constrains their *length*, not
  their content, so every byte is legal on the wire and BIND has escaped them
  per §5.1 since forever. Demonstrated with a real build rather than argued: a
  TXT record containing `CR ESC [ 2 K` makes dig emit
  `68 69 0d 1b 5b 32 4b ...` — carriage return, then erase-entire-line — so the
  record can wipe the line dig just printed and repaint a forged one. **This
  needs no spoofing at all**, only a zone the attacker controls, and it reaches
  the TXT path for *any* qtype because the answer walk dispatches on the RR's
  own type. Two more channels in the same defect: an embedded `0x0A` forges an
  extra line in `+short`, which is exactly the form scripts read with
  `for ip in $(dig +short ...)`; and an embedded NUL truncated the whole name,
  because the sink was `strlen`-based, so `safe.example.com\0.evil.tld`
  displayed as `safe.example.com`.

  All response-derived output now goes through `_esc_to_buf` (RFC 1035 §5.1),
  which is length-driven rather than NUL-terminated — `dns_decode_name` gained
  an `out_len` out-param for it. Escaping is at the sink, deliberately: doing it
  in the decoder expands up to 4x and every caller declares `var nbuf[256]`,
  which in a language with no bounds checking is a stack smash rather than a
  fix. Space is context-dependent — escaped in an unquoted name as `\032`
  (BIND does this), left literal inside TXT's quotes, so the near-universal
  `v=spf1 -all` still renders as `v=spf1 -all` and not `v=spf1\032-all`.
  Control bytes are escaped in both contexts and that is not configurable.
  **Known limit, stated rather than hidden:** a literal `.` inside a label is
  not escaped as `\.`, because the decoder flattens labels into a dotted string
  and by the sink a separator dot and an in-label dot are indistinguishable. A
  BIND-fidelity gap with no security consequence; it needs the decoder-side
  rewrite parked at 0.4.x.
- **The AGNOS arm did not get the hardening the Linux arm did — now it does.**
  Fixing one backend and not the other is the divergence taar 0.5.0 spent a
  release closing, and this cut had opened a fresh one:
    - `platform_random_u16` returned `(hi << 8) | lo` on AGNOS — structurally
      `[0, 65535]`, **never negative** — so the fail-closed entropy check added
      to `query.cyr` above was *dead code on that arm* while live on Linux. Both
      `sys_getrandom` call sites now check for `!= 2` and fail closed. `var
      rb[2]` is not zero-initialised, so the unchecked version derived the
      source port from stack residue; on a zero page that is exactly 49152.
    - `platform_udp_recv` passed `0` as `sys_udp_recv`'s fourth argument and
      threw the peer away. That argument is the source-address out-param, not a
      flags word (`kernel/core/syscall.cyr`), and the kernel does **not** filter
      by source — `net_ingress` resolves with `udp_find_listener(dst_port)` and
      compares nothing else. So after the Linux `connect(2)` repair, AGNOS was
      the only unfiltered arm, and the harder one: the listener mailbox is a
      single slot every matching datagram overwrites, so a sprayer both lands
      forgeries *and* clobbers the genuine reply. dig now stashes the peer on
      send and drops non-matching datagrams on recv, continuing the poll rather
      than ending the attempt.
    - `platform_set_recv_timeout_ms` stored its argument unclamped and always
      returned 0, so `query.cyr`'s new return check could never fire there and a
      non-positive value put the poll deadline in the past.
- **The UDP socket is now connected, so the kernel drops off-peer replies.**
  `platform_udp_send_to` was `sendto(2)` on an unconnected socket and
  `platform_udp_recv` passed `NULL` for the source-address out-param, so *any*
  host that could reach the ephemeral port had its datagram handed to the
  parser; the 16-bit query ID was the only thing an off-path attacker had to
  guess. Now `connect(2)`-then-`write(2)`, following taar 0.4.0's udp path —
  which also removes the need for a `sendto` number the stdlib does not name
  (the aarch64 hazard above). An attacker must now guess the ephemeral port too.
- **The reply's question section is compared against the question asked**
  (RFC 5452 §9.1) — new `dns_question_matches`. Through 0.3.6 the only checks
  were the query ID and the QR bit, so anyone who guessed the ID could return an
  answer for a *different name* and dig would print it as the answer. The match
  folds case (RFC 4343; 0x20-encoding resolvers randomize it) and is conservative
  by construction — a `qdcount` other than 1, or a question running past the
  received length, rejects.
- **A fresh query ID per attempt.** The ID was generated once, outside the retry
  loop, so all three default attempts reused the same 16 bits on the same port —
  handing an off-path attacker a second and third guess at one target.
- **Entropy failure is now fatal instead of falling back to the clock.**
  `platform_random_u16` opened `/dev/urandom` and, if that failed, returned the
  low 16 bits of `CLOCK_MONOTONIC` nanoseconds — a value an attacker who knows
  roughly when the query was sent can search over a small range. A guessable
  query ID is the whole cache-poisoning problem, so there is no safe fallback:
  the call now fails closed via `sys_getrandom` and the query is abandoned.
  Incidentally two syscalls cheaper per query, and it matches the AGNOS arm.
- **A rejected datagram no longer costs a retry.** On a bad ID or a clear QR
  bit the old loop consumed one of its three attempts *and re-sent the query*,
  so anyone able to spray junk at the socket exhausted the retry budget in
  microseconds and dig reported "connection timed out". The accept checks now
  run in an inner loop bounded by the attempt's own deadline: junk costs the
  attacker a packet and dig one iteration.
- `platform_set_recv_timeout_ms`'s return value is checked. An unnoticed failure
  there meant an unbounded receive.

### Changed
- **`[deps.cmdit]` 1.2.4 adopted, and stdlib `flags` dropped.** dig's grammar is
  BIND's, not getopt-long, and cmdit's own docs name dig as the case its
  `cmdit_raw_argv` escape hatch exists for — so `src/cli.cyr` keeps the
  `@server` / `+flag` tokenizer, which is the security-relevant part. What cmdit
  takes over is everything around it: `--help`/`-h`, `--version`/`-V`, the
  `argc()`/`argv(i)` materialize bridge that `main.cyr` hand-rolled, and the
  usage/success exit constants.

  Stdlib `flags` went the other way: declared at 0.3.0 for "CLI parsing" and
  **never referenced by a single line of dig** — all 25 of its symbols had zero
  hits across `src/` and `tests/` — because `cli.cyr` was hand-rolled precisely
  since `lib/flags.cyr`'s `--long` grammar does not fit. Same swap `kii` made at
  its v1.1.0. `args` stays; cmdit calls it.
- **`dig --version` exists.** It reported a parse error before. It prints from
  the same `CYRIUS_PKG_VERSION` the query banner uses, so `VERSION` remains the
  single source of truth.
- **`PLATFORM_ERR_TIMEOUT` is a named constant in both platform arms** rather
  than a bare `-11` in one and an unnamed `-EAGAIN` convention in the other.
  taar 0.5.0 spent a release fixing exactly this divergence in its own TCP path;
  dig's two arms are now aligned by construction.
- All 33 previously undocumented public fns have doc comments; the two
  over-long lines are wrapped; `src/platform.cyr`'s bare `TODO` is tracked
  against a real roadmap entry. `cyrius audit` is green on all four dimensions
  (fmt / lint / docs / tests) for the first time.
- **`roadmap.md` gains § 0.7.x — Host-target parity**, and loses the
  "Windows / macOS host targets" out-of-scope bullet that contradicted it. The
  code had carried `Windows / macOS branches still TODO` since June while the
  roadmap declared those targets excluded; the code was right, and the stdlib
  has since grown the peers that made the exclusion moot.

### Tests
- **70 → 128 assertions**, in four new groups: `output_escaping` (26),
  `dns_question_match` (12), `cli_bounds` (13), `cli_bad_type` (7).
- **Mutation-checked, all of them:** reverting `dns_question_matches` to always
  accept, dropping the `+timeout` clamp, restoring the silent unknown-type
  discard, removing the digit cap, passing bytes through `_esc_to_buf` raw,
  hardcoding the escape's hundreds digit, dropping its capacity refusal, and
  escaping space unconditionally — each turns the suite red. One mutation
  (`% 10` → `% 9` on the hundreds digit) does *not*, and is reported here rather
  than quietly dropped: it is equivalent, since the two differ only above
  c = 900 and c is a byte. The digit-cap
  mutation is also the empirical proof that the old overflow guard was
  insufficient rather than merely ugly.
- Still no executed coverage of `src/platform_agnos.cyr`, and the network path
  itself remains untested in CI. Both are named in `state.md`. The AGNOS parity
  fixes above are therefore **review-verified only** — which is exactly how the
  divergence they close got in.

### Notes
- x86_64, `--aarch64` and `--agnos` all build; x86_64 and aarch64 both resolve
  live (aarch64 under `qemu-aarch64`). AGNOS still only compiles.
- Binary grew 132,472 → 163,016 bytes. The cmdit bundle is 72 KB of source for
  the five functions dig calls, and at 6.5.35 `CYRIUS_DCE=1` NOPs unreachable
  code in place rather than removing it, so none of that comes back. Named here
  rather than buried: it is a real cost of the dependency.
- `+tcp`, `+dnssec` and EDNS(0) remain 0.4.x. Nothing here touches them.


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
