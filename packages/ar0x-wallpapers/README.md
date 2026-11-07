# ar0x-wallpapers — DEFERRED to Phase 9 (ADR-023)

**Status:** ⏳ skeleton only. Phase 8 intentionally ships just the three
user-facing tools (`ar0x-welcome`, `ar0x-update`, `ar0x-info`).

**Planned contents:** 3× 4K wallpapers, GRUB/Plymouth/syslinux/SDDM art, `ar0x-logo` hicolor icon.

**Why not built in Phase 8:** Art lives at `assets/wallpapers/**`, `assets/grub-theme/**`, `assets/plymouth/**`, `assets/sddm/**`, `assets/icons/**` and is staged by `build-kernel.sh`/`configure-branding.sh`/`configure-desktop.sh`.
Because the live ISO already contains those exact paths, a second package
owning them would make `pacman -U` fail with
`error: failed to commit transaction (conflicting files)` during a Calamares
install. Phase 9 must choose ONE owner per path (package OR airootfs overlay),
then write this PKGBUILD and re-run `tools/configure-tools.sh --check`.

**Do not** add a PKGBUILD here until that ownership decision is recorded in
`docs/architecture/DECISIONS.md`. Full rationale: `/home/user/ar0xOS/docs/TOOLS_GUIDE.md §8`.
