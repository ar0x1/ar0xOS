#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/config/iso/run-qemu-bios.sh — Phase 11
# CANONICAL BIOS / SeaBIOS (isolinux) boot launcher. Copied by
# tools/build-iso.sh --sync into build/iso-prefix (gitignored).
# Usage: run-qemu-bios.sh /path/to/ar0x-0.1.0-x86_64.iso
# -----------------------------------------------------------------------------
set -euo pipefail

ISO="${1:-}"
[[ -n "$ISO" && -f "$ISO" ]] || { printf 'usage: %s <ar0x ISO>\n' "$0" >&2; exit 2; }

QEMU="${AR0X_QEMU_BIN:-qemu-system-x86_64}"
RAM="${AR0X_ISO_QEMU_RAM_MIB:-4096}"
CPUS="${AR0X_ISO_QEMU_CPUS:-4}"
NAME="${AR0X_ISO_VM_NAME:-ar0x-bios}"

ACCEL=()
if [[ -r /dev/kvm && -w /dev/kvm ]]; then ACCEL=(-enable-kvm); fi

printf 'ar0x BIOS boot: %s (%s MiB RAM, %s vCPU)\n' "$ISO" "$RAM" "$CPUS"
printf 'Expected: syslinux/isolinux menu → Plymouth splash → SDDM → Hyprland/Wayland.\n'
printf 'FAILSAFE entry overrides with plymouth.enable=0 nomodeset loglevel=7.\n'

exec "$QEMU" \
    "${ACCEL[@]}" \
    -name "$NAME" \
    -machine q35 \
    -m "$RAM" -smp "$CPUS" \
    -cpu max \
    -rtc base=utc \
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
