# ar0x-info — Phase 8 package

`/usr/bin/ar0x-info` · `arch=('any')` · pure Bash, no root.

| Mode | Behaviour |
|---|---|
| (default) | `fastfetch --config /usr/share/ar0x/info/fastfetch.jsonc`; auto-falls back to `--plain` when fastfetch is absent |
| `--plain` | 8-line ASCII logo + key/value summary, pure Bash, NO external tools |
| `--json`  | 17 string keys, UTF-8, no ANSI — consumed by `ar0x-welcome` |
| `--logo`  | just the ASCII art |
| `--self-test` | offline checks of JSON, art dimensions, config, fallback |

**Canonical ownership:** `ar0x-ascii.txt` and `ar0x-fastfetch.txt` are
byte-identical mirrors of `config/branding/ascii/*`; `fastfetch.jsonc` is the
canonical `config/branding/fastfetch/config.jsonc` with ONLY the header and
`logo.source` rewritten to the package-owned path.
`tools/configure-tools.sh --check` enforces all three relationships. Edit the
canonical files, then re-generate the mirrors and refresh the PKGBUILD
`sha256sums` (`./tools/configure-tools.sh --sync`).

Build (⚠️ MANUAL, Arch host): `cd packages/ar0x-info && makepkg -s --noconfirm`.
