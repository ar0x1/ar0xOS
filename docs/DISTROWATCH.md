# DistroWatch Submission Draft (Phase 12)

> ⚠️ **DRAFT — DO NOT SEND (RISK-054).** A signed, verified ISO must exist
> before submission. DistroWatch asks for an **email** containing exactly four
> pieces of information: project name, website URL, a brief description
> (including the base distribution), and a direct link to the installation
> media. New submissions go on a **waiting list** and are mentioned in
> DistroWatch Weekly; they are not added to the database immediately.
> Source: <https://distrowatch.com/dwres.php?resource=submit>.
> Re-check the live policy and recipient before sending.

---

**To:** `{{DISTROWATCH_SUBMISSION_CONTACT}}` (RESERVED-MANUAL — verify on the
live DistroWatch "Submit New Distribution" page)
**Subject:** New distribution submission: ar0x

Hello DistroWatch team,

**1. Project name:** ar0x

**2. Website:** <https://github.com/ar0x1/ar0xOS>
(planned dedicated site: `{{PROJECT_WEBSITE_URL}}` — RESERVED, DNS/TLS MANUAL)

**3. Description:** ar0x is an Arch-based, rolling-release, developer-oriented
Linux distribution **based on Arch Linux**. It ships a Wayland-first Hyprland
0.57 desktop with a Lua-only configuration, the stock Arch `linux-lts` kernel,
systemd, GRUB (UEFI) + isolinux (BIOS), zsh, and its own signed `[ar0x]`
package repository (`SigLevel = Required`). The live ISO installs offline via
Calamares 3.4.3 with auto or manual partitioning. The current release is
`0.1.0`, codename "ar0x root", built from a frozen `2026/11/01` Arch snapshot.

**4. Installation media (direct ISO link):**
`{{DIRECT_ISO_URL}}` — RESERVED until GitHub Release `v0.1.0` publishes
`ar0x-0.1.0-x86_64.iso` with `SHA256SUMS`, `SHA256SUMS.sig` and a detached
ISO signature.

Additional context (not a substitute for the four required fields):

| Field | Value |
|---|---|
| Version | `0.1.0` / tag `v0.1.0` |
| Architecture | `x86_64` only |
| ISO size | ≤ 2.2 GB (`{{ISO_SIZE_BYTES}}` bytes) |
| Desktop | Hyprland + Waybar + SDDM |
| Installer | Calamares 3.4.3 (Codeberg) |
| Package manager | pacman + signed `[ar0x]` |
| Release FPR | `{{RELEASE_FINGERPRINT_40HEX}}` (currently `PENDING-KEYGEN`) |
| Documentation | <https://github.com/ar0x1/ar0xOS/tree/main/docs> |
| Issue tracker | <https://github.com/ar0x1/ar0xOS/issues> |
| EOL | next stable + 1 month |
| Cadence | quarterly stable ISOs |

We understand that new projects are placed on the waiting list and require
long-term maintenance (package listings, screenshots, news, link checks).
Thank you for your time.

— ar0x maintainers

---

### Pre-send gates (all MANUAL)

- [ ] Signed ISO + all 6 artifacts published on GitHub Releases.
- [ ] `docs/TESTING_CHECKLIST.md` at **100%**.
- [ ] `{{DIRECT_ISO_URL}}` returns HTTP 200 via `curl -IL`.
- [ ] Live DistroWatch policy + recipient re-checked; RESERVED placeholders
      replaced; the DRAFT banner removed.
- [ ] Sent email archived as evidence (no reply is expected).
