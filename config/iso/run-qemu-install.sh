#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/config/iso/run-qemu-install.sh — Phase 11
# ⚠️ RISK-004 (CRITICAL): Calamares partitioning is DESTRUCTIVE and IRREVERSIBLE.
# This launcher uses ONLY a DISPOSABLE qcow2 in a temp dir. It NEVER touches a
# host disk and NEVER auto-selects a device.
#
# Manual equivalent of the disposable disk created below:
#   qemu-img create -f qcow2 ar0x-target.qcow2 40G
#
#   Inside the guest BEFORE clicking Install:
#     lsblk -o NAME,SIZE,MODEL,TRAN
#   then TYPE the target device name. If more than one disk appears, STOP.
#
# Usage: AR0X_CONFIRM_DISPOSABLE_VM=yes AR0X_TARGET_DISK=vda \
#          run-qemu-install.sh /path/to/ar0x-0.1.0-x86_64.iso
# -----------------------------------------------------------------------------
set -euo pipefail

ISO="${1:-}"
[[ -n "$ISO" && -f "$ISO" ]] || { printf 'usage: %s <ar0x ISO>\n' "$0" >&2; exit 2; }
if [[ "${AR0X_CONFIRM_DISPOSABLE_VM:-no}" != "yes" ]]; then
    printf 'RISK-004: set AR0X_CONFIRM_DISPOSABLE_VM=yes after reading docs/INSTALLER_FLOW.md §2.\n' >&2
    exit 2
fi
DISK="${AR0X_TARGET_DISK:-}"
if [[ -z "$DISK" || ! "$DISK" =~ ^[a-z]+[a-z0-9]*$ ]]; then
    printf 'RISK-004: AR0X_TARGET_DISK must be a TYPED bare device name (e.g. vda).\n' >&2
    exit 2
fi

QEMU="${AR0X_QEMU_BIN:-qemu-system-x86_64}"
IMGBIN="${AR0X_QEMU_IMG_BIN:-qemu-img}"
RAM="${AR0X_ISO_QEMU_RAM_MIB:-4096}"
CPUS="${AR0X_ISO_QEMU_CPUS:-4}"
GIB="${AR0X_ISO_QEMU_DISK_GIB:-40}"
CODE="${AR0X_ISO_QEMU_UEFI_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
VARS_SRC="${AR0X_ISO_QEMU_UEFI_VARS:-/usr/share/edk2/x64/OVMF_VARS_4m.fd}"

TMP="$(mktemp -d -t ar0x-install-XXXXXXXX)"
trap 'printf "disposable VM scratch kept at %s (delete manually)\n" "$TMP"' EXIT
"$IMGBIN" create -f qcow2 "${TMP}/ar0x-target.qcow2" "${GIB}G" >/dev/null
cp -- "$VARS_SRC" "${TMP}/OVMF_VARS.fd"

ACCEL=()
if [[ -r /dev/kvm && -w /dev/kvm ]]; then ACCEL=(-enable-kvm); fi

printf '\n⚠️ RISK-004 — typed target device: /dev/%s (DISPOSABLE qcow2 only)\n' "$DISK"
printf '   Inside the guest run: lsblk -o NAME,SIZE,MODEL,TRAN\n'
printf '   Accept criterion 3: install → reboot → ar0x-welcome on first login.\n\n'

exec "$QEMU" \
    "${ACCEL[@]}" \
    -name ar0x-install \
    -machine q35,smm=on \
    -m "$RAM" -smp "$CPUS" \
    -cpu max \
    -rtc base=utc \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,unit=1,file="${TMP}/OVMF_VARS.fd" \
    -drive file="${TMP}/ar0x-target.qcow2",format=qcow2,if=virtio \
    -vga virtio \
    -display "${AR0X_ISO_QEMU_DISPLAY:-gtk}" \
    -usb -device usb-tablet \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0 \
    -drive file="$ISO",media=cdrom,readonly=on \
    -boot order=d,menu=on \
    -no-reboot
