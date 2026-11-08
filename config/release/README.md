# `config/release/` — Phase 12 canonical release configuration

| File | Role |
|---|---|
| `release-options.conf` | 21 sourced KEY=value pins: tag, title, exact 6-member artifact set, hosts, FPR path, EOL policy |

**ONE OWNER PER PATH (ADR-024/026/027/028):** these pins are canonical.
`tools/prepare-release.sh --sync` stages a disposable `build/release-prefix/`
(gitignored) for offline tests; no derived artifact is ever committed.

⚠️ **RISK-054:** NO tag, GitHub Release, mirror upload, announcement or
DistroWatch submission happened. The release key is still `PENDING-KEYGEN`
(`config/repo/RELEASE_KEY_FINGERPRINT`) and the signed `[ar0x]` db does not
exist. `--publish` is **print-only** and NEVER uploads. Full procedure:
`docs/RELEASE_GUIDE.md`.

The DistroWatch submission requires exactly four pieces of information (project
name, website URL, description including the Arch base, and a direct ISO link);
the last one is a RESERVED placeholder until a signed ISO exists.
