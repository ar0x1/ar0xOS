# ar0x

> **ar0x `0.1.0` "ar0x root"** — an Arch-based, Wayland-first developer
> distribution with a Cyberpunk / Dark-Hacker identity.
> ⚠️ **SOURCE-COMPLETE, RELEASE-PENDING.** No ISO has been built, booted, signed
> or published yet. Read the [status](#status) section before looking for a
> download link.

| | |
|---|---|
| Base | Arch Linux, rolling, frozen build snapshot `2026/11/01` |
| Init / kernel | systemd `v262.1`, stock `linux-lts 6.18.59-1` (zero patches) |
| Desktop | Hyprland `0.57.1` (Lua config), Waybar, SDDM `0.21.0-7` (Qt6 greeter) |
| Boot | GRUB (UEFI) + isolinux (BIOS); Secure Boot optional/manual |
| Installer | Calamares `3.4.3` from **Codeberg**, ar0x branding, auto + manual partitioning |
| Shell / tooling | zsh interactive, bash scripts, developer profile, `ar0x-info` / `ar0x-update` / `ar0x-welcome` |
| Packages | pacman + signed `[ar0x]` repo, `SigLevel = Required` |
| Target ISO | `ar0x-0.1.0-x86_64.iso`, ≤ 2.2 GB |
| License | docs/art: CC-BY-SA-4.0; code follows upstream Arch licenses |

---

## Status

Phases 1–12 of `PROJECT_PLAN.md` are **source-complete**: architecture,
archiso 92 profile, kernel/boot, system config, desktop, branding, custom
tools, package repository, Calamares installer, ISO build tooling and release
engineering all exist and pass their offline validators.

⚠️ **There is NO downloadable ISO.** The following are MANUAL gates that never
ran in the build sandbox (RISK-053/054):

- offline GPG release keygen (`RELEASE_KEY_FINGERPRINT = PENDING-KEYGEN`),
- building and publishing the signed `[ar0x]` package database,
- publishing the signed `[ar0x]` db (the ISO packages are then injected into the
  staged profile by `build-release.sh --run`, ADR-029),
- `mkarchiso` ISO build, QEMU BIOS/UEFI boots, real-hardware QA,
- all **40** items of `docs/TESTING_CHECKLIST.md` (currently 0/40),
- detached GPG signatures, GitHub Release `v0.1.0`, mirror uploads,
- DNS + TLS for the reserved `repo.ar0x.dev` endpoint.

Do not trust any third-party "ar0x 0.1.0 ISO" until a release fingerprint is
published **out of band** on this page and verified below.

## Make the ISO

All 12 phases are source-complete, but **no ISO exists here**: this sandbox has
no root, no `mkarchiso`/`pacman`/`gpg`, and no access to Arch package mirrors.
`tools/build-release.sh` therefore **fails closed** rather than fabricating a
non-bootable file. On a real Arch host (or the privileged Arch build container
in `docker/Dockerfile`), the whole automatable chain is one command:

```bash
# Step 0 (human, air-gapped): generate the offline release key and sign the
# [ar0x] repo — see docs/BUILD_RELEASE_ISO.md §2. Then:
sudo AR0X_CONFIRM_RELEASE_CHAIN=yes AR0X_CONFIRM_SIGNED_REPO=yes \
     AR0X_CONFIRM_BUILD=yes AR0X_CONFIRM_SIGN=yes \
     ./tools/build-release.sh --run
```

That stages the real mkarchiso profile, injects `calamares` + `ar0x-keyring` +
`ar0x-meta` from the signed `[ar0x]` repo into the **staged profile only**
(ADR-029), builds the ≤2.2 GiB ISO, writes `SHA256SUMS`, signs both artifacts
and verifies them. It **never tags, uploads or announces**. Full recipes
(Docker / Vagrant / native Arch / CI), the exact prerequisites and the MANUAL
40/40 QA that still follows: **[`docs/BUILD_RELEASE_ISO.md`](docs/BUILD_RELEASE_ISO.md)**.

Read-only helpers that work anywhere:
`./tools/build-release.sh --plan`, `--preflight`, `--check`, `--self-test`.

## Verifying a release (when one exists)

```bash
# 1. Import the release key using the 40-hex fingerprint published HERE.
gpg --recv-keys <RELEASE_FINGERPRINT>       # PENDING-KEYGEN — not published yet
# 2. Verify the checksum list and its detached signature.
gpg --verify SHA256SUMS.sig SHA256SUMS
sha256sum -c SHA256SUMS
# 3. Verify the ISO's own detached signature.
gpg --verify ar0x-0.1.0-x86_64.iso.sig ar0x-0.1.0-x86_64.iso
```

Release fingerprint: **`PENDING-KEYGEN`** (placeholder — never accept a release
whose key is not published here out of band). RISK-051.

## Build it yourself (real Arch host required)

```bash
git clone https://github.com/ar0x1/ar0xOS.git && cd ar0xOS
./tools/validate-versions.sh                 # offline gates
./tools/bootstrap.sh --check
./tools/build-iso.sh --preflight            # host prerequisites
# MANUAL: keygen -> build/sign/publish [ar0x] -> add calamares + ar0x-meta
sudo AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build
./tools/checksum.sh --create && ./tools/checksum.sh --verify
./tools/build-iso.sh --qemu-bios out/ar0x-0.1.0-x86_64.iso
./tools/build-iso.sh --qemu-uefi out/ar0x-0.1.0-x86_64.iso
```

⚠️ **RISK-004:** before any install, run `lsblk -o NAME,SIZE,MODEL,TRAN` and
TYPE the target device; use a disposable VM disk only.

## Documentation

| Document | Contents |
|---|---|
| [`PROJECT_PLAN.md`](PROJECT_PLAN.md) | Contract for all 12 phases |
| [`docs/BOOTSTRAP_GUIDE.md`](docs/BOOTSTRAP_GUIDE.md) | archiso 92 profile + build host |
| [`docs/SYSTEM_CONFIG.md`](docs/SYSTEM_CONFIG.md) | systemd, network, security posture |
| [`docs/DESKTOP_GUIDE.md`](docs/DESKTOP_GUIDE.md) | Hyprland Lua, SDDM, theming |
| [`docs/BRANDING_GUIDE.md`](docs/BRANDING_GUIDE.md) | ar0x-only naming, palette, art |
| [`docs/TOOLS_GUIDE.md`](docs/TOOLS_GUIDE.md) | welcome / update / info tools |
| [`docs/REPO_GUIDE.md`](docs/REPO_GUIDE.md) | `[ar0x]` keygen, build, sign, publish |
| [`docs/INSTALLER_FLOW.md`](docs/INSTALLER_FLOW.md) | Calamares wizard + first boot |
| [`docs/ISO_BUILD_GUIDE.md`](docs/ISO_BUILD_GUIDE.md) | ISO build, size gate, QEMU/VBox/VMware |
| [`docs/TESTING_CHECKLIST.md`](docs/TESTING_CHECKLIST.md) | 40-item / 100% release gate |
| [`docs/RELEASE_GUIDE.md`](docs/RELEASE_GUIDE.md) | tag, signatures, mirrors, announcement |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | v0.2 / v1.0 planning |
| [`CHANGELOG.md`](CHANGELOG.md) | release notes template |

## Links

- Source: <https://github.com/ar0x1/ar0xOS>
- Issues: <https://github.com/ar0x1/ar0xOS/issues>
- Discussions: <https://github.com/ar0x1/ar0xOS/discussions>
- Docs: <https://github.com/ar0x1/ar0xOS/tree/main/docs>
- Upstream: <https://wiki.archlinux.org/>

⚠️ RISK-050: the five endpoints above are RESERVED; `/tree/main/docs` resolves
only after the PR is merged. Verify all with `curl -IL` at release time.
