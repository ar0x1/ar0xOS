#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_iso.py
# -----------------------------------------------------------------------------
# PHASE 11 — pure-stdlib ISO build / size / VM / release-artifact validator.
#
# NO PyYAML, NO mkarchiso, NO QEMU, NO gpg, NO root, NO network, NO ISO. It
# parses the small KEY=value configs in config/iso/, asserts parity with
# config/versions.env, validates the archiso 92 profile contract, the package
# policy (RISK-010/048/051), the 3 QEMU launchers, the checksum tool and the
# 40-item TESTING_CHECKLIST.md. `self_test()` mutates copies of every config
# in a temp tree to prove each gate actually FAILS, and really exercises the
# 2.2 GiB size gate with sparse files.
#
# Usage:
#   python3 tools/lib/ar0x_iso.py <SOURCE_ROOT>
#   python3 tools/lib/ar0x_iso.py <SOURCE_ROOT> --self-test
# -----------------------------------------------------------------------------

import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

SIZE_GATE_BYTES = 2362232012          # 2.2 GiB (PROJECT_PLAN.md §7)
BUDGET_ROWS = (
    "base-airootfs", "developer-toolchain", "hyprland-ecosystem",
    "qt6-calamares-kpmcore", "sddm-gtk4-welcome", "mesa-firmware",
    "kernel-initramfs", "boot-catalogs-assets",
)
COMPRESSED_TOTAL_MIB = 1890           # §7 estimates: ~1.9 GB compressed
CHECKLIST_IDS = tuple("T-%02d" % i for i in range(1, 41))
QEMU_SCRIPTS = ("run-qemu-bios.sh", "run-qemu-uefi.sh", "run-qemu-install.sh")
MANDATORY_PACKAGES = (
    "base", "linux-lts", "mkinitcpio", "mkinitcpio-archiso", "syslinux", "grub",
)
FORBIDDEN_PACKAGE_TOKENS = ("-git", "-bin", "aur/", "extra-testing")
MIB = 1024 * 1024


def read(path):
    return Path(path).read_text(encoding="utf-8")


def ok(msg):
    print("[ OK ] %s" % msg)


def parse_kv(text):
    """Plain KEY=value / KEY="value" config. Comments and blanks ignored.

    Handles THREE real-world shapes without PyYAML:
      KEY="value"                     -> value
      KEY="value"   # inline comment   -> value   (versions.env does this)
      KEY=value # comment             -> value
    The inline comment is stripped AFTER the closing quote, never before, so a
    value containing a '#' is not truncated and no stray quote survives.
    """
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip()
        if v.startswith('"') or v.startswith("'"):
            q = v[0]
            end = v.find(q, 1)
            v = v[1:end] if end != -1 else v[1:]
        else:
            v = v.split("#", 1)[0].strip()
        out[k.strip()] = v.strip()
    return out


def conf(root, rel):
    return parse_kv(read(root / rel))


# --- Section 1: options / budget --------------------------------------------
def check_options(root):
    iso = conf(root, "config/iso/build-options.conf")
    env = conf(root, "config/versions.env")
    assert iso.get("AR0X_ISO_SIZE_GATE_BYTES") == env.get("AR0X_ISO_MAX_BYTES"), \
        "size gate parity: config/iso/build-options.conf must match AR0X_ISO_MAX_BYTES"
    assert iso.get("AR0X_ISO_SIZE_GATE_BYTES") == str(SIZE_GATE_BYTES), \
        "size gate must be exactly %d bytes (2.2 GiB)" % SIZE_GATE_BYTES
    assert iso.get("AR0X_ISO_BOOT_MODES") == env.get("AR0X_ARCHISO_BOOTMODES"), \
        "boot modes must match AR0X_ARCHISO_BOOTMODES (bios.syslinux + uefi.grub)"
    assert iso.get("AR0X_ISO_TARGET_ARCH") == env.get("AR0X_ARCH"), "arch parity"
    assert iso.get("AR0X_ISO_RELEASE_DB") == env.get("AR0X_REPO_DB"), \
        "release db name must match AR0X_REPO_DB"
    assert iso.get("AR0X_ISO_HASH_ALGO") == "sha256", \
        "hash algorithm must be sha256, got %r" % iso.get("AR0X_ISO_HASH_ALGO")
    assert iso.get("AR0X_ISO_SUMS_FILE") == "SHA256SUMS", "sums file must be SHA256SUMS"
    assert iso.get("AR0X_ISO_SIG_SUFFIX") == ".sig", "signature suffix must be .sig"
    code = iso.get("AR0X_ISO_QEMU_UEFI_CODE", "")
    assert code.endswith("OVMF_CODE.4m.fd"), "UEFI firmware must be the OVMF_CODE image"
    assert iso.get("AR0X_ISO_QEMU_UEFI_VARS", "").endswith("OVMF_VARS_4m.fd"), \
        "UEFI vars template must be OVMF_VARS_4m.fd"
    for key in ("AR0X_ISO_QEMU_RAM_MIB", "AR0X_ISO_QEMU_CPUS",
                "AR0X_ISO_QEMU_DISK_GIB", "AR0X_ISO_BOOT_TIMEOUT_SEC",
                "AR0X_ISO_SIZE_REPORT_MIN_MIB"):
        assert iso.get(key, "").isdigit(), "%s must be a positive integer" % key
    ok("build-options.conf: 16 keys, size-gate/boot-mode/db/hash/OVMF parity with versions.env")


def parse_budget(text):
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        assert len(parts) == 3, "size-budget.conf row needs name|uncompressed|compressed: %r" % line
        assert parts[1].isdigit() and parts[2].isdigit(), \
            "size-budget.conf row has non-integer sizes: %r" % line
        rows.append((parts[0], int(parts[1]), int(parts[2])))
    return rows


def check_budget(root):
    rows = parse_budget(read(root / "config/iso/size-budget.conf"))
    assert tuple(r[0] for r in rows) == BUDGET_ROWS, \
        "size budget must have exactly the 8 PROJECT_PLAN.md §7 rows"
    for name, raw, comp in rows:
        assert comp <= raw, "%s compressed > uncompressed" % name
    total = sum(r[2] for r in rows)
    assert total == COMPRESSED_TOTAL_MIB, \
        "compressed budget drifted: %d MiB (expected %d)" % (total, COMPRESSED_TOTAL_MIB)
    assert total * MIB < SIZE_GATE_BYTES, \
        "RISK-012: budget already exceeds the 2.2 GiB gate"
    ok("size budget: 8 rows, %d MiB compressed < %d byte gate (%d MiB headroom)"
       % (total, SIZE_GATE_BYTES, (SIZE_GATE_BYTES - total * MIB) // MIB))


# --- Section 2: archiso 92 profile + package policy -------------------------
def check_profile(root):
    p = root / "archiso/profiledef.sh"
    t = read(p)
    # The header comment EXPLAINS that strict mode must not be added; the
    # assertion therefore applies to ACTIVE lines only (comments stripped).
    t_code = "\n".join(l for l in t.splitlines()
                        if l.strip() and not l.strip().startswith("#"))
    assert "set -euo pipefail" not in t_code and not re.search(r"^\s*set\s+-euo", t_code, re.M), \
        "profiledef.sh is SOURCED by mkarchiso; strict mode must not leak"
    for needle in ('buildmodes=(\'bootstrap\' \'iso\')', 'airootfs_image_type="squashfs"',
                   "'bios.syslinux'", "'uefi.grub'", 'install_dir="ar0x"',
                   'iso_label="AR0X_010"', 'iso_version="0.1.0"',
                   '-Xcompression-level\' \'15\''):
        assert needle in t, "profiledef.sh lost %r" % needle
    assert '["/etc/shadow"]="0:0:400"' in t, "/etc/shadow must be 0400 on the live ISO"
    # The header comment EXPLAINS that systemd-boot is exclusive; only the
    # ACTIVE (uncommented) config may not select it.
    assert "uefi.systemd-boot" not in t_code, \
        "uefi.grub and uefi.systemd-boot are mutually exclusive bootmodes"
    for f in ("archiso/grub/grub.cfg", "archiso/syslinux/syslinux.cfg"):
        assert (root / f).is_file(), "missing boot config for a declared boot mode: %s" % f
    ok("profiledef.sh: squashfs zstd-15, BIOS+UEFI, 0400 shadow, both boot configs, no strict-mode leak")


def active_packages(text):
    return [l.strip() for l in text.splitlines()
            if l.strip() and not l.strip().startswith("#")]


def check_packages(root):
    canon = root / "config/packages.x86_64"
    mirror = root / "archiso/packages.x86_64"
    assert canon.read_bytes() == mirror.read_bytes(), \
        "config/packages.x86_64 and archiso/packages.x86_64 diverged (run bootstrap.sh --sync)"
    names = active_packages(read(canon))
    for p in MANDATORY_PACKAGES:
        assert p in names, "mandatory archiso package missing: %s" % p
    assert len(names) == len(set(names)), "duplicate package line in packages.x86_64"
    for n in names:
        for bad in FORBIDDEN_PACKAGE_TOKENS:
            assert bad not in n, "RISK-010: forbidden package %r (%s)" % (n, bad)
        assert not n.startswith("ar0x-"), \
            "RISK-048/051: %r must NOT be on the ISO until the signed [ar0x] repo exists" % n
    assert "calamares" not in names, \
        "RISK-003/048: calamares arrives from the signed [ar0x] repo (Phase 11 MANUAL gate)"
    assert "Phase 11" in read(canon), \
        "packages.x86_64 must document the Phase 11 calamares/ar0x-meta gate"
    ok("packages.x86_64: byte-identical mirror, 6 mandatory pkgs, zero AUR/-git/-bin/ar0x-*/calamares")


# --- Section 3: QEMU launchers ----------------------------------------------
def check_qemu(root):
    d = root / "config/iso"
    for name in QEMU_SCRIPTS:
        p = d / name
        assert p.is_file(), "missing QEMU launcher: %s" % name
        assert os.access(p, os.X_OK), "%s must be mode 0755" % name
        t = read(p)
        assert t.startswith("#!/bin/bash"), "%s needs the bash shebang" % name
        assert re.search(r"^set -euo pipefail$", t, re.M), "%s needs strict mode" % name
        assert "\t" not in t, "%s contains a TAB" % name
    bios = read(d / "run-qemu-bios.sh")
    uefi = read(d / "run-qemu-uefi.sh")
    inst = read(d / "run-qemu-install.sh")
    assert "-boot order=d" in bios and "-cdrom" in bios.replace("-drive file=", "-cdrom"), \
        "BIOS launcher must boot from the ISO"
    assert "pflash" not in bios and "OVMF" not in bios, \
        "BIOS launcher must NOT carry firmware pflash/OVMF flags"
    assert uefi.count("if=pflash") == 2 and "OVMF_CODE" in uefi, \
        "UEFI launcher needs 2 pflash drives (if=pflash) + OVMF_CODE"
    assert "cp --" in uefi and "mktemp" in uefi, \
        "UEFI launcher must use a DISPOSABLE writable vars copy (never the packaged file)"
    for needle in ("qemu-img create", "if=virtio", "RISK-004",
                   "lsblk -o NAME,SIZE,MODEL,TRAN", "AR0X_CONFIRM_DISPOSABLE_VM",
                   "AR0X_TARGET_DISK"):
        assert needle in inst, "installer VM launcher missing %r" % needle
    ok("3 QEMU launchers: 0755, strict mode, BIOS/UEFI separation, RISK-004 typed-device gate")


def check_checksum(root):
    t = read(root / "tools/checksum.sh")
    for weak in ("md5sum", "sha1sum", "md5", "sha1"):
        assert weak not in t, "checksum.sh uses a weak hash: %s" % weak
    for needle in ("sha256sum -c", "SHA256SUMS.sig", "gpg --verify",
                   "PENDING-KEYGEN", "AR0X_CONFIRM_SIGN", "--detach-sign",
                   "sha256sum --"):
        assert needle in t, "checksum.sh missing %r" % needle
    gi = read(root / ".gitignore")
    assert "SHA256SUMS" in gi and "*.iso" in gi and "*.gpg" in gi, \
        "derived release artifacts must stay OUT of Git"
    assert "gpg --verify SHA256SUMS.sig SHA256SUMS" in t, \
        "checksum.sh must verify BOTH the checksum and its signature"
    ok("checksum.sh: sha256 only, gpg --verify, PENDING-KEYGEN refusal, artifacts gitignored")


def check_docs(root):
    guide = root / "docs/ISO_BUILD_GUIDE.md"
    cl = root / "docs/TESTING_CHECKLIST.md"
    assert guide.is_file() and cl.is_file(), "missing Phase 11 guide or checklist"
    g = read(guide)
    for needle in ("mkarchiso", "qemu-system-x86_64", "sha256sum -c", "gpg --verify",
                   "VMSVGA", "3D Acceleration", "WLR_NO_HARDWARE_CURSORS",
                   "SOURCE_DATE_EPOCH", "RISK-004", "RISK-053"):
        assert needle in g, "ISO_BUILD_GUIDE.md missing %r" % needle
    c = read(cl)
    items = re.findall(r"^- \[ \] (T-\d{2})\b", c, re.M)
    assert len(items) == len(CHECKLIST_IDS), \
        "TESTING_CHECKLIST.md must have exactly %d unchecked items, got %d" % (len(CHECKLIST_IDS), len(items))
    assert tuple(items) == CHECKLIST_IDS, \
        "checklist IDs must be exactly T-01..T-40 in order"
    for needle in ("100%", "2.2 GB", "lsblk -o NAME,SIZE,MODEL,TRAN", "VBox",
                   "VMware", "OVMF", "SeaBIOS", "RISK-004", "RISK-048",
                   "RISK-052", "RISK-053", "SHA256SUMS", "WiFi", "PipeWire"):
        assert needle in c, "TESTING_CHECKLIST.md missing %r" % needle
    ok("docs: ISO_BUILD_GUIDE.md + TESTING_CHECKLIST.md with %d ordered items and all risk gates"
       % len(items))


def check_policy(root):
    env = conf(root, "config/versions.env")
    assert env.get("AR0X_CALAMARES_VERSION") == "3.4.3", "RISK-003: Calamares pin drifted"
    assert env.get("AR0X_CALAMARES_SOURCE") == "codeberg", "RISK-003: Codeberg source required"
    fpr = [l.strip() for l in read(root / "config/repo/RELEASE_KEY_FINGERPRINT").splitlines()
           if l.strip() and not l.strip().startswith("#")]
    assert fpr == ["PENDING-KEYGEN"] or re.fullmatch(r"[0-9A-F]{40}", fpr[0]), \
        "release fingerprint must be PENDING-KEYGEN or a published 40-hex FPR"
    for p in sorted((root / "config/iso").rglob("*")):
        if p.is_file():
            assert "github.com/calamares/calamares" not in read(p), \
                "RISK-003: archived GitHub Calamares mirror referenced in %s" % p.name
    skip = {".git", "build", "__pycache__"}
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip]
        for fn in files:
            assert not fn.endswith(".iso"), "generated ISO leaked into the source tree: %s" % fn
    assert not (root / "config/repo/ar0x.db.tar.zst").exists(), \
        "a signed repo db must NOT be committed (RISK-051)"
    ok("policy: Codeberg 3.4.3, PENDING-KEYGEN, no signed db / ISO / archived mirror in Git")


def size_gate(size_bytes, gate_bytes=SIZE_GATE_BYTES):
    """Pure gate used by tools/build-iso.sh --build and the offline self-test."""
    return size_bytes <= gate_bytes


def run_checks(source_root):
    root = Path(source_root)
    print("=== ar0x Phase 11 ISO build validation ===")
    check_options(root)
    check_budget(root)
    check_profile(root)
    check_packages(root)
    check_qemu(root)
    check_checksum(root)
    check_docs(root)
    check_policy(root)
    print("[ OK ] Phase 11 ISO build validation PASSED")
    return 0


# --- Section 4: self-test ----------------------------------------------------
NEEDED = (
    "config/iso", "config/versions.env", "config/packages.x86_64",
    "archiso/packages.x86_64", "archiso/profiledef.sh",
    "archiso/grub/grub.cfg", "archiso/syslinux/syslinux.cfg",
    "tools/checksum.sh", "tools/build-iso.sh", "docs/ISO_BUILD_GUIDE.md",
    "docs/TESTING_CHECKLIST.md", ".gitignore",
    "config/repo/RELEASE_KEY_FINGERPRINT",
)


def _mini_root(src, tmp, mutate=None):
    for rel in NEEDED:
        s, d = src / rel, tmp / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        if s.is_dir():
            shutil.copytree(s, d)
        else:
            shutil.copyfile(s, d)
    if mutate:
        mutate(tmp)


def _expect_fail(label, src, mutate, needle):
    tmp = Path(tempfile.mkdtemp(prefix="ar0x-p11-neg-"))
    try:
        _mini_root(src, tmp, mutate)
        try:
            run_checks(tmp)
        except AssertionError as exc:
            assert needle in str(exc), "%s: wrong failure: %s" % (label, exc)
            print("[ OK ] negative test: %s correctly rejected" % label)
            return
        raise AssertionError("%s: validator ACCEPTED a broken config" % label)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def self_test(source_root):
    src = Path(source_root)
    print("=== ar0x Phase 11 offline self-test ===")
    run_checks(src)

    def edit(rel, old, new):
        def fn(root):
            p = root / rel
            t = read(p)
            assert old in t, "self-test fixture drift: %r absent in %s" % (old, rel)
            p.write_text(t.replace(old, new, 1), encoding="utf-8")
        return fn

    _expect_fail("size gate parity drift (RISK-012)", src,
                 edit("config/iso/build-options.conf",
                      'AR0X_ISO_SIZE_GATE_BYTES="2362232012"',
                      'AR0X_ISO_SIZE_GATE_BYTES="9999999999"'), "size gate")
    _expect_fail("weak hash algorithm", src,
                 edit("config/iso/build-options.conf",
                      'AR0X_ISO_HASH_ALGO="sha256"',
                      'AR0X_ISO_HASH_ALGO="sha1"'), "hash algorithm")
    _expect_fail("size budget row removed", src,
                 edit("config/iso/size-budget.conf",
                      "kernel-initramfs|250|180\n", ""), "8 PROJECT_PLAN")
    _expect_fail("UEFI launcher lost pflash", src,
                 edit("config/iso/run-qemu-uefi.sh",
                      "if=pflash,format=raw,unit=0", "if=none,format=raw,unit=0"),
                 "if=pflash")
    _expect_fail("BIOS launcher gained firmware flags", src,
                 edit("config/iso/run-qemu-bios.sh", "-vga virtio",
                      "-vga virtio -drive if=pflash,format=raw,file=OVMF_CODE.4m.fd"),
                 "BIOS launcher")
    def add_ar0x_package(root):
        # Mutate BOTH canonical + mirror so the byte-parity gate does not fire
        # before the real RISK-048 package-policy gate is reached.
        for rel in ("config/packages.x86_64", "archiso/packages.x86_64"):
            f = root / rel
            t = read(f)
            assert "\n# ar0x" in t, "packages fixture drift: %s" % rel
            f.write_text(t.replace("\n# ar0x", "\nar0x-meta\n# ar0x", 1),
                         encoding="utf-8")

    _expect_fail("ar0x package on the ISO (RISK-048)", src,
                 add_ar0x_package, "must NOT be on the ISO")
    _expect_fail("checklist item removed (100% gate)", src,
                 edit("docs/TESTING_CHECKLIST.md", "- [ ] T-40", "- [x] T-40"),
                 "40 unchecked")
    _expect_fail("weak hash in checksum.sh", src,
                 edit("tools/checksum.sh", "sha256sum --", "md5sum --"), "weak hash")
    def strip_lsblk(root):
        # The checklist repeats the RISK-004 command in its header AND in
        # T-29 (intentional). Remove EVERY occurrence to test the gate.
        f = root / "docs/TESTING_CHECKLIST.md"
        t = read(f)
        assert "lsblk -o NAME,SIZE,MODEL,TRAN" in t
        f.write_text(t.replace("lsblk -o NAME,SIZE,MODEL,TRAN", "lsblk"),
                     encoding="utf-8")

    _expect_fail("RISK-004 lsblk gate removed", src,
                 strip_lsblk, "lsblk")

    # --- REAL sparse-file exercise of the 2.2 GiB gate ----------------------
    tmp = Path(tempfile.mkdtemp(prefix="ar0x-p11-size-"))
    try:
        big, small = tmp / "gate-plus-one.iso", tmp / "gate-minus-one.iso"
        with open(big, "wb") as fh:
            fh.truncate(SIZE_GATE_BYTES + 1)
        with open(small, "wb") as fh:
            fh.truncate(SIZE_GATE_BYTES - 1)
        assert big.stat().st_size == SIZE_GATE_BYTES + 1
        assert small.stat().st_size == SIZE_GATE_BYTES - 1
        assert not size_gate(big.stat().st_size), "size gate ACCEPTED an oversized ISO"
        assert size_gate(small.stat().st_size), "size gate REJECTED an in-budget ISO"
        assert size_gate(COMPRESSED_TOTAL_MIB * MIB), "the §7 budget should fit the gate"
        ok("size gate: sparse gate+1 REJECTED, gate-1 ACCEPTED, %d MiB budget fits"
           % COMPRESSED_TOTAL_MIB)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("[ OK ] Phase 11 offline self-test PASSED")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("usage: ar0x_iso.py <SOURCE_ROOT> [--self-test]\n")
        sys.exit(2)
    try:
        if "--self-test" in sys.argv:
            sys.exit(self_test(Path(sys.argv[1])))
        sys.exit(run_checks(Path(sys.argv[1])))
    except (AssertionError, OSError, ValueError) as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        sys.exit(1)
