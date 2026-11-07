# /home/user/ar0xOS/assets/ascii/

Canonical, human-edited ASCII art lives in **`config/branding/ascii/`** (all
`/etc`-adjacent text is owned by `config/branding/`, per BUILD_LAYOUT.md §4).

| Canonical source | Installed path | Consumer |
|---|---|---|
| `config/branding/ascii/ar0x-ascii.txt` | `/usr/share/ar0x/branding/ar0x-ascii.txt` | neofetch `image_source`, `/etc/motd` |
| `config/branding/ascii/ar0x-fastfetch.txt` | `/usr/share/ar0x/branding/ar0x-fastfetch.txt` | fastfetch `logo.type=file` (`$1..$9`) |
| `config/branding/ascii/ar0x-screenfetch.sh` | `/usr/share/ar0x/branding/ar0x-screenfetch.sh` | `screenfetch -a PATH` |

`tools/configure-branding.sh --check` proves that stripping `$[1-9]` from the
fastfetch variant yields the plain variant **byte for byte**, and that the
screenfetch `fulloutput` array has exactly one `%s` per line.
