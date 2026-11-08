# ar0x Roadmap Template (Phase 12)

> ⚠️ **PLANNING ONLY (RISK-054).** Nothing below is scheduled, funded or
> committed. Dates are deliberately omitted — v0.1.0 has not been released and
> the 40-item `docs/TESTING_CHECKLIST.md` is 0/40. This is the template the
> maintainers fill in AFTER the first signed release.

## v0.1.x — maintenance (after `v0.1.0`)

- Signed `[ar0x]` security updates; quarterly stable ISO refreshes.
- `repo.ar0x.dev` DNS + TLS, mirror redundancy, `curl -IL` monitoring of all
  5 `AR0X_URL_*` endpoints (RISK-050).
- Real-hardware WiFi/Bluetooth/audio/GPU/screen-capture regression matrix.
- `namcap`, `shellcheck`, `desktop-file-validate`, `systemd-analyze verify`
  in CI on a real Arch host (RISK-049).
- Key rotation + revocation runbook (`ar0x-revoked`), out-of-band FPR
  publication (RISK-051).

## v0.2 — candidates from the residual risk statement

- **Bit-for-bit reproducible ISO** (`AR0X_REPRODUCIBLE` is currently
  `package-level`; extend to full ISO with a pinned toolchain + `SOURCE_DATE_EPOCH`).
- **AppArmor enforcing** opt-in after portal/screen-share QA (RISK-008).
- **Secure Boot** shim + documented MOK enrollment flow (RISK-007).
- **Wayland-native greeter** (`greetd` + `gtkgreet`) for NVIDIA/Wayland-only
  setups, replacing the X11 SDDM greeter (RISK-009).
- **btrfs snapshot** integration + rollback for `ar0x-update --upgrade`.
- **hyprcursor** compiled cursor theme (ADR-022 deferred).
- Full custom GTK/Qt theme engine (ADR-021 deferred), light-theme
  accessibility variant (ADR-015 deferred).
- Multi-arch (aarch64) investigation; curated `ar0x-firmware-extras` for
  real-hardware WiFi (RISK-005).

## v1.0 — candidates

- Stable, signed, published release with a **100%** automated QEMU + hardware
  checklist and a public release-key ceremony.
- Primary + secondary mirrors with automatic verification, DistroWatch listing,
  a dedicated website and community forums/mailing lists.
- Installer: unattended-default install proven on UEFI + BIOS + real hardware;
  first-boot `ar0x-welcome` QA automated.
- Long-term support policy, CVE response process, reproducible build attestation.

## Explicit non-goals carried forward from v0.1

- No custom/patched kernel (RISK-001), no AUR/`*-git`/`*-bin`/`[extra-testing]`
  packages in the ISO (RISK-010), no CLI-only installer, no systemd-boot or
  rEFInd, no Alpine/musl/LFS base, no GNOME/libadwaita desktop, no automatic
  disk selection (RISK-004), no unsigned release artifacts (RISK-051).

---

**How to use this template:** after each release, move delivered items into
`CHANGELOG.md`, add a dated section here, and keep every unreleased item
traceable to a `RISK-*` ID or an `ADR-*` decision in
`docs/architecture/`.
