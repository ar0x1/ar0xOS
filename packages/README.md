# /home/user/ar0xOS/packages/ — ar0x PKGBUILD workspace

Phase 8 delivers the **three user-facing tools** as real, buildable packages.
Every file here is a SOURCE; no `.pkg.tar.zst` is ever committed (`.gitignore`
excludes `*.pkg.tar.zst`, `*.sig`, `SHA256SUMS`).

| Directory | Phase | Status | Installed files |
|---|---|---|---|
| `ar0x-welcome/` | 8 | ✅ COMPLETE | `/usr/bin/ar0x-welcome`, `.desktop`, CSS, link/group tables, 2 systemd units, 2 helpers, scriptlet |
| `ar0x-update/`  | 8 | ✅ COMPLETE | `/usr/bin/ar0x-update`, `.desktop`, `/etc/ar0x/update.conf` |
| `ar0x-info/`    | 8 | ✅ COMPLETE | `/usr/bin/ar0x-info`, `.desktop`, `/usr/share/ar0x/info/**` |
| `ar0x-theme/`        | 9 | ⏳ DEFERRED | GTK3/GTK4, Qt5/Qt6, icons, cursors, fontconfig |
| `ar0x-wallpapers/`   | 9 | ⏳ DEFERRED | 3× 4K wallpapers + GRUB/Plymouth/SDDM art + `ar0x-logo` icon |
| `ar0x-hypr-config/`  | 9 | ⏳ DEFERRED | `/etc/skel/.config/hypr/hyprland.lua` + modules |
| `ar0x-keyring/`      | 9 | ⏳ DEFERRED | GPG public key (cannot exist before Phase 9's offline key) |
| `ar0x-meta/`         | 9 | ⏳ DEFERRED | meta-package pulling the standard experience |

⚠️ **Why five packages are deferred to Phase 9 (ADR-023):** their sources
already exist in `config/desktop/**`, `config/branding/**` and `assets/**` and
are installed into the live ISO by `configure-desktop.sh --sync` /
`configure-branding.sh --sync`. A second package owning the SAME `/etc/skel/**`
paths would produce a `pacman: file exists in filesystem` conflict during a
Calamares install. Phase 9 must decide ONE owner per path before writing those
PKGBUILDs; `ar0x-keyring` additionally needs the offline GPG key (`R1`).

Full guide: `/home/user/ar0xOS/docs/TOOLS_GUIDE.md`.
