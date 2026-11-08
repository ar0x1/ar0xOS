# ar0x ISO Build Guide — Phase 11 (COMPLETE)

**Target:** `ar0x-0.1.0-x86_64.iso` · `AR0X_010` · archiso `92-1` · GRUB (UEFI) +
isolinux (BIOS) · frozen Arch snapshot `2026/11/01` · size gate **≤ 2.2 GB**
(`2362232012` bytes / 2.2 GiB).
**Status:** ✅ build tooling, size gate, checksum/signature tooling, QEMU/VBox/
VMware procedures and the 40-item checklist COMPLETE (ADR-027). ⚠️ **NO ISO was
built, booted, hashed or signed here** — see the warnings below.

> ⚠️ **RISK-053 (HIGH):** `mkarchiso`, `qemu-system-x86_64`, `qemu-img`,
> `edk2-ovmf`, `xorriso`, `gpg`, KVM, loop devices and root are ALL absent in
> this sandbox. Only `--check`, `--sync`, `--self-test`, `--preflight` and the
> real offline checksum/size-gate tests ran. The ISO does not exist.
>
> ⚠️ **RISK-048 / RISK-051 (CRITICAL):** the offline release key is
> `PENDING-KEYGEN`; the signed `[ar0x]` db does not exist. `calamares` and
> `ar0x-meta` are therefore **STILL NOT** in `config/packages.x86_64`.
> `tools/build-iso.sh --build` **REFUSES** until the MANUAL
> `--keygen → --build → --sign → publish` chain completes.
>
> ⚠️ **RISK-004 (CRITICAL):** Calamares partitioning is destructive and
> irreversible. Before ANY install: `lsblk -o NAME,SIZE,MODEL,TRAN` and TYPE
> the target device. `--qemu-install` only ever creates a **disposable qcow2**
> in a temp dir — never a host disk.
>
> ⚠️ **RISK-052:** the Calamares GUI was never rendered (Phase 10). Phase 11
> is where the full install → reboot → first-boot acceptance criterion is
> finally exercised **manually**.

---

## 1. Deliverables

| Canonical source | Role |
|---|---|
| `config/iso/build-options.conf` | 16 sourced KEY=value pins: size gate, QEMU resources, OVMF paths, hash/signature names |
| `config/iso/size-budget.conf` | the 8 PROJECT_PLAN.md §7 payload rows (`name\|uncompressed_MiB\|compressed_MiB`, 1890 MiB compressed) |
| `config/iso/run-qemu-{bios,uefi,install}.sh` | 3 canonical `0755` VM launchers |
| `tools/build-iso.sh` | `--check/--sync/--self-test/--preflight/--size-report/--qemu-*/--build` |
| `tools/checksum.sh` | `--check/--create/--verify/--sign/--self-test` (SHA256SUMS + detached GPG sigs) |
| `tools/lib/ar0x_iso.py` | pure-stdlib validator; 9 negative mutation tests + REAL sparse-file size gate |
| `docs/ISO_BUILD_GUIDE.md` | this document |
| `docs/TESTING_CHECKLIST.md` | 40 ordered pass/fail items; **100%** gate |

**ONE OWNER PER PATH (ADR-024/026):** `config/iso/**` is canonical.
`tools/build-iso.sh --sync` copies the launchers into the gitignored
`build/iso-prefix/` for offline tests only. Derived artifacts (`*.iso`,
`SHA256SUMS*`, `*.sig`, `packages.lock`, `*.gpg`) stay in
`/opt/ar0x-build/out/` and are gitignored — never in the checkout.

---

## 2. ⚠️ MANUAL pre-build gates (do NOT skip)

The release ISO cannot be built until all of these are true:

1. **Keygen (RISK-051).** On an AIR-GAPPED host:
   `sudo AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen`, commit the
   40-hex fingerprint into `config/repo/RELEASE_KEY_FINGERPRINT`, publish it out
   of band, then `--sync`.
2. **Build + sign the 8 packages (RISK-048/049).**
   `AR0X_CONFIRM_BUILD=yes ./tools/setup-repo.sh --build` as a **non-root**
   `builder`, then `sudo AR0X_CONFIRM_SIGN=yes ./tools/setup-repo.sh --sign`
   and `--verify`. `repo-add -s -v --include-sigs` must produce
   `ar0x.db.tar.zst` + `.sig`.
3. **Publish Calamares 3.4.3 (RISK-003).** Build from the **Codeberg**
   `calamares-3.4.3.tar.gz`, verify the detached `.asc` with key
   `6D08 3784 1C06 8A23 3F24 127B 14B6 CC38 1BC2 56D6`, then add it to the
   signed repo. NEVER the archived GitHub mirror (`v3.3.14`).
4. **Update the ISO package list.** Add `calamares` **and** `ar0x-meta` to
   `config/packages.x86_64`, then `./tools/bootstrap.sh --sync` so
   `archiso/packages.x86_64` stays byte-identical. `ar0x_iso.py` intentionally
   fails while they are absent, so this step must be re-validated deliberately.
5. **Host prerequisites.** Real Arch host, ROOT, `archiso 92-1`, `mkarchiso`,
   loop devices, ~40 GiB free under `/opt/ar0x-build`, `qemu-full`,
   `edk2-ovmf`, `xorriso`, `gpg`.

Check with `./tools/build-iso.sh --preflight` (print-only, builds nothing).

---

## 3. Exact build commands (real Arch host)

```bash
cd /home/user/ar0xOS

# Offline, no root — ALWAYS first
./tools/build-iso.sh --sync
./tools/build-iso.sh --check
./tools/build-iso.sh --self-test
./tools/checksum.sh --check
./tools/validate-versions.sh
./tools/bootstrap.sh --check

# ⚠️ MANUAL, ROOT, REAL ARCH HOST, signed [ar0x] db REQUIRED
sudo AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build
```

`--build` runs `bootstrap.sh --sync`, then
`SOURCE_DATE_EPOCH` (derived from the frozen `2026/11/01` snapshot) +
`mkarchiso -v -m iso -w /opt/ar0x-build/work -o /opt/ar0x-build/out
/opt/ar0x-build/profile`, then `stat -c %s` against
`AR0X_ISO_MAX_BYTES` and finally `checksum.sh --create`.

If the ISO is oversized, `--size-report <staged-airootfs>` prints a
per-directory MiB breakdown. Apply the **fixed lever order** from
`PROJECT_PLAN.md §7`: (1) trim `linux-firmware`, (2) drop large optional apps,
(3) zstd 15 → 19, (4) 1080p JPEG wallpapers, (5) **last resort only** drop
Calamares — that changes a locked preference and **requires your approval**
(RISK-012).

`SOURCE_DATE_EPOCH` gives deterministic ISO timestamps; `AR0X_REPRODUCIBLE =
package-level` means bit-for-bit reproducibility is still a v0.2 goal.

---

## 4. Checksums & detached signatures

```bash
./tools/checksum.sh --create     # writes /opt/ar0x-build/out/SHA256SUMS
./tools/checksum.sh --verify     # sha256sum -c + gpg --verify SHA256SUMS.sig SHA256SUMS

# ⚠️ MANUAL only, after keygen:
sudo AR0X_CONFIRM_SIGN=yes ./tools/checksum.sh --sign
#   -> SHA256SUMS.sig  AND  ar0x-0.1.0-x86_64.iso.sig
```

Verification order for a downloader (also in `TESTING_CHECKLIST.md`):
`gpg --verify SHA256SUMS.sig SHA256SUMS` → confirm the **fingerprint** out of
band → `sha256sum -c SHA256SUMS`. Signature first, then checksum; never the
reverse. `--sign` REFUSES while `RELEASE_KEY_FINGERPRINT = PENDING-KEYGEN`.

`tools/checksum.sh --self-test` really runs create → verify → tamper →
**verify must fail** → restore → verify, and proves `--sign` refuses. It needs
no root, no gpg, no network and no ISO.

---

## 5. QEMU — BIOS (SeaBIOS / isolinux)

```bash
./tools/build-iso.sh --qemu-bios /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
# equivalent to:
qemu-system-x86_64 -enable-kvm -machine q35 -m 4096 -smp 4 -cpu max \
  -vga virtio -display gtk -usb -device usb-tablet \
  -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
  -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 \
  -drive file=ar0x-0.1.0-x86_64.iso,media=cdrom,readonly=on \
  -boot order=d,menu=on -no-reboot
```

Expected: isolinux/syslinux menu → Plymouth splash → SDDM → Hyprland/Wayland.
The **FAILSAFE** entry adds `plymouth.enable=0 nomodeset loglevel=7`.

## 6. QEMU — UEFI (OVMF / uefi.grub)

```bash
./tools/build-iso.sh --qemu-uefi /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
# equivalent to (Arch paths, edk2-ovmf):
cp /usr/share/edk2/x64/OVMF_VARS_4m.fd /tmp/OVMF_VARS.fd
qemu-system-x86_64 -enable-kvm -machine q35,smm=on -m 4096 -smp 4 \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,unit=1,file=/tmp/OVMF_VARS.fd \
  -vga virtio -display gtk -drive file=ar0x-0.1.0-x86_64.iso,media=cdrom,readonly=on \
  -boot order=d,menu=on -no-reboot
```

The launcher uses `mktemp -d` and a **disposable copy** of the vars file — it
never writes to the packaged firmware. `-no-reboot` makes a failed boot visible
instead of looping. Confirm the GRUB menu, then Plymouth, SDDM, Hyprland.
`xorriso -indev <iso> -report_el_torito plain` should list BOTH the BIOS and
EFI El Torito entries.

## 7. ⚠️ QEMU installer VM (RISK-004)

```bash
qemu-img create -f qcow2 /tmp/ar0x-target.qcow2 40G
AR0X_CONFIRM_DISPOSABLE_VM=yes AR0X_TARGET_DISK=vda \
  ./tools/build-iso.sh --qemu-install /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
```

**Inside the guest, before clicking Install:**

```bash
lsblk -o NAME,SIZE,MODEL,TRAN        # TYPE the target device; >1 disk => STOP
```

`initialPartitioningChoice: none` + `prompt-install: true` (Phase 10 /
ADR-026) prevent auto-selection. Walk the wizard from
`docs/INSTALLER_FLOW.md §3`, reboot, then verify:

```bash
sudo systemctl status ar0x-firstboot.service
sudo -l                      # must NOT show NOPASSWD
cat /etc/machine-id          # real 32-hex id, NOT "uninitialized"
systemctl --user status ar0x-welcome.service
```

---

## 8. VirtualBox (secondary target)

1. New VM: **Linux / Arch Linux (64-bit)**, ≥ 4 GiB RAM, ≥ 4 vCPU, ≥ 40 GiB disk.
2. **Settings → System → Motherboard:** enable **EFI** (for the UEFI target);
   disable EFI for the BIOS target. Chipset PIIX3 is fine for BIOS.
3. **Settings → Display → Screen:** graphics controller **VMSVGA** for a Linux
   guest (VBoxSVGA is Windows-oriented), Video Memory to the maximum (128 MiB),
   enable **3D Acceleration**.
4. Attach `ar0x-0.1.0-x86_64.iso` to the optical drive; boot order optical first.
5. Install `virtualbox-guest-utils` in the guest **only for the smoke test** —
   it is NOT an ISO package (RISK-010) and must not be added to
   `config/packages.x86_64`.
6. If Hyprland fails to start, use the FAILSAFE entry or set, in the guest's
   session environment: `WLR_NO_HARDWARE_CURSORS=1` and
   `WLR_RENDERER_ALLOW_SOFTWARE=1`. A software-rendered Wayland session is a
   **known VM limitation**, not a release blocker (RISK-009/043). QEMU/KVM is
   the authoritative graphical test.
7. Record the VBox result at `TESTING_CHECKLIST.md T-38`.

## 9. VMware Workstation / Player (secondary target)

1. New VM: **Linux / Other Linux 6.x kernel 64-bit**, ≥ 4 GiB RAM, ≥ 4 vCPU,
   ≥ 40 GiB disk, **Accelerate 3D graphics** enabled, `svga` / `vmwgfx` driver.
2. Set firmware to **UEFI** in `.vmx` (`firmware = "efi"`) for the UEFI target.
3. Attach the ISO to the CD/DVD device, `bios.bootOrder = "cdrom"`.
4. `open-vm-tools` may be installed in the guest for the smoke test only.
5. Same `WLR_NO_HARDWARE_CURSORS=1` fallback as VirtualBox if the cursor or
   renderer misbehaves; `WLR_RENDERER_ALLOW_SOFTWARE=1` for llvmpipe.
6. Record the result at `TESTING_CHECKLIST.md T-39`.

---

## 10. Real hardware matrix (criterion 4)

Test on ≥ 1 physical machine (Intel + AMD GPU if possible): **WiFi** (do not
trim `linux-firmware` without re-testing, RISK-005), **Bluetooth**,
**PipeWire** audio (playback + capture), **GPU acceleration**
(`glxinfo -B` under XWayland / `vulkaninfo`), and **screen capture**
(`grim` + `slurp`, xdg-desktop-portal-hyprland). AppArmor stays in `complain`
(RISK-008). Secure Boot is OPTIONAL and MOK enrollment is MANUAL (RISK-007).

---

## 11. Troubleshooting

| Symptom | Fix |
|---|---|
| `--build` refuses with `PENDING-KEYGEN` | Expected: MANUAL keygen → sign → publish first (§2) |
| ISO > 2362232012 bytes | `--size-report` then the FIXED §7 lever order; never silently drop Calamares |
| Black screen at boot | FAILSAFE entry: `plymouth.enable=0 nomodeset loglevel=7` |
| UEFI boots to a shell | Check `uefi.grub` (not `uefi.systemd-boot`), `grub-mkstandalone` on the HOST |
| BIOS menu missing | `syslinux` must be IN `packages.x86_64` (mkarchiso copies from the airootfs) |
| QEMU UEFI vars read-only | Use the disposable `OVMF_VARS` copy; never mount the packaged file rw |
| VBox/VMware Wayland fails | `WLR_NO_HARDWARE_CURSORS=1` + `WLR_RENDERER_ALLOW_SOFTWARE=1`; QEMU is authoritative |
| `gpg --verify` fails | Verify the fingerprint out of band; NEVER weaken `SigLevel` below `Required` |
| `sha256sum -c` fails | DO NOT PUBLISH; rebuild, do not hand-edit SHA256SUMS |
| Wrong disk erased | ⚠️ **RISK-004 — irreversible.** Always `lsblk` first; no automated fix |

---

## 12. Verification actually performed in this sandbox

| Gate | Result |
|---|---|
| `python3 tools/lib/ar0x_iso.py .` | ✅ options parity, 8-row budget, profiledef, package policy, 3 QEMU launchers, checksum contract, 40 checklist items, RISK-003/048/051 |
| `python3 tools/lib/ar0x_iso.py . --self-test` | ✅ 9 negative mutations rejected + REAL sparse-file size gate (gate+1 rejected, gate-1 accepted) |
| `./tools/checksum.sh --self-test` | ✅ REAL create → verify → tamper → reject → restore → verify; `--sign` refused |
| `./tools/build-iso.sh --check/--sync/--self-test` | ✅ PASS; staged prefix byte-identical |
| `bash -n` + Python AST + `validate-versions.sh` + full P3–P10 chain + `git diff --check` | ✅ PASS |
| `mkarchiso` / QEMU / VBox / VMware / real hardware / `gpg` | ⚠️ **NOT RUN** — MANUAL |

---

## 13. Companion documents

`docs/TESTING_CHECKLIST.md` (100% gate) · `PROJECT_PLAN.md §7/§11/§15/§16` ·
`docs/INSTALLER_FLOW.md` (Phase 10) · `docs/REPO_GUIDE.md §3` (keygen/sign) ·
`docs/BOOTSTRAP_GUIDE.md` · `docs/KERNEL_BOOT.md` ·
`docs/architecture/DECISIONS.md` (ADR-027) ·
`docs/architecture/RISK_REGISTER.md` (RISK-053).
