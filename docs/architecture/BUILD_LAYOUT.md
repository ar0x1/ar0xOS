# ar0x — Build Environment Directory Structure

> Phase 1 companion to [`PROJECT_PLAN.md`](../../PROJECT_PLAN.md).
> Every path below is absolute and is the canonical location. Scripts in Phases 2–12
> MUST use these paths (via the `AR0X_*` environment variables in §5), never ad-hoc ones.

---

## 1. Two-root model

| Root | Absolute path | Owner | In Git? | Lifetime | Purpose |
|---|---|---|---|---|---|
| **SOURCE ROOT** | `/home/user/ar0xOS` | developer | ✅ yes | permanent | Human-edited configs, scripts, PKGBUILDs, docs, assets |
| **BUILD ROOT** | `/opt/ar0x-build` | `root:root` | ❌ no (`.gitignore`) | disposable, wiped between clean builds | Scratch space, pacman cache, ISO output, signing keys |

**Why two roots:** `mkarchiso` writes 10–25 GB into its `work/` directory and needs root
(mount, loop devices, `mknod`). Keeping that out of the Git checkout prevents accidental
commits of multi-gigabyte artifacts and keeps `git status` fast. `/opt/ar0x-build` should sit
on a fast SSD with ≥ 40 GB free (Phase 2 defines the full hardware spec).

`/home/user/ar0xOS/build/` is a **git-ignored symlink** created by Phase 2:
`ln -s /opt/ar0x-build /home/user/ar0xOS/build`
so `build/out/ar0x-0.1.0-x86_64.iso` is a convenient relative path from the checkout.

---

## 2. SOURCE ROOT — complete tree

```
/home/user/ar0xOS/
├── .git/
├── .gitignore                                  # Phase 1 — excludes build/, repo/, *.iso, keys
├── README.md                                   # Phase 12
├── PROJECT_PLAN.md                             # Phase 1
│
├── docs/
│   ├── architecture/
│   │   ├── BUILD_LAYOUT.md                     # Phase 1  ← this file
│   │   ├── COMPONENT_VERSIONS.md               # Phase 1
│   │   ├── DEPENDENCY_GRAPH.md                 # Phase 1
│   │   ├── DECISIONS.md                        # Phase 1
│   │   └── RISK_REGISTER.md                    # Phase 1
│   ├── BUILD_HOST.md                           # Phase 2 — exact commands, hardware, Docker/Vagrant
│   ├── BOOTSTRAP_GUIDE.md                      # Phase 3 — full profile spec + chroot guide
│   ├── KERNEL_BOOT.md                          # Phase 4 — kernel policy + boot branding
│   ├── SYSTEM_CONFIG.md                        # Phase 5 — core system config guide
│   ├── DESKTOP_GUIDE.md                        # Phase 6 — desktop + theme guide
│   ├── BRANDING_GUIDE.md                       # Phase 7 — identity + art guide
│   ├── TOOLS_GUIDE.md                          # Phase 8 — custom tools + packaging guide
│   ├── KERNEL_CONFIG_NOTES.md                  # Phase 4
│   ├── INSTALLER_FLOW.md                       # Phase 10 — step-by-step Calamares test
│   ├── TESTING_CHECKLIST.md                    # Phase 11
│   ├── RELEASE_NOTES_TEMPLATE.md               # Phase 12
│   ├── DISTROWATCH_SUBMISSION.md               # Phase 12
│   └── ROADMAP.md                              # Phase 12
│
├── config/                                     # ALL config sources; 1:1 with target /etc
│   ├── versions.env                            # Phase 1 — pinned versions (sourced by scripts)
│   ├── pacman.conf.build                       # Phase 3 — FROZEN archive mirror (canonical)
│   ├── pacman.conf.installed                   # Phase 5/9 — rolling mirrors + [ar0x]
│   ├── packages.x86_64                         # Phase 3 — canonical ISO package list
│   ├── bootstrap_packages.x86_64               # Phase 3 — canonical bootstrap buildmode list
│   ├── profiledef.sh                           # REMOVED — canonical is archiso/profiledef.sh
│   ├── mkinitcpio.conf                         # Phase 4 — installed-system base
│   ├── mkinitcpio.d/linux-lts.preset           # Phase 4 — default preset ONLY
│   ├── default/grub                            # Phase 4 — GRUB_THEME, quiet splash
│   ├── plymouth/plymouthd.conf                 # Phase 4 — Theme=ar0x
│   ├── kernel/
│   │   ├── README.md                           # Phase 4 — RISK-001 policy
│   │   ├── ar0x-lts.config                     # Phase 4 — exact menuconfig selections
│   │   └── patches/                            # ⚠️ EMPTY in v0.1 (no kernel patches)
│   ├── system/                                 # Phase 5 — mirrors /etc EXACTLY (1:1)
│   │   ├── hostname, hosts, locale.conf, locale.gen, vconsole.conf
│   │   ├── localtime -> /usr/share/zoneinfo/UTC   (SYMLINK)
│   │   ├── passwd, shadow                     # ⚠️ LIVE-only passwordless user
│   │   ├── nftables.conf                      # /etc/nftables.conf (top-level!)
│   │   ├── sysusers.d/ar0x-live.conf , sudoers.d/10-ar0x-wheel
│   │   ├── security/limits.d/90-ar0x-audio.conf
│   │   ├── polkit-1/rules.d/10-ar0x.rules
│   │   ├── NetworkManager/conf.d/10-ar0x.conf
│   │   ├── pipewire/pipewire.conf.d/10-ar0x.conf
│   │   ├── pipewire/wireplumber.conf.d/10-ar0x.conf  # ⚠️ WP 0.5+ PATH
│   │   ├── environment.d/10-ar0x-wayland.conf , profile.d/ar0x-wayland.sh
│   │   ├── sysctl.d/50-ar0x-security.conf , sysctl.d/60-ar0x-network.conf
│   │   ├── systemd/journald.conf.d/10-ar0x.conf
│   │   ├── systemd/logind.conf.d/10-ar0x.conf
│   │   ├── systemd/system-preset/50-ar0x.preset
│   │   └── systemd/system/apparmor.service.d/10-ar0x-complain.conf
│   │   (NO wireplumber/ dir — legacy 0.4 path, removed in Phase 5)
│   │   (NO apparmor/ dir — ar0x v0.1 ships no custom profiles)
│   ├── desktop/                                # Phase 6 ✅ CANONICAL configs
│   │   ├── hypr/
│   │   │   ├── hyprland.lua                    # ⚠️ Hyprland 0.57 — Lua, NOT .conf
│   │   │   ├── lua/                           # 10 modules
│   │   │   │   ├── palette.lua                #   palette parity with versions.env
│   │   │   │   ├── programs.lua  env.lua  monitors.lua
│   │   │   │   ├── looknfeel.lua  animations.lua  input.lua
│   │   │   │   └── keybinds.lua  rules.lua  autostart.lua
│   │   │   ├── hyprpaper.conf  hyprlock.conf  hypridle.conf
│   │   ├── waybar/{config.jsonc,style.css}
│   │   ├── kitty/kitty.conf , wofi/{config,style.css} , mako/config
│   │   ├── gtk-3.0/{settings.ini,gtk.css} , gtk-4.0/{settings.ini,gtk.css}
│   │   ├── qt5ct/qt5ct.conf , qt6ct/qt6ct.conf
│   │   ├── fontconfig/conf.d/99-ar0x-fonts.conf
│   │   ├── xdg/mimeapps.list
│   │   ├── etc/                               # → /etc/** 1:1
│   │   │   ├── sddm.conf.d/10-ar0x.conf
│   │   │   ├── environment.d/20-ar0x-desktop.conf
│   │   │   └── xdg/user-dirs.defaults
│   │   └── skel/                               # → /etc/skel/** 1:1
│   │       ├── .zshrc , .zshenv , .zprofile , .bashrc , .profile
│   │       ├── .config/starship.toml , .config/git/config
│   │       ├── .config/fastfetch/config.jsonc , .config/user-dirs.dirs
│   │       ├── .config/xdg-desktop-portal/hyprland-portals.conf
│   │       ├── .icons/default/index.theme
│   │       └── .config/                       # ⚠️ GENERATED by --sync, DO NOT EDIT
│   │           ├── hypr/ , waybar/ , gtk-3.0/ , gtk-4.0/
│   │           ├── qt5ct/ , qt6ct/ , fontconfig/conf.d/
│   │           ├── kitty/ , wofi/ , mako/ , mimeapps.list
│   ├── branding/                               # Phase 7 ✅ CANONICAL identity
│   │   ├── os-release , lsb-release            # → /etc/** AND /usr/lib/os-release
│   │   ├── issue , issue.net , motd            # → /etc/**
│   │   ├── palette.conf                        # 8 hex pins, parity with versions.env
│   │   ├── ascii/ar0x-ascii.txt                # plain (neofetch / motd)
│   │   ├── ascii/ar0x-fastfetch.txt            # $1..$9 tagged (fastfetch)
│   │   ├── ascii/ar0x-screenfetch.sh           # SOURCED by screenfetch -a
│   │   ├── fastfetch/config.jsonc              # → /etc/skel/.config/fastfetch/
│   │   ├── neofetch/config.conf                # → /etc/skel/.config/neofetch/
│   │   └── screenfetch/ar0x-screenfetch.sh     # → /usr/local/bin/ar0x-screenfetch
│   ├── tools/                                 # Phase 8 ✅ CANONICAL tool configs
│   │   ├── links.conf                         # 5 URL pins (AR0X_URL_* parity)
│   │   ├── extra-groups.conf                  # 4 official-package groups
│   │   └── update.conf                        # → /etc/ar0x/update.conf (backup=())
│   ├── calamares/                              # Phase 10
│   │   ├── settings.conf                       # → /etc/calamares/settings.conf
│   │   ├── branding/ar0x/branding.desc         # → /usr/share/calamares/branding/ar0x/
│   │   └── modules/{welcome,locale,keyboard,partition,users,ar0x-packages,
│   │               bootloader,unpackfs,initramfs,grubcfg,removeuser,finished}.conf
│   └── repo/
│       ├── pacman.conf.ar0x-entry               # Phase 9 — snippet appended to installed conf
│       └── repo-options.conf                    # Phase 9 — repo-add options
│
├── archiso/                                    # Phase 3 — COMPLETE archiso 92 PROFILE
│   ├── profiledef.sh                            # CANONICAL — sourced by mkarchiso
│   ├── packages.x86_64                          # synced from config/packages.x86_64
│   ├── bootstrap_packages.x86_64                # synced from config/bootstrap_packages.x86_64
│   ├── pacman.conf                              # rendered from config/pacman.conf.build
│   ├── bootstrap.sh                             # stages the profile + runs mkarchiso
│   ├── airootfs/                                # overlay → live system root
│   │   ├── etc/
│   │   │   ├── mkinitcpio.conf.d/archiso.conf  # MANDATORY live initramfs hooks
│   │   │   ├── pacman.d/hooks/90-ar0x-build-stamp.hook  # supported customization
│   │   │   ├── hostname, locale.conf, vconsole.conf
│   │   │   └── ... (config/system/** overlays here in Phase 5)
│   │   ├── usr/
│   │   │   ├── local/bin/                      # ar0x-* tools (shipped as pkgs in P8)
│   │   │   └── share/{plymouth,calamares,sddm,backgrounds,applications}/
│   │   ├── opt/ar0x/ , root/ , var/lib/ar0x/
│   │   └── NO root/customize_airootfs.sh       # ⚠️ deprecated in archiso 92
│   ├── efiboot/loader/entries/                 # unused: uefi.grub, not systemd-boot
│   ├── grub/{grub.cfg,ar0x-theme/}             # UEFI GRUB (Phase 4 brands it)
│   ├── syslinux/{syslinux.cfg,splash.png}      # BIOS isolinux (Phase 4 brands it)
│   └── boot/                                    # kernel + initramfs staged by mkarchiso
│
├── assets/                                     # Phase 6/7 ✅ — source artwork
│   ├── logo/{ar0x-logo.svg,ar0x-logo-mono.svg,ar0x-wordmark.svg,LICENSE}
│   ├── logo/ar0x-logo-{256,512}.png            # GENERATED (gen-branding-assets.sh)
│   ├── wallpapers/{ar0x-neon-grid.png,ar0x-void.png,ar0x-circuit.png,PLACEHOLDERS.md}
│   ├── plymouth/ar0x/{ar0x.plymouth,ar0x.script,logo.png,progress-0..20.png}
│   ├── grub-theme/ar0x/{theme.txt,background.png}
│   ├── sddm/ar0x/{Main.qml,metadata.desktop,theme.conf,background.png}
│   ├── syslinux/splash.png
│   ├── icons/{ar0x-logo.svg,README.md}
│   ├── cursors/ar0x-cursors/{index.theme,cursor.theme,README.md}  # TEXT canonical only
│   └── ascii/README.md                         # canonical art is in config/branding/
│
├── packages/                                   # Phase 8 ✅ 3 built + 5 P9 skeletons
│   ├── README.md                               # ownership / deferral index
│   ├── ar0x-info/                              # ✅ PKGBUILD, ar0x-info, *.desktop,
│   │   │                                      #    fastfetch.jsonc, ar0x-*.txt, README.md
│   ├── ar0x-update/                            # ✅ PKGBUILD, ar0x-update, *.desktop,
│   │   │                                      #    update.conf, README.md
│   ├── ar0x-welcome/                           # ✅ PKGBUILD, ar0x-welcome.py, *.desktop,
│   │   │                                      #    *.css, links.conf, extra-groups.conf,
│   │   │                                      #    ar0x-{welcome,firstboot}.service,
│   │   │                                      #    ar0x-firstboot, ar0x-apparmor-ctl,
│   │   │                                      #    ar0x-welcome.install, README.md
│   └── {ar0x-theme,ar0x-wallpapers,ar0x-hypr-config,
│         ar0x-keyring,ar0x-meta}/README.md     # ⏳ Phase 9 — NO PKGBUILD yet (ADR-023)
│
├── tools/                                      # ALL scripts: #!/bin/bash + set -euo pipefail
│                                                # (SOURCED snippets are exempt: see §6)
│   ├── lib/common.sh                            # shared logging, die(), require_root(), colours
│   ├── validate-versions.sh                     # Phase 1 — structural + version sanity check
│   ├── setup-build-env.sh                       # Phase 2
│   ├── bootstrap.sh                             # Phase 3
│   ├── build-kernel.sh                          # Phase 4 — config audit + boot stack
│   ├── gen-theme-assets.sh                      # Phase 4 — deterministic PNG art
│   ├── configure-system.sh                      # Phase 5 — --check/--sync/--apply
│   ├── gen-desktop-assets.sh                    # Phase 6 — deterministic 4K PNGs
│   ├── configure-desktop.sh                     # Phase 6 — --check/--sync/--apply
│   ├── lib/ar0x_logo.py                         # Phase 7 — SVG geometry + palette + PNG
│   ├── lib/ar0x_xcursor.py                      # Phase 7 — Xcur writer + self-verifier
│   ├── gen-branding-assets.sh                   # Phase 7 — logo PNGs + XCursor theme
│   ├── configure-branding.sh                    # Phase 7 — --check/--sync/--apply
│   ├── lib/ar0x_pkgbuild.py                     # Phase 8 — pure-stdlib PKGBUILD validator
│   ├── configure-tools.sh                       # Phase 8 — --check/--sync/--self-test/--build
│   ├── setup-repo.sh                            # Phase 9
│   ├── build-iso.sh                             # Phase 11 — master orchestrator
│   ├── checksum.sh                              # Phase 11
│   └── qemu-test.sh                             # Phase 11
│
├── ci/workflows/
│   ├── build-packages.yml                       # Phase 9
│   └── build-iso.yml                            # Phase 11 (optional)
│
├── docker/                                     # Phase 2 — Docker option
│   ├── Dockerfile
│   ├── compose.yaml                             # ⚠️ privileged: true (RISK-016)
│   └── run.sh
├── vagrant/                                    # Phase 2 — Vagrant option
│   └── provision.sh
├── Vagrantfile                                 # Phase 2 — Vagrant definition
│
├── tests/
│   ├── TESTING_CHECKLIST.md                     # Phase 11
│   └── test-scripts.sh                          # Phase 11 — bash -n + shellcheck sweep
│
├── repo/                                       # Phase 9 — GITIGNORED built packages
│   └── x86_64/
└── build -> /opt/ar0x-build                    # Phase 2 symlink, GITIGNORED
```

---

## 3. BUILD ROOT — complete tree

```
/opt/ar0x-build/                                # root:root, mode 0755 (keys/ is 0700)
├── profile/                                    # Phase 3 — disposable staged archiso profile
├── work/                                       # mkarchiso work dir — 10–25 GB, wiped on clean
│   ├── x86_64/airootfs/                        # the actual chroot-able root filesystem
│   ├── iso/                                    # staged ISO tree
│   └── efiboot.img , isohybrid mbr
├── out/                                        # FINAL ARTIFACTS
│   ├── ar0x-0.1.0-x86_64.iso
│   ├── SHA256SUMS
│   ├── SHA256SUMS.sig
│   └── ar0x-0.1.0-x86_64.iso.sig
├── chroot/                                     # manual arch-chroot test mount point
├── cache/                                      # pacman pkg cache, shared across rebuilds
│   └── pacman/pkg/
├── src/                                        # vendored upstream source tarballs
│   ├── calamares-3.4.3.tar.gz (+ .asc)
│   └── hyprland-*.tar.gz
├── repo/
│   └── x86_64/{ar0x.db.tar.zst, ar0x.files.tar.zst, *.pkg.tar.zst, *.sig}
├── keys/                                       # mode 0700 — NEVER in Git
│   ├── release-signing-key.asc                  # private key (offline backup required)
│   ├── repo-signing-key.asc
│   └── public/{ar0x-release.asc, ar0x-repo.asc}
└── logs/
    ├── 01-setup.log , 02-bootstrap.log , 03-kernel.log ,
    ├── 04-config.log , 05-desktop.log , 06-branding.log ,
    ├── 07-packages.log , 08-repo.log , 09-installer.log , 10-iso.log
    └── mkarchiso.log
```

---

## 4. Mapping source → target (the "1:1 overlay" rule)

`tools/bootstrap.sh` performs a mechanical overlay. There must be **no** path translation
logic other than the three explicit renames below:

| Source | Target (live + installed) |
|---|---|
| `config/system/**` | `/etc/**` |
| `config/bootstrap_packages.x86_64` | `archiso/bootstrap_packages.x86_64` |
| `config/pacman.conf.build` | `archiso/pacman.conf` (rendered, `@AR0X_REPO_DIR@` substituted) |
| `config/mkinitcpio.conf` + `config/mkinitcpio.d/` | `archiso/airootfs/etc/mkinitcpio.conf` + `/etc/mkinitcpio.d/linux-lts.preset` |
| `config/default/grub` | `archiso/airootfs/etc/default/grub` |
| `config/plymouth/plymouthd.conf` | `archiso/airootfs/etc/plymouth/plymouthd.conf` |
| `assets/plymouth/ar0x/**` | `archiso/airootfs/usr/share/plymouth/themes/ar0x/**` |
| `assets/grub-theme/ar0x/**` | `archiso/grub/themes/ar0x/**` (ISO `/boot/grub/themes/`) + `archiso/airootfs/usr/share/grub/themes/ar0x/**` |
| `assets/syslinux/splash.png` | `archiso/syslinux/splash.png` |
| `config/desktop/skel/**` | `/etc/skel/**` |
| `config/desktop/etc/**` | `/etc/**` |
| `config/desktop/<tool>/**` | `config/desktop/skel/.config/<tool>/**` (GENERATED by `--sync`) |
| `assets/sddm/ar0x/{Main.qml,metadata.desktop,theme.conf,background.png}` | `/usr/share/sddm/themes/ar0x/**` |
| `assets/wallpapers/ar0x-{neon-grid,void,circuit}.png` | `/usr/share/backgrounds/ar0x/**` |
| `config/branding/os-release` | `/etc/os-release` **and** `/usr/lib/os-release` |
| `config/branding/lsb-release` | `/etc/lsb-release` |
| `config/branding/issue` | `/etc/issue` |
| `config/branding/issue.net` | `/etc/issue.net` |
| `config/branding/motd` | `/etc/motd` |
| `config/branding/palette.conf` | `/usr/share/ar0x/palette.conf` |
| `config/branding/ascii/**` | `/usr/share/ar0x/branding/**` |
| `config/branding/{fastfetch,neofetch}/**` | `/etc/skel/.config/{fastfetch,neofetch}/**` (GENERATED) |
| `config/branding/screenfetch/ar0x-screenfetch.sh` | `/usr/local/bin/ar0x-screenfetch` (`0755`) |
| `assets/logo/*.svg` + `LICENSE` | `/usr/share/ar0x/logo/**` |
| `assets/icons/ar0x-logo.svg` | `/usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg` (`LOGO=ar0x-logo`) |
| `assets/cursors/ar0x-cursors/{index,cursor}.theme` | `/usr/share/icons/ar0x-cursors/{index,cursor}.theme` (text metadata only) |
| `tools/gen-branding-assets.sh` output | `/usr/share/icons/ar0x-cursors/cursors/*` — 5 generated Xcursor binaries + 12 alias symlinks written DIRECTLY into the tracked `archiso/airootfs` profile (there is no second binary copy under `assets/`) |
| `config/desktop/hypr/hyprland.lua` | `/etc/skel/.config/hypr/hyprland.lua` ⚠️ Lua |
| `config/calamares/settings.conf` | `/etc/calamares/settings.conf` |
| `config/calamares/branding/ar0x/**` | `/usr/share/calamares/branding/ar0x/**` |
| `assets/plymouth/ar0x/**` | `/usr/share/plymouth/themes/ar0x/**` |
| `assets/grub-theme/ar0x/**` | `/boot/grub/themes/ar0x/**` |
| `assets/sddm/ar0x/**` | `/usr/share/sddm/themes/ar0x/**` |
| `assets/wallpapers/**` | `/usr/share/backgrounds/ar0x/**` |
| `archiso/airootfs/**` | `/**` (archiso native overlay) |
| `config/tools/{links,extra-groups}.conf` | `/usr/share/ar0x/welcome/{links,extra-groups}.conf` (via `packages/ar0x-welcome/`) |
| `config/tools/update.conf` | `/etc/ar0x/update.conf` (`backup=()`, via `packages/ar0x-update/update.conf`) |
| `config/branding/ascii/**` | `/usr/share/ar0x/info/{ar0x-ascii,ar0x-fastfetch}.txt` (via `packages/ar0x-info/`) |
| `config/branding/fastfetch/config.jsonc` | `/usr/share/ar0x/info/fastfetch.jsonc` (DERIVED: header + `logo.source` only) |
| `packages/ar0x-*/PKGBUILD` | `/usr/bin/ar0x-*`, `/usr/share/applications/ar0x-*.desktop`, `/usr/lib/{systemd,ar0x}/**` |

**Consequence:** a config file that must appear at
`/etc/NetworkManager/conf.d/10-ar0x.conf` lives at
`config/system/NetworkManager/conf.d/10-ar0x.conf`; one that must appear at
`/etc/sddm.conf.d/10-ar0x.conf` lives at
`config/desktop/etc/sddm.conf.d/10-ar0x.conf`. Every Phase 5/6/7 config header
states the full destination path so nothing is ambiguous. Phase 7 ADDED a
**second** mapping rule: anything under `config/branding/**` and
`assets/{logo,icons}/**` is CANONICAL, and
`tools/configure-branding.sh --sync` writes byte-identical mirrors into
`archiso/airootfs/**` and `config/desktop/skel/.config/**`. `--check`
`cmp -s` every pair; `validate-versions.sh` re-checks the `/etc` pairs. The
Xcursor BINARIES are the one exception: `tools/gen-branding-assets.sh` writes
them directly into `archiso/airootfs/usr/share/icons/ar0x-cursors/cursors/`
(single binary copy), and `--check` parses them back rather than comparing bytes.

Phase 8 ADDS a **third** mapping rule: anything under `config/tools/**` and the
two `config/branding/ascii/*.txt` files is CANONICAL, and
`tools/configure-tools.sh --sync` writes byte-identical mirrors into
`packages/ar0x-*/`. `fastfetch.jsonc` is the single DERIVED exception (only the
header comment and `logo.source` change, because the package owns its art).
`--sync` also refreshes all 18 real SHA-256 sums in the three PKGBUILDs and
installs a disposable prefix at `build/tools-prefix/` (gitignored). `--check`
asserts 5 byte-identical pairs + the derivation-only difference via
`tools/lib/ar0x_pkgbuild.py`. Full installed paths: `docs/TOOLS_GUIDE.md §7`.

⚠️ **ONE OWNER PER PATH (ADR-023):** the three Phase 8 packages are NOT copied
into `archiso/airootfs/**` and NOT listed in `config/packages.x86_64`. They will
arrive from the signed `[ar0x]` repo in Phase 9. The five remaining packages are
deferred because their `/etc/skel/**` paths are already owned by the Phase 6/7
airootfs overlay — a second owner would cause `pacman: conflicting files`.

---

## 5. Environment variables (defined in `tools/lib/common.sh`, Phase 2)

| Variable | Default | Used by |
|---|---|---|
| `AR0X_SOURCE_ROOT` | `/home/user/ar0xOS` | all scripts |
| `AR0X_BUILD_ROOT` | `/opt/ar0x-build` | all scripts |
| `AR0X_PROFILE` | `$AR0X_SOURCE_ROOT/archiso` | canonical profile |
| `AR0X_PROFILE_STAGE` | `$AR0X_BUILD_ROOT/profile` | disposable staged profile used by `bootstrap.sh`; `mkarchiso` target |
| `AR0X_WORK_DIR` | `$AR0X_BUILD_ROOT/work` | `mkarchiso -w` |
| `AR0X_OUT_DIR` | `$AR0X_BUILD_ROOT/out` | `mkarchiso -o` |
| `AR0X_PKG_CACHE` | `$AR0X_BUILD_ROOT/cache/pacman/pkg` | `pacman.conf.build` `CacheDir` |
| `AR0X_REPO_DIR` | `$AR0X_BUILD_ROOT/repo/x86_64` | `repo-add` |
| `AR0X_KEYS_DIR` | `$AR0X_BUILD_ROOT/keys` | `gpg` |
| `AR0X_LOG_DIR` | `$AR0X_BUILD_ROOT/logs` | all scripts |
| `AR0X_SNAPSHOT_DATE` | `2026/11/01` | frozen archive mirror |
| `AR0X_VERSION` | `0.1.0` | artifact naming |
| `AR0X_ISO_LABEL` | `AR0X_010` | ISO volume label (≤ 32 chars for ISO9660) |

---

## 6. Disk & permission requirements (detailed in Phase 2)

| Path | Min free | Notes |
|---|---:|---|
| `/opt/ar0x-build/work` | 25 GB | mkarchiso squashfs staging; put on SSD/NVMe |
| `/opt/ar0x-build/cache` | 5 GB | pacman cache reused across builds |
| `/opt/ar0x-build/out` | 5 GB | 2 ISO generations retained |
| `/opt/ar0x-build/keys` | 1 MB | mode `0700`, owned by the release engineer |
| `/home/user/ar0xOS` | 200 MB | source tree only |

**Ownership rule:** build commands run as `root` (or via `sudo mkarchiso`), but all files under
`$AR0X_SOURCE_ROOT` must remain owned by the developer user. `tools/build-iso.sh` ends with
`chown -R "$SUDO_USER":"$SUDO_USER" "$AR0X_SOURCE_ROOT"` for any generated files that `mkarchiso`
may have written back into the checkout (e.g. `archiso/pacman.conf`).

---

## 7. What is deliberately NOT in this tree

- No `node_modules/`, no `venv/`, no compiled binaries — `ar0x-welcome` is pure Python + GTK4
  installed from a PKGBUILD, never vendored into Git. Its `gi` import is LAZY so
  `--self-test` works headless on a host with no GTK4.
- No PKGBUILD for the five Phase 9 packages (`ar0x-theme`, `ar0x-wallpapers`,
  `ar0x-hypr-config`, `ar0x-keyring`, `ar0x-meta`) — only a deferral README each.
  Writing one now would duplicate the ISO overlay's `/etc/skel/**` ownership.
- No ISO files, no `.pkg.tar.zst`, no squashfs images — all git-ignored (`.gitignore`).
- No private keys, ever. `keys/` lives only in BUILD ROOT.
- No `hyprland.conf` anywhere. ⚠️ Hyprland 0.57 requires `hyprland.lua`; a stray `.conf` is a
  build-breaking condition checked by `tools/validate-versions.sh`.
- No `archiso/airootfs/root/customize_airootfs.sh`. ⚠️ It is deprecated in archiso 92;
  `archiso/airootfs/etc/pacman.d/hooks/*.hook` is the supported customization path.
- No `*.gitkeep` in the staged profile — `bootstrap.sh` strips them before `mkarchiso`.
- No `*.patch` / `*.diff` in `config/kernel/patches/` — ⚠️ RISK-001, stock LTS only.
- No `config/system/wireplumber/` legacy dir — WirePlumber 0.5+ reads
  `/etc/pipewire/wireplumber.conf.d/`; `--check` fails if the 0.4 path returns.
- No passwordless `/etc/shadow` on an INSTALLED system — the LIVE-only file in
  `config/system/shadow` is replaced by Calamares with real hashed passwords.
- No `config/kernel/patches/*.patch` in v0.1 — custom kernel patching is RISK-001 and deferred.
