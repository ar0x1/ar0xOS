# /home/user/ar0xOS/config/kernel/ — Kernel policy (Phase 4)

## ⚠️⚠️ RISK-001 — READ THIS BEFORE PATCHING ANYTHING ⚠️⚠️

**ar0x v0.1 applies ZERO kernel patches and does NOT compile a custom kernel.**
The user selected **Stock LTS**. The kernel is the `linux-lts 6.18.59-1` binary
package from `[core]` at the frozen `2026/11/01` snapshot.

Why no patches, even "small" ones:

| Temptation | Real consequence |
|---|---|
| "Just one small patch for X" | You own a kernel fork forever. Every LTS point release must be rebased, re-reviewed, re-signed and re-QA'd. |
| Out-of-tree patch for NVIDIA / Wi-Fi | Breaks on the next `linux-lts` bump; DKMS rebuild failures at boot can leave the ISO unbootable. |
| Custom `.config` + `make -j$(nproc)` | 15–40 min per build, ~200 MB toolchain, non-reproducible `localversion`, and you lose Arch's tested module set. |
| Enabling `CONFIG_*` that Arch left off | Requires rebuilding the whole kernel; a wrong `CONFIG_EFI_STUB` / `CONFIG_RD_ZSTD` produces a blank screen on UEFI. |

**Arch already patches its own LTS kernel.** The `6.18.59-1` packaging tag in
`archlinux/packaging/packages/linux-lts` contains three maintainer patches
(`0001-add-sysctl-to-allow-disabling-unprivileged-CLONE_NEW.patch` and two
`drm-amdgpu` GFP fixes). Those are upstream-Arch decisions, reviewed and signed
by Arch — ar0x inherits them and adds nothing. `config/kernel/patches/` stays
**empty** in v0.1 (only `README.md` + `.gitkeep`).

If a future release needs a patch, the process is: (1) open an ADR, (2) store the
patch under `config/kernel/patches/`, (3) add a `PKGBUILD` that rebuilds
`linux-lts` in a clean chroot, (4) re-sign, (5) re-run the Phase 11 QEMU
UEFI+BIOS matrix. **That is a separate phase, not a quick edit.**

## What Phase 4 actually does instead

1. `ar0x-lts.config` is an **audit fragment**, not a build input. It lists the
   exact `CONFIG_*` symbols the Wayland/PipeWire/AppArmor/live-ISO stack requires,
   with the `make menuconfig` path for each one.
2. `tools/build-kernel.sh --check` validates that fragment against a real kernel
   config (`/proc/config.gz`, `/boot/config-linux-lts`, or a file passed with
   `--config FILE`) and fails the build if a required symbol is missing.
3. `tools/build-kernel.sh --lock-config` downloads the **complete** frozen
   `config.x86_64` from the `6.18.59-1` packaging tag and writes
   `/opt/ar0x-build/out/kernel-config.lock` — a reproducible record of the exact
   stock kernel ar0x shipped.
4. `config/mkinitcpio.conf` + `config/mkinitcpio.d/linux-lts.preset` configure the
   **initramfs** (adds the `plymouth` hook), which is a supported, reversible
   change that does not touch the kernel image.
5. GRUB / Plymouth / syslinux themes are pure artwork — no kernel involvement.

## Where the full `.config` comes from

| Source | Path / URL |
|---|---|
| Installed system (authoritative at runtime) | `/boot/config-linux-lts` or `zcat /proc/config.gz` (the pinned kernel has `CONFIG_IKCONFIG=y` and `CONFIG_IKCONFIG_PROC=y`) |
| Frozen upstream packaging config | `https://gitlab.archlinux.org/archlinux/packaging/packages/linux-lts/-/raw/6.18.59-1/config.x86_64` |
| Locked copy produced by Phase 4 | `/opt/ar0x-build/out/kernel-config.lock` |

⚠️ The upstream `config.x86_64` header at tag `6.18.59-1` reads
`# Linux/x86 6.18.57 Kernel Configuration` — a packaging artefact (the config
file was not re-generated for that point release). We pin the **package version**
`6.18.59-1`, not the string in that header. `[core] 6.18.59-1` is the frozen
snapshot pin; `6.18.60-*` lives in testing and must NOT be used.

## Audit-fragment value convention

`ar0x-lts.config` uses valid kernel-config syntax, but it is interpreted by
`build-kernel.sh` as a *requirement*, not a build recipe:

| Declared value | Requirement on the real config |
|---|---|
| `CONFIG_FOO=y` | must be exactly `=y` (built-in) |
| `CONFIG_FOO=m` | must be `=y` **or** `=m` (built-in or loadable module) |
| `# CONFIG_FOO is not set` | must be unset |

Using `=m` for most entries is deliberate: Arch builds most drivers as modules,
and "built-in" satisfies the same requirement. Only symbols verified as `=y` in
the actual `6.18.59-1` `config.x86_64` are asserted as `=y`.
