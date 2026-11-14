<div align="center">

<h1>ar0xOS</h1>

<p><strong>Arch at the core. ar0x at the surface.</strong></p>

<img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&weight=600&size=17&duration=2800&pause=900&color=9B8CFF&center=true&vCenter=true&width=620&lines=A+Wayland-first+Linux+experience.;Built+on+Arch.+Shaped+by+ar0x.;A+darker+environment+for+developers." alt="ar0xOS animated tagline" />

<br />

<p>
  <img src="https://img.shields.io/badge/BASE-ARCH_LINUX-1793D1?style=for-the-badge&logo=archlinux&logoColor=white" alt="Arch Linux" />
  <img src="https://img.shields.io/badge/DISPLAY-WAYLAND-FFBC00?style=for-the-badge&logo=wayland&logoColor=111111" alt="Wayland" />
  <img src="https://img.shields.io/badge/WM-HYPRLAND-58E1FF?style=for-the-badge&logo=hyprland&logoColor=111111" alt="Hyprland" />
  <img src="https://img.shields.io/badge/STATUS-RELEASE_PENDING-F0A33A?style=for-the-badge" alt="Release pending" />
</p>

<p>
  <img src="https://img.shields.io/badge/CODE-MIT-8B7CFF?style=for-the-badge" alt="MIT License for original ar0xOS code" />
  <img src="https://img.shields.io/badge/DOCS%20%26%20ART-CC%20BY--SA%204.0-6B7280?style=for-the-badge" alt="CC BY-SA 4.0 for documentation and artwork" />
</p>

<p>
  <a href="https://github.com/ar0x1/ar0xOS"><img src="https://img.shields.io/badge/SOURCE-GitHub-181717?style=flat-square&logo=github" alt="Source" /></a>
  <a href="https://github.com/ar0x1/ar0xOS/issues"><img src="https://img.shields.io/badge/ISSUES-Report-8B7CFF?style=flat-square&logo=github" alt="Issues" /></a>
  <a href="https://github.com/ar0x1/ar0xOS/blob/main/PROJECT_PLAN.md"><img src="https://img.shields.io/badge/ROADMAP-View-8B7CFF?style=flat-square" alt="Roadmap" /></a>
</p>

<p>
  <img src="https://img.shields.io/github/stars/ar0x1/ar0xOS?style=flat-square&logo=github&label=stars" alt="GitHub stars" />
  <img src="https://img.shields.io/github/forks/ar0x1/ar0xOS?style=flat-square&logo=github&label=forks" alt="GitHub forks" />
  <img src="https://img.shields.io/github/last-commit/ar0x1/ar0xOS?style=flat-square&logo=git&label=last%20commit" alt="Last commit" />
</p>

</div>

---

> **Release notice:** `ar0xOS 0.1.0` is source-complete, but release-pending. No ISO has been built, booted, signed, or published yet. There is currently **no download**. A release will be announced here only after the build, boot tests, QA, and signing steps are complete.

## `01 / Overview`

**ar0xOS** is an Arch-based, rolling Linux distribution with a **Wayland-first Hyprland desktop** and a cyberpunk / dark-hacker identity. It brings together a curated developer environment, custom ar0x utilities, and a branded graphical installer.

*Arch power. A focused desktop. An identity of its own.*

## `02 / The setup`

| Component | Stack |
|:--|:--|
| Base | Arch Linux · rolling snapshot `2026-11-01` |
| Desktop | Hyprland `0.57.1` · Waybar |
| Display | Wayland |
| Login | SDDM `0.21.0` · Qt6 greeter |
| Init | systemd `262.1` |
| Kernel | Stock `linux-lts 6.18.59-1` · unpatched |
| Boot | GRUB (UEFI) · isolinux (BIOS) |
| Installer | Calamares `3.4.3` · branded workflow |
| Shell | zsh · Bash tooling |
| Package layer | pacman · signed `[ar0x]` repository (release setup pending) |

## `03 / Built in`

- **Hyprland desktop** — a Wayland-first workspace with Waybar and a consistent ar0x visual theme.
- **Custom utilities** — `ar0x-welcome`, `ar0x-update`, and `ar0x-info`.
- **Graphical installer** — Calamares with automatic and manual partitioning flows.
- **Release tooling** — ArchISO profile, build checks, checksum generation, and signing workflow.
- **Package foundation** — a planned signed `[ar0x]` repository with signature verification required.

## `04 / Build from source`

Building the ISO requires a real **Arch Linux host** or a privileged Arch build container, at least **8 GB RAM**, and **40 GB free disk space**. The release key and signed package repository setup are manual prerequisites. Follow the full guide before running a release build.

```bash
git clone https://github.com/ar0x1/ar0xOS.git
cd ar0xOS

./tools/validate-versions.sh
./tools/bootstrap.sh --check
./tools/build-iso.sh --preflight
```

After completing the manual signing and repository steps documented in the build guide:

```bash
sudo AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build
./tools/checksum.sh --create
./tools/checksum.sh --verify
```

**Build guide:** [`docs/BUILD_RELEASE_ISO.md`](docs/BUILD_RELEASE_ISO.md)

> Use a disposable virtual machine for boot testing. Do not point installation or disk-writing steps at a device containing data you need.

## `05 / Release checklist`

The project structure and build tooling are in place. These release gates are still outstanding:

- [ ] Generate and publish the offline GPG release-key fingerprint.
- [ ] Build and publish the signed `[ar0x]` package repository.
- [ ] Build the ISO and test UEFI + BIOS boot paths.
- [ ] Complete the 40-point QA checklist and real-hardware checks.
- [ ] Sign the release artifacts and publish the GitHub release.

Until the fingerprint is published in this repository, do not trust third-party images claiming to be an official `ar0xOS` release.

## `06 / Project docs`

| Guide | What it covers |
|:--|:--|
| [`PROJECT_PLAN.md`](PROJECT_PLAN.md) | Project architecture and phase plan |
| [`docs/DESKTOP_GUIDE.md`](docs/DESKTOP_GUIDE.md) | Hyprland, Waybar, SDDM, and desktop setup |
| [`docs/SYSTEM_CONFIG.md`](docs/SYSTEM_CONFIG.md) | Core system configuration |
| [`docs/TOOLS_GUIDE.md`](docs/TOOLS_GUIDE.md) | ar0x command-line utilities |
| [`docs/BUILD_RELEASE_ISO.md`](docs/BUILD_RELEASE_ISO.md) | Host requirements and ISO build process |
| [`docs/TESTING_CHECKLIST.md`](docs/TESTING_CHECKLIST.md) | Release QA checklist |
| [`docs/RELEASE_GUIDE.md`](docs/RELEASE_GUIDE.md) | Signing and release process |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Upcoming milestones |

## `07 / License & credits`

Original **ar0xOS code** is licensed under the **MIT License**. Documentation and artwork are licensed under **CC BY-SA 4.0**. Third-party and bundled components retain their respective upstream licenses; see the relevant project files for details.

Built by **[ar0x](https://github.com/ar0x1)** · [Repository](https://github.com/ar0x1/ar0xOS) · [Issues](https://github.com/ar0x1/ar0xOS/issues)

---

<div align="center">

`ar0xOS` · `0.1.0` · **Arch, with an ar0x identity.**

</div>
