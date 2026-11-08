# `config/iso/` — Phase 11 canonical ISO / VM configuration

| File | Role |
|---|---|
| `build-options.conf` | sourced KEY=value: size gate parity, QEMU resources, OVMF paths, hash/signature names |
| `size-budget.conf` | the 8 PROJECT_PLAN.md §7 payload rows (`name\|uncompressed_MiB\|compressed_MiB`) |
| `run-qemu-bios.sh` | SeaBIOS / isolinux boot (no firmware pflash) |
| `run-qemu-uefi.sh` | OVMF / uefi.grub boot, disposable writable vars copy |
| `run-qemu-install.sh` | ⚠️ RISK-004 disposable-qcow2 installer VM; typed device gate |

**ONE OWNER PER PATH (ADR-024/026):** these are canonical. `tools/build-iso.sh
--sync` copies them into the gitignored `build/iso-prefix/` for the offline
self-test only; no second copy lives in `archiso/airootfs/`.

⚠️ MANUAL: none of these ran here. `qemu-system-x86_64`, `qemu-img`,
`edk2-ovmf`, `mkarchiso`, `gpg` and KVM are absent in this sandbox. Full
procedures: `docs/ISO_BUILD_GUIDE.md`; pass/fail gate: `docs/TESTING_CHECKLIST.md`.
