# ar0x 0.1.0 — Announcement Template (Phase 12)

> ⚠️ **DRAFT — DO NOT PUBLISH (RISK-054).** Every `{{PLACEHOLDER}}` must be
> filled from a REAL, signed, 40/40-tested release. No ISO, tag, fingerprint or
> SHA256 exists yet. Publishing this draft as-is would be a false claim.

---

**Title:** ar0x 0.1.0 "{{ ar0x root }}" is available

Today we are publishing the first ar0x stable ISO: `ar0x-0.1.0-x86_64.iso`,
`{{ISO_SIZE_BYTES}}` bytes, built from the frozen Arch snapshot `2026/11/01`
with archiso 92-1. ar0x is an Arch-based, Wayland-first developer distribution
running Hyprland 0.57.1 with a Lua-only config, stock `linux-lts 6.18.59-1`,
GRUB (UEFI) and isolinux (BIOS) boot, zsh, and a signed `[ar0x]` package repo
with `SigLevel = Required`.

The live ISO boots to SDDM and a Hyprland Wayland session. Calamares 3.4.3
(from Codeberg) installs offline to a target disk with auto or manual
partitioning; the first boot runs `ar0x-firstboot.service` and opens the GTK4
`ar0x-welcome` app.

**Download:** {{GITHUB_RELEASE_URL}}

**Artifacts (6):** `ar0x-0.1.0-x86_64.iso`, `SHA256SUMS`, `SHA256SUMS.sig`,
`ar0x-0.1.0-x86_64.iso.sig`, `CHANGELOG.md`, `README.md`.

**Release key fingerprint:** `{{RELEASE_FINGERPRINT_40HEX}}`
(published out of band in `README.md`; currently `PENDING-KEYGEN`).

**ISO SHA256:** `{{ISO_SHA256}}`

```bash
gpg --recv-keys {{RELEASE_FINGERPRINT_40HEX}}
gpg --verify SHA256SUMS.sig SHA256SUMS
sha256sum -c SHA256SUMS
gpg --verify ar0x-0.1.0-x86_64.iso.sig ar0x-0.1.0-x86_64.iso
```

**Known limitations:** single architecture (`x86_64`); Secure Boot is optional
and requires manual MOK enrollment; AppArmor ships in complain mode; no
bit-for-bit reproducible ISO yet; `repo.ar0x.dev` is a reserved endpoint.
Full 40-item checklist and sign-off: `docs/TESTING_CHECKLIST.md`.

**Links:** source <https://github.com/ar0x1/ar0xOS> · issues
<https://github.com/ar0x1/ar0xOS/issues> · docs
<https://github.com/ar0x1/ar0xOS/tree/main/docs> · community
<https://github.com/ar0x1/ar0xOS/discussions> · upstream
<https://wiki.archlinux.org/>

**EOL:** supported until the next stable release plus one month.
Release cadence: quarterly stable ISOs, continuous `testing` packages.

---

### Pre-publication checklist (all MANUAL)

1. `docs/TESTING_CHECKLIST.md` is **40/40 PASS (100%)** and signed off.
2. `gpg --verify SHA256SUMS.sig SHA256SUMS` + `sha256sum -c SHA256SUMS` PASS
   from a FRESH download.
3. The 40-hex fingerprint is published out of band (README, website, keyserver).
4. All 5 `AR0X_URL_*` endpoints pass `curl -IL` (RISK-050).
5. `gh release create` used `--verify-tag`; the git tag `v0.1.0` already exists.
6. Replace EVERY `{{PLACEHOLDER}}` above and delete this checklist + the DRAFT
   banner before sending.
