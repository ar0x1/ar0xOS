# ar0x 0.1.0 — ISO Testing Checklist (Phase 11)

**Artifact:** `ar0x-0.1.0-x86_64.iso` (`AR0X_010`) · archiso `92-1` ·
frozen snapshot `2026/11/01` · size gate **2.2 GB** (`2362232012` bytes) ·
GRUB/UEFI + isolinux/BIOS.

> **Exit gate: 100% of the 40 items below must be PASS.** Any FAIL blocks the
> `v0.1.0` tag. Items are ordered; do not skip ahead.
>
> ⚠️ **RISK-053 (HIGH):** NO ISO was built, booted, hashed or signed in this
> sandbox. `mkarchiso`, `qemu-system-x86_64`, `qemu-img`, `edk2-ovmf`,
> `xorriso`, `gpg`, KVM, loop devices and root are all absent. This document is
> a **procedure**, not a test result. All 40 boxes are deliberately unchecked.
>
> ⚠️ **RISK-048 / RISK-051 (CRITICAL):** the offline release key is
> `PENDING-KEYGEN` and the signed `[ar0x]` db does not exist. `calamares` and
> `ar0x-meta` are STILL absent from `config/packages.x86_64`, so
> `tools/build-iso.sh --build` **REFUSES** until the MANUAL
> `--keygen → --build → --sign → publish` chain completes.
>
> ⚠️ **RISK-052:** the Calamares GUI was never rendered (Phase 10). This is
> where acceptance criterion 3 is finally exercised.
>
> ⚠️ **RISK-004 (CRITICAL, irreversible):** before ANY install run
> `lsblk -o NAME,SIZE,MODEL,TRAN` and TYPE the target device. Use a disposable
> QEMU qcow2 only; never a host disk.

---

## A. Offline (sandbox-verifiable) — T-01 … T-08

- [ ] T-01 `./tools/validate-versions.sh` exits 0 with zero `[FAIL]` lines.
- [ ] T-02 `./tools/bootstrap.sh --check` and all Phase 3–10 `--check` drivers exit 0.
- [ ] T-03 `./tools/build-iso.sh --check` and `./tools/checksum.sh --check` exit 0.
- [ ] T-04 `python3 tools/lib/ar0x_iso.py . --self-test` passes 9 negative mutations + the REAL sparse-file 2.2 GB size-gate test.
- [ ] T-05 `./tools/build-iso.sh --self-test` passes the staged-prefix parity and `checksum.sh` create/verify/tamper round-trip.
- [ ] T-06 `config/packages.x86_64` and `archiso/packages.x86_64` are byte-identical, with zero `ar0x-*`, `calamares`, AUR, `*-git`, `*-bin` or `extra-testing` entries.
- [ ] T-07 `git diff --check` is clean; no `*.iso`, `SHA256SUMS`, `*.sig`, `*.gpg` or private key is tracked (RISK-051).
- [ ] T-08 `find . -name '*.iso'` is empty in the checkout; all derived artifacts live in `/opt/ar0x-build/out/`.

## B. Build host prerequisites — T-09 … T-14

- [ ] T-09 Real Arch host (or `archlinux:base-devel` container) with root, loop devices and ≥ 40 GiB free under `/opt/ar0x-build`.
- [ ] T-10 `archiso 92-1`, `mkarchiso`, `xorriso`, `qemu-full`, `edk2-ovmf`, `gpg`, `sha256sum` installed; `mkarchiso -h` works.
- [ ] T-11 `./tools/build-iso.sh --preflight` prints the prerequisite list; every `MISSING` warning is resolved.
- [ ] T-12 Offline release key generated on an AIR-GAPPED host (`AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen`), 40-hex FPR committed out of band, `--sync` re-run (RISK-051).
- [ ] T-13 Signed `[ar0x]` db built, signed and published; `pacman-key --init` + `--populate ar0x` succeed on a test host (RISK-048).
- [ ] T-14 `calamares 3.4.3` (Codeberg tarball + detached `.asc`, key `6D08 3784 … 56D6`) and `ar0x-meta` added to `config/packages.x86_64`; frozen `2026/11/01` mirror still reachable (RISK-003/006).

## C. ISO build & integrity — T-15 … T-20

- [ ] T-15 `sudo AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build` completes `mkarchiso -v -m iso` with `SOURCE_DATE_EPOCH` set to the snapshot date.
- [ ] T-16 `stat -c %s` on the ISO is ≤ `2362232012` bytes; if not, apply the PROJECT_PLAN.md §7 lever order (never drop Calamares without approval) (RISK-012).
- [ ] T-17 `./tools/build-iso.sh --size-report <staged-airootfs>` reviewed for the largest payload directories.
- [ ] T-18 `./tools/checksum.sh --create` writes `SHA256SUMS` and passes its own `sha256sum -c` self-check.
- [ ] T-19 `AR0X_CONFIRM_SIGN=yes ./tools/checksum.sh --sign` creates detached `SHA256SUMS.sig` + `<iso>.sig` with the published FPR; `--verify` passes `gpg --verify SHA256SUMS.sig SHA256SUMS` (RISK-051).
- [ ] T-20 `CHANGELOG.md`, `README.md` and `packages.lock` are present in `out/`; the exact 6-item artifact set from PROJECT_PLAN.md §11 is complete.

## D. QEMU BIOS / SeaBIOS (isolinux) — T-21 … T-24

- [ ] T-21 `./tools/build-iso.sh --qemu-bios out/ar0x-0.1.0-x86_64.iso` boots with `-machine q35 -vga virtio` and NO OVMF/pflash flags.
- [ ] T-22 isolinux menu renders the ar0x theme; the normal and FAILSAFE (`plymouth.enable=0 nomodeset loglevel=7`) entries are both present.
- [ ] T-23 Plymouth splash → SDDM 0.21 greeter → Hyprland/Wayland session; `Hyprland --verify-config` clean (RISK-002).
- [ ] T-24 `fastfetch`, `/etc/os-release`, GRUB, Plymouth and SDDM all show `ar0x root` branding; `AR0X ROOT` boot labels correct (ADR-025).

## E. QEMU UEFI / OVMF (uefi.grub) — T-25 … T-28

- [ ] T-25 `./tools/build-iso.sh --qemu-uefi out/ar0x-0.1.0-x86_64.iso` boots with two `if=pflash` drives (`OVMF_CODE.4m.fd` + a disposable writable `OVMF_VARS` copy).
- [ ] T-26 OVMF → GRUB menu → Plymouth splash → SDDM → Hyprland/Wayland; no `uefi.systemd-boot` artifacts.
- [ ] T-27 `efibootmgr`/`ls /sys/firmware/efi` confirms UEFI mode; the ESP is 512 MiB and GRUB is installed to it.
- [ ] T-28 Secure Boot OFF (RISK-007); if tested ON, MOK enrollment is a separate MANUAL firmware step and recovery is documented.

## F. Installer → reboot → first boot — T-29 … T-33

- [ ] T-29 `AR0X_CONFIRM_DISPOSABLE_VM=yes AR0X_TARGET_DISK=vda ./tools/build-iso.sh --qemu-install <iso>` creates ONLY a disposable qcow2 in a temp dir; **inside the guest** run `lsblk -o NAME,SIZE,MODEL,TRAN` and TYPE the target device (RISK-004).
- [ ] T-30 Calamares 3.4.3 wizard completes: welcome → locale → keyboard → partition → users → package group → summary; no QML keyboard failure (RISK-003/052).
- [ ] T-31 `calamares -d` debug log reviewed; `unpackfs` squashfs, `initcpiocfg/initcpio`, GRUB and `umount` all succeed; target unmounted at the end.
- [ ] T-32 Rebooted system: `ar0x-firstboot.service` succeeded, `/etc/machine-id` is a real 32-hex id (NOT `uninitialized`), `sudo -l` shows **zero** `NOPASSWD`, live `ar0x` user removed (RISK-013/033).
- [ ] T-33 `ar0x-welcome` (GTK4) appears on the first graphical login; its 5 links, "Check for updates" and "Install extras" all work (acceptance criterion 3).

## G. Desktop, hardware & VMs — T-34 … T-37

- [ ] T-34 WiFi, Bluetooth, audio (PipeWire/WirePlumber 0.5+), GPU acceleration and screen capture pass on ≥ 1 real hardware machine (RISK-005/008/009).
- [ ] T-35 VirtualBox: VMSVGA controller, 3D Acceleration enabled, ≥ 4 GiB RAM; boot to Wayland session and verify clipboard/resize.
- [ ] T-36 VMware: `svga` driver, `WLR_NO_HARDWARE_CURSORS=1` workaround documented if the cursor disappears.
- [ ] T-37 `ar0x-update --check`, `ar0x-info`, `ar0x-cursors`, wallpapers and Hyprland 0.57 Lua keybinds work without root.

## H. Release gate — T-38 … T-40

- [ ] T-38 Every shell script passes `bash -n` and `shellcheck`; `namcap`, `desktop-file-validate` and `systemd-analyze verify` clean (MANUAL, absent here).
- [ ] T-39 GitHub Release `v0.1.0` contains `.iso`, `SHA256SUMS`, `SHA256SUMS.sig`, `<iso>.sig`, `CHANGELOG.md`, `README.md`; a fresh download passes `sha256sum -c` + `gpg --verify`.
- [ ] T-40 All 40 boxes in this checklist are PASS (100%), the release fingerprint is published out of band, and Phase 12 upload/DistroWatch announcement may proceed.

---

## Sign-off

| Field | Value |
|---|---|
| Tester | ____________________ |
| Date | ____________________ |
| Host / CPU / GPU | ____________________ |
| ISO SHA256 | ____________________ |
| Passed items | ____ / 40 (gate: **100%**) |
| Blocking issues | ____________________ |

Companion documents: `docs/ISO_BUILD_GUIDE.md` (exact commands, size levers,
VBox/VMware settings), `docs/INSTALLER_FLOW.md` (RISK-004 disk gate),
`docs/REPO_GUIDE.md` (keygen/sign/publish), `PROJECT_PLAN.md §7/§16`.
