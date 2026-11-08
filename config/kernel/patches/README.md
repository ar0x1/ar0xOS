# /home/user/ar0xOS/config/kernel/patches/README.md

## Phase 1 — deliberately EMPTY for ar0x v0.1.0

v0.1 ships the **unmodified, signed Arch `linux-lts 6.18.59-1`** package. No `.patch` or
`.diff` files belong in this directory.

### ⚠️ RISK-001 — read before adding anything here

Applying out-of-tree patches or a hand-edited `.config` can produce an **unbootable ISO**.
`tools/validate-versions.sh` FAILS the build if `AR0X_CUSTOM_KERNEL_PATCHES != none` or if
any `*.patch` / `*.diff` file appears in this directory.

If a future release (v0.2+) needs a custom kernel, ALL of the following are mandatory:
1. A second, known-good stock kernel must remain in the ISO as a fallback boot entry.
2. Every patch must be named `NNNN-short-description.patch`, apply cleanly with
   `patch -p1 --dry-run`, and carry a header explaining why it is needed upstream.
3. `tools/build-kernel.sh` must be run manually with `--i-accept-the-risk`.
4. The kernel and GRUB binaries must be re-signed for the optional Secure Boot path.
5. Phase 11 must re-run BOTH the UEFI and BIOS QEMU boot tests.

`config/kernel/ar0x-lts.config` (Phase 4) is a **reference/diff document only** — it is not
applied to the v0.1 kernel package.
