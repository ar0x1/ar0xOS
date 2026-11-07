# /home/user/ar0xOS/packages/ — ar0x PKGBUILD workspace

**Phase 9 status: ALL EIGHT packages have real PKGBUILDs.** Every file here is
a SOURCE; no `.pkg.tar.zst`, `.sig`, db or private key is ever committed
(`.gitignore` excludes `*.pkg.tar.zst*`, `*.db.tar.*`, `*.asc`, `*.gpg`, `keys/`).

| Directory | Phase | Status | Installed files |
|---|---|---|---|
| `ar0x-info/` | 8 | ✅ COMPLETE | `/usr/bin/ar0x-info`, `.desktop`, `/usr/share/ar0x/info/**` |
| `ar0x-update/` | 8 | ✅ COMPLETE | `/usr/bin/ar0x-update`, `.desktop`, `/etc/ar0x/update.conf` |
| `ar0x-welcome/` | 8 | ✅ COMPLETE | `/usr/bin/ar0x-welcome`, `.desktop`, CSS, tables, 2 units, 2 helpers, scriptlet |
| `ar0x-theme/` | 9 | ✅ COMPLETE | `/usr/share/ar0x/theme/**`, `/usr/bin/ar0x-apply-theme` |
| `ar0x-wallpapers/` | 9 | ✅ COMPLETE | `/usr/share/ar0x/wallpapers/**`, `/usr/bin/ar0x-apply-wallpapers` |
| `ar0x-hypr-config/` | 9 | ✅ COMPLETE | `/usr/share/ar0x/hypr-config/**`, `/usr/bin/ar0x-apply-hypr-config` |
| `ar0x-keyring/` | 9 | ✅ COMPLETE | `/usr/share/pacman/keyrings/ar0x.{gpg,trusted,revoked}`, `.install`, doc snippet |
| `ar0x-meta/` | 9 | ✅ COMPLETE | `/usr/share/doc/ar0x-meta/RELEASE` (depends on the 7 above) |

## ⚠️ ONE OWNER PER PATH (ADR-024 — resolves ADR-023's P8 deferral)

The live ISO already owns `/etc/skel/.config/**`, `/usr/share/backgrounds/ar0x/**`,
`/usr/share/plymouth/themes/ar0x/**`, `/usr/share/grub/themes/ar0x/**`,
`/usr/share/sddm/themes/ar0x/**`, `/usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg`
and `/usr/share/ar0x/{branding,logo}/**` through the Phase 6/7 airootfs overlay.
**Decision: the overlay keeps those paths; the four payload packages install
PACKAGE-PRIVATE reference trees under `/usr/share/ar0x/<pkg>/**` plus
`/usr/bin/ar0x-apply-*` helpers.** No path has two owners, so `pacman -U`
can never report `conflicting files` during a Calamares install.
`tools/lib/ar0x_pkgbuild.py::validate_ownership()` FAILS the build if any PKGBUILD
tries to install into an overlay-owned path (`ar0x_repo.py` re-checks the same
rule as part of its Phase 9 gate chain).

`ar0x-keyring` needs the **MANUAL** `sudo ./tools/setup-repo.sh --keygen` step
before it can be built: `ar0x-public-key.asc` is generated, gitignored, and its
PKGBUILD checksum is `SKIP` until `--sync` replaces it with a real SHA-256.

## Commands

```bash
./tools/setup-repo.sh --check        # read-only, no root/network
./tools/setup-repo.sh --sync         # mirrors + all 8 PKGBUILD checksums
./tools/setup-repo.sh --self-test    # offline pure-logic + mock repo tests
sudo ./tools/setup-repo.sh --keygen  # ⚠️ MANUAL, air-gapped GPG key
AR0X_CONFIRM_BUILD=yes ./tools/setup-repo.sh --build   # ⚠️ MANUAL, Arch host
sudo ./tools/setup-repo.sh --sign    # ⚠️ MANUAL, needs the private key
./tools/setup-repo.sh --verify <DIR>  # validate a built signed repo tree
./tools/setup-repo.sh --publish      # stages build/repo-publish (NO upload)
```

Full guide: `/home/user/ar0xOS/docs/REPO_GUIDE.md`.
