# dig

DNS resolver written in [Cyrius](https://github.com/MacCracken/cyrius). Sovereign reimplementation of BIND's `dig`.

> *Mechanically, **Domain Information Groper** — the upstream BIND meaning, kept for the muscle memory of `dig A example.com`. Culturally, **Cyrus from The Warriors (1979): "Can you dig it?"** — consonant with **Cyrius**, the language. Two layers of dig in one verb.*

## What it does

```sh
$ dig example.com
; <<>> dig 0.1.0 <<>> example.com
;; QUESTION
;example.com.        IN    A
;; ANSWER
example.com.   3600  IN    A    93.184.216.34
;; Query time: 12 ms · server: 192.168.1.1 · proto: udp

$ dig +short example.com AAAA
2606:2800:21f:cb07:6820:80da:af6b:8b2c

$ dig +trace google.com
;; root  -> .                NS  a.root-servers.net.
;; tld   -> com.             NS  a.gtld-servers.net.
;; auth  -> google.com.      NS  ns1.google.com.
;; final -> google.com.      A   142.250.80.46
```

Same shape as BIND's `dig` but Cyrius-native end to end:

- No POSIX `socket()` — kernel exposes a sovereign `udp_send` / `udp_recv` / `tcp_connect` surface. Per [[project_agnos_kernel_growth_rules]] we add what `dig` actually needs, not POSIX emulation.
- No `libc`, no `libresolv`, no `libbind`. RFC 1035 + RFC 3596 (AAAA) + RFC 2782 (SRV) + RFC 4034 (DNSSEC RRSIG/DNSKEY) all parsed in Cyrius.
- Reads naturally as a verb: `dig example.com`, `dig +short MX gmail.com`, `dig +trace +tcp +dnssec example.com`.

## Why use it

- **Cyrius-native** — same toolchain that builds the AGNOS kernel, same sovereignty story end to end.
- **Tiny** — single static binary, no `libresolv` drift.
- **Predictable resolution** — no `/etc/nsswitch.conf` magic, no NSS plugin chain. Queries go straight to the resolver you point at, in the order you specify.
- **Wordplay readability** — `dig example.com` is what your brain wants to type when you want the A record.

## Build

```sh
cyrius deps                            # resolve stdlib + sibling deps
cyrius build src/main.cyr build/dig    # compile
cyrius test                            # run [build].test + tests/*.tcyr
```

Toolchain pin lives in `cyrius.cyml` (`[package].cyrius`). Don't hardcode it in CI YAML.

## Install

```sh
sh scripts/install.sh                  # copies build/dig → ~/.cyrius/bin/
```

Or drop the built binary anywhere on `$PATH`. No runtime deps.

## Family

`dig` is the second entry in the **AGNOS network-tools family** (English-wordplay / trickster lane):

| Tool | Sovereign equivalent of | Role |
|---|---|---|
| **yo** | `ping` | ICMP echo probe — *"is this host reachable, and how far away?"* |
| **dig** | BIND `dig` | DNS resolver — *"dig out the address record"* (and: *can you dig it?*) |
| **whirl** | `curl` + `wget` | HTTP / HTTPS transfer — *"the packet whirls out, the response whirls back"* |

`dig` is the **extraction trigger** for `taar` (Hindi तार, *wire/string/connection*) — the network-probe substrate library. The duplication friction between yo (ICMP) and dig (DNS + UDP/TCP-53 sockets) is what shapes taar's API honestly. Per user direction 2026-05-23: **yo → dig → extract taar (at dig completion) → whirl consumes already-extracted taar**. See [shared-crates registry § taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) for the extraction shape.

## Status

Pre-1.0. See [`docs/development/state.md`](docs/development/state.md) for current version + surface + iron-validation status, and [`docs/development/roadmap.md`](docs/development/roadmap.md) for the milestone path through v1.0.

## License

GPL-3.0-only — see [LICENSE](LICENSE).

## Genesis

Part of [AGNOS](https://github.com/MacCracken/agnosticos) — the AI-native general operating system. AGNOS first-party tools follow [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md) and [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-documentation.md).
