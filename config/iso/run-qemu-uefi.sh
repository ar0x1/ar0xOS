#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/config/iso/run-qemu-uefi.sh — Phase 11
# CANONICAL UEFI / OVMF (uefi.grub) boot launcher. Copied by
# tools/build-iso.sh --sync into build/iso-prefix (gitignored).
# Usage: run-qemu-uefi.sh /path/to/ar0x-0.1.0-x86_64.iso
# -----------------------------------------------------------------------------
set -euo pipefail

ISO="${1:-}"
[[ -n "$ISO" && -f "$ISO" ]] || { printf 'usage: %s <ar0x ISO>\n' "$0" >&2; exit 2; }

QEMU="${AR0X_QEMU_BIN:-qemu-system-x86_64}"
RAM="${AR0X_ISO_QEMU_RAM_MIB:-4096}"
CPUS="${AR0X_ISO_QEMU_CPUS:-4}"
CODE="${AR0X_ISO_QEMU_UEFI_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
VARS_SRC="${AR0X_ISO_QEMU_UEFI_VARS:-/usr/share/edk2/x64/OVMF_VARS_4m.fd}"
NAME="${AR0X_ISO_VM_NAME:-ar0x-uefi}"

[[ -r "$CODE" ]]     || { printf 'missing UEFI firmware: %s (install edk2-ovmf)\n' "$CODE" >&2; exit 2; }
[[ -r "$VARS_SRC" ]] || { printf 'missing UEFI vars template: %s\n' "$VARS_SRC" >&2; exit 2; }

# NEVER write to the packaged firmware file: use a disposable writable copy.
TMP="$(mktemp -d -t ar0x-ovmf-XXXXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
cp -- "$VARS_SRC" "${TMP}/OVMF_VARS.fd"

ACCEL=()
if [[ -r /dev/kvm && -w /dev/kvm ]]; then ACCEL=(-enable-kvm); fi

printf 'ar0x UEFI boot: %s (%s MiB RAM, %s vCPU)\n' "$ISO" "$RAM" "$CPUS"
printf 'Expected: OVMF → GRUB menu → Plymouth splash → SDDM → Hyprland/Wayland.\n'

exec "$QEMU" \
    "${ACCEL[@]}" \
    -name "$NAME" \
    -machine q35,smm=on \
    -m "$RAM" -smp "$CPUS" \
    -cpu max \
    -rtc base=utc \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,unit=1,file="${TMP}/OVMF_VARS.fd" \
    -vga virtio \
    -display "${AR0X_ISO_QEMU_DISPLAY:-gtk}" \
    -usb -device usb-tablet \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0 \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -drive file="$ISO",media=cdrom,readonly=on \
    -boot order=d,menu=on \
    -no-reboot
