# Changelog

All notable changes to ar0x are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/) with `MAJOR.MINOR.PATCH`
versions; ISO tags are `vX.Y.Z` (`PROJECT_PLAN.md §11`).

> ⚠️ **TEMPLATE, NOT A RELEASE ANNOUNCEMENT (RISK-054).** The `0.1.0` entry
> below describes **source deliverables**, not a shipped ISO. No ISO was built,
> booted, hashed, signed or published; the release key is `PENDING-KEYGEN` and
> `docs/TESTING_CHECKLIST.md` is 0/40. Do not tag `v0.1.0` until every MANUAL
> gate in `docs/RELEASE_GUIDE.md §2` is complete.

## [0.1.0] — ar0x root — UNRELEASED

### Added

- P1–P2: architecture contract, 5 architecture docs, version pins, build host
  tooling (Docker/Vagrant), archiso `92-1` correction, ADR-017.
- P3: complete archiso 92 profile, frozen `2026/11/01` snapshot, `bootstrap.sh`.
- P4: stock `linux-lts 6.18.59-1`, **zero kernel patches** (RISK-001), GRUB +
  Plymouth + syslinux themes, FAILSAFE boot entries.
- P5: NetworkManager, PipeWire/WirePlumber 0.5+, Wayland env, nftables,
  AppArmor complain, rolling installed `pacman.conf` (RISK-006).
- P6: Hyprland 0.57 **Lua** config (10 modules), Waybar, Qt6 SDDM theme,
  GTK3/GTK4/Qt theming, 3 wallpapers, `/etc/skel` dotfiles.
- P7: ar0x logo/wordmark SVGs, real XCursor theme, ASCII identity, GRUB/SDDM
  boot art, `ar0x-cursors` (RISK-040 closed).
- P8: GTK4 `ar0x-welcome`, non-root `ar0x-update`, `ar0x-info`, 3 `.desktop`
  files, 2 systemd units, RISK-013 first-boot guard.
- P9: all **8** ar0x PKGBUILDs (57/57 SHA-256 sums, 31 byte-identical
  mirrors), ADR-024 one-owner-per-path, `config/repo/**`, 3 PR-safe/signing CI
  workflows, `docs/REPO_GUIDE.md`.
- P10: Calamares 3.4.3 `settings.conf` (show/exec/show, 22 exec jobs, 3
  instances), **21** module configs, ar0x QML branding, first-boot symlink
  arming, `tools/configure-installer.sh`, `docs/INSTALLER_FLOW.md`.
- P11: `tools/build-iso.sh`, `tools/checksum.sh`, `tools/lib/ar0x_iso.py`,
  `config/iso/**` (2.2 GiB gate, 8 budget rows, 3 QEMU launchers),
  `docs/ISO_BUILD_GUIDE.md`, **40-item** `docs/TESTING_CHECKLIST.md`.
- P12: `README.md`, this changelog, `config/release/**`, announcement and
  DistroWatch drafts, roadmap, `tools/prepare-release.sh`,
  `tools/lib/ar0x_release.py`, `docs/RELEASE_GUIDE.md`.

### Naming

- Human codename `ar0x root`, machine slug `ar0x-root`, boot label `AR0X ROOT`,
  wallpaper `ar0x-grid.png`; whole-tree naming gate (ADR-025).

### Security

- Installed `[ar0x] SigLevel = Required`; build-only `Optional TrustAll`.
- No private key, passphrase or `*.gpg`/`*.asc` artifact in Git (RISK-051).
- Live `ar0x` user has an empty password on the ISO **only**; `removeuser` +
  `ar0x-installer-finish` refuse any surviving `NOPASSWD` (RISK-013/033).

### Known limitations / MANUAL gates

- Offline release key `PENDING-KEYGEN`; no signed `[ar0x]` db, no publication.
- `calamares` + `ar0x-meta` are NOT yet in `config/packages.x86_64`.
- No `mkarchiso`, QEMU, `gpg`, KVM, loop devices or root in the build sandbox;
  no ISO, no detached signature, no 40/40 checklist, no real-hardware QA
  (RISK-052/053/054).
- `repo.ar0x.dev` DNS + TLS and all 5 `AR0X_URL_*` endpoints are RESERVED
  (RISK-050).
- v0.1 is single-arch (`x86_64`), Secure Boot optional, AppArmor complain,
  no bit-for-bit ISO reproducibility.

## [Unreleased]

_See [`docs/ROADMAP.md`](docs/ROADMAP.md) for v0.2 / v1.0 candidates._
