# ar0x-keyring — DEFERRED to Phase 9 (ADR-023)

**Status:** ⏳ skeleton only. Phase 8 intentionally ships just the three
user-facing tools (`ar0x-welcome`, `ar0x-update`, `ar0x-info`).

**Planned contents:** `/usr/share/pacman/keyrings/ar0x.gpg` + trust bootstrap.

**Why not built in Phase 8:** Needs the OFFLINE GPG key created in Phase 9 (node R1, `/opt/ar0x-build/keys/`, mode 0700). No key may ever be committed to Git.
Because the live ISO already contains those exact paths, a second package
owning them would make `pacman -U` fail with
`error: failed to commit transaction (conflicting files)` during a Calamares
install. Phase 9 must choose ONE owner per path (package OR airootfs overlay),
then write this PKGBUILD and re-run `tools/configure-tools.sh --check`.

**Do not** add a PKGBUILD here until that ownership decision is recorded in
`docs/architecture/DECISIONS.md`. Full rationale: `/home/user/ar0xOS/docs/TOOLS_GUIDE.md §8`.
