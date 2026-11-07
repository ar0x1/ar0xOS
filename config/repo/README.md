# /home/user/ar0xOS/config/repo/ — Phase 9 repository policy

| File | CANONICAL for | Installed / consumed at |
|---|---|---|
| `repo-options.conf` | `repo-add` flags, SigLevel, retention, CI image | sourced by `tools/setup-repo.sh` |
| `pacman.conf.ar0x-entry` | the 3 `[ar0x]` data lines | policy source for `config/pacman.conf.installed` (`[ar0x]` FIRST, ADR-017) and `/etc/pacman.conf` (Phase 10); shipped as `/usr/share/doc/ar0x-keyring/pacman.conf.ar0x-entry` |
| `RELEASE_KEY_FINGERPRINT` | the 40-hex release signing key fingerprint | published out-of-band; regenerates `ar0x-trusted` |

⚠️ **No private key is ever stored here.** `$AR0X_KEYS_DIR/gnupg` (default
`/opt/ar0x-build/keys/gnupg`, mode `0700`) is outside the Git checkout.
Full procedure: `/home/user/ar0xOS/docs/REPO_GUIDE.md`.

`config/pacman.conf.installed` and `config/repo/pacman.conf.ar0x-entry` MUST stay
**policy-identical** for the `[ar0x]` block (same 3 data lines: `[ar0x]`,
`SigLevel = Required`, `Server = https://repo.ar0x.dev/$arch`).
`ar0x_repo.validate_pacman_entry()` asserts this. Neither file may ever contain
`Optional`, `Never`, `TrustAll` or `DatabaseOptional` — those are FORBIDDEN on
installed systems; the build-only `SigLevel = Optional TrustAll` lives solely in
`config/pacman.conf.build` (RISK-006).
