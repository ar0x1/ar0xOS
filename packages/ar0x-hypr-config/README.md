# ar0x-hypr-config — DEFERRED to Phase 9 (ADR-023)

**Status:** ⏳ skeleton only. Phase 8 intentionally ships just the three
user-facing tools (`ar0x-welcome`, `ar0x-update`, `ar0x-info`).

**Planned contents:** `/etc/skel/.config/hypr/hyprland.lua` + 10 Lua modules.

**Why not built in Phase 8:** Sources live at `config/desktop/hypr/**`; `tools/configure-desktop.sh --sync` renders them into `/etc/skel/.config/hypr/`.
Because the live ISO already contains those exact paths, a second package
owning them would make `pacman -U` fail with
`error: failed to commit transaction (conflicting files)` during a Calamares
install. Phase 9 must choose ONE owner per path (package OR airootfs overlay),
then write this PKGBUILD and re-run `tools/configure-tools.sh --check`.

**Do not** add a PKGBUILD here until that ownership decision is recorded in
`docs/architecture/DECISIONS.md`. Full rationale: `/home/user/ar0xOS/docs/TOOLS_GUIDE.md §8`.
