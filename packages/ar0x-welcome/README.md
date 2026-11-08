# ar0x-welcome — Phase 8 package

`/usr/bin/ar0x-welcome` · GTK4 + PyGObject · **never runs as root**.

- Plain `Gtk.Application` + `Gtk.CssProvider` (NOT libadwaita — RISK-042).
- `gi` is imported LAZILY inside `run_gui()`, so `--self-test` runs headless.
- System summary comes from `ar0x-info --json`.
- Privileged actions go through `pkexec` with EXPLICIT argv lists, never a shell
  string, never `--noconfirm`, and are echoed into the output pane first.
- `--firstboot` skips when `~/.config/ar0x/welcome-done` exists and writes it on close.

| Installed file | Purpose |
|---|---|
| `/usr/bin/ar0x-welcome` | GTK4 application |
| `/usr/share/applications/ar0x-welcome.desktop` | launcher (`Icon=ar0x-logo`) |
| `/usr/share/ar0x/welcome/ar0x-welcome.css` | 8 ADR-015 palette pins |
| `/usr/share/ar0x/welcome/links.conf` | 5 https links (mirror of `config/tools/links.conf`) |
| `/usr/share/ar0x/welcome/extra-groups.conf` | 4 official-package groups (RISK-010 gate) |
| `/usr/lib/systemd/user/ar0x-welcome.service` | per-user first-login unit |
| `/usr/lib/systemd/system/ar0x-firstboot.service` | `ConditionFirstBoot=yes`, armed by Calamares `finished` |
| `/usr/lib/ar0x/ar0x-firstboot` | RISK-013 guard + stamp + global user-unit enable |
| `/usr/lib/ar0x/ar0x-apparmor-ctl` | RISK-008 enforce/complain opt-in + one-command revert |

⚠️ **GTK4 rendering was NEVER tested in this sandbox** (no display, no `gi`,
no GTK runtime). RISK-047. `--self-test` covers every pure-Python path.
