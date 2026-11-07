# ar0x-meta — DEFERRED to Phase 9 (ADR-023)

**Status:** ⏳ skeleton only. Phase 8 intentionally ships just the three
user-facing tools (`ar0x-welcome`, `ar0x-update`, `ar0x-info`).

**Planned contents:** meta-package depending on the standard ar0x experience.

**Why not built in Phase 8:** Depends on the four packages above plus `ar0x-welcome`/`ar0x-update`/`ar0x-info`; must be written AFTER the ownership decision below.
Because the live ISO already contains those exact paths, a second package
owning them would make `pacman -U` fail with
`error: failed to commit transaction (conflicting files)` during a Calamares
install. Phase 9 must choose ONE owner per path (package OR airootfs overlay),
then write this PKGBUILD and re-run `tools/configure-tools.sh --check`.

**Do not** add a PKGBUILD here until that ownership decision is recorded in
`docs/architecture/DECISIONS.md`. Full rationale: `/home/user/ar0xOS/docs/TOOLS_GUIDE.md §8`.
