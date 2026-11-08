#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_installer.py
# -----------------------------------------------------------------------------
# PHASE 10 — pure-stdlib Calamares 3.4.3 configuration validator.
#
# NO PyYAML, NO Qt, NO Calamares, NO root, NO network, NO display. It parses
# the small, deliberately-constrained YAML subset we ship in config/calamares/
# and asserts the RISK-004 / RISK-013 / RISK-003 / ADR-015 / ADR-024 / ADR-025
# contracts structurally. `self_test()` also mutates copies of every config in
# a temp tree to prove each gate actually FAILS when the contract is broken.
#
# Usage:
#   python3 tools/lib/ar0x_installer.py <SOURCE_ROOT>
#   python3 tools/lib/ar0x_installer.py <SOURCE_ROOT> --self-test
# -----------------------------------------------------------------------------

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Modules that legitimately use Calamares' shipped defaults in
# /usr/share/calamares/modules/ (no file in config/calamares/modules/).
UPSTREAM_DEFAULT_MODULES = (
    "mount", "fstab", "localecfg", "networkcfg", "hwclock",
)

SHOW_ORDER = (
    "welcome", "locale", "keyboard", "partition", "users",
    "packagechooser@ar0x-packages", "summary",
)

# Relative-order assertions inside the single exec phase (a before b).
EXEC_ORDER = (
    ("partition", "mount"), ("mount", "unpackfs"),
    ("unpackfs", "machineid"), ("machineid", "fstab"),
    ("unpackfs", "packages"), ("packages", "initcpiocfg"),
    ("initcpiocfg", "initcpio"), ("removeuser", "users"),
    ("grubcfg", "bootloader"), ("bootloader", "shellprocess@ar0x-finish"),
    ("shellprocess@ar0x-finish", "umount"),
)

REQUIRED_EXEC = (
    "partition", "mount", "unpackfs", "packages", "machineid", "fstab",
    "locale", "keyboard", "localecfg", "shellprocess@ar0x-prep",
    "initcpiocfg", "initcpio", "removeuser", "users", "displaymanager",
    "networkcfg", "hwclock", "services-systemd", "grubcfg", "bootloader",
    "shellprocess@ar0x-finish", "umount",
)

REQUIRED_SCALARS = {
    "modules-search": "[ local ]",
    "branding": "ar0x",
    "prompt-install": "true",
    "dont-chroot": "false",
    "oem-setup": "false",
    "disable-cancel": "false",
    "disable-cancel-during-exec": "true",
    "hide-back-and-next-during-exec": "true",
    "quit-at-end": "false",
}

UNSAFE_SIGLEVELS = ("Never", "Optional", "TrustAll", "DatabaseOptional")
FORBIDDEN_PACKAGE_WORDS = ("aur/", "-git", "-bin", "steam", "yay", "paru")


def read(path):
    return Path(path).read_text(encoding="utf-8")


def ok(msg):
    print("[ OK ] %s" % msg)


def warn(msg):
    print("[WARN] %s" % msg)


def scalar(text, key):
    m = re.search(r"^%s:\s*(.+?)\s*$" % re.escape(key), text, re.M)
    return m.group(1).strip().strip('"').strip("'") if m else None


def scalar_any(text, key):
    """Like scalar(), but also matches NESTED keys (e.g. strings.productName)."""
    m = re.search(r"^\s*%s:\s*(.+?)\s*$" % re.escape(key), text, re.M)
    return m.group(1).strip().strip('"').strip("'") if m else None


# --- Section 1: tiny YAML-subset parser -------------------------------------
def parse_settings(text):
    """Parse ONLY the subset used by our settings.conf: top-level scalars, a
    list of `instances` maps, and a 3-phase `sequence` list of lists."""
    out = {"scalars": {}, "instances": [], "sequence": []}
    phase = None
    inst = None
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#") or raw.strip() == "---":
            continue
        if "\t" in raw:
            raise AssertionError("settings.conf contains a TAB (YAML forbids tabs)")
        # Phase / instance start at column 0: "- show:", "- exec:", "- id:"
        if raw.startswith("- "):
            rest = raw[2:].strip()
            if rest in ("show:", "exec:"):
                phase = {"kind": rest[:-1], "modules": []}
                out["sequence"].append(phase)
                inst = None
                continue
            if rest.startswith("id:"):
                inst = {"id": rest[3:].strip(), "module": "", "config": ""}
                out["instances"].append(inst)
                phase = None
                continue
            raise AssertionError("unexpected top-level list item: %r" % raw)
        # Sequence items are indented two spaces: "  - welcome"
        if raw.startswith("  - "):
            if phase is None:
                raise AssertionError("sequence item outside a phase: %r" % raw)
            phase["modules"].append(raw[4:].strip())
            continue
        # Instance attributes: "  module:   packagechooser"
        if raw.startswith("  ") and inst is not None and phase is None:
            k, _, v = raw.strip().partition(":")
            if k in ("module", "config"):
                inst[k] = v.strip()
            continue
        # Top-level scalar
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", raw)
        if m:
            out["scalars"][m.group(1)] = m.group(2).strip()
            continue
        raise AssertionError("unparseable settings.conf line: %r" % raw)
    return out


def check_settings(cfg):
    for key, want in REQUIRED_SCALARS.items():
        got = cfg["scalars"].get(key)
        assert got == want, "settings.conf %s must be %r, got %r" % (key, want, got)
    phases = cfg["sequence"]
    assert [p["kind"] for p in phases] == ["show", "exec", "show"], \
        "Calamares 3.4 needs exactly show/exec/show phases"
    assert phases[0]["modules"] == list(SHOW_ORDER), \
        "show order drifted: %r" % phases[0]["modules"]
    assert phases[2]["modules"] == ["finished"], \
        "final show phase must contain only `finished`"
    exec_mods = phases[1]["modules"]
    for mod in REQUIRED_EXEC:
        assert mod in exec_mods, "exec phase missing required module %s" % mod
    for a, b in EXEC_ORDER:
        assert exec_mods.index(a) < exec_mods.index(b), \
            "exec order violated: %s must run before %s" % (a, b)
    assert "umount" == exec_mods[-1], "umount must be the LAST exec job"
    ids = {i["id"] for i in cfg["instances"]}
    assert ids == {"ar0x-packages", "ar0x-prep", "ar0x-finish"}, \
        "unexpected instance ids: %r" % ids
    modules = {i["module"] for i in cfg["instances"]}
    assert modules == {"packagechooser", "shellprocess"}, \
        "instances must be packagechooser + 2 shellprocess: %r" % modules
    for mod in exec_mods + phases[0]["modules"] + phases[2]["modules"]:
        if "@" in mod:
            assert mod.split("@", 1)[1] in ids, \
                "sequence references undefined instance %s" % mod
    for i in cfg["instances"]:
        assert i["config"].endswith(".conf"), "bad instance config %r" % i
    ok("settings.conf: 9 top-level scalars, show/exec/show, %d exec jobs, 3 instances, order gates" % len(exec_mods))


def check_module_configs(root, cfg):
    mdir = root / "config/calamares/modules"
    expected = {i["config"] for i in cfg["instances"]}
    for mod in (cfg["sequence"][1]["modules"] + cfg["sequence"][0]["modules"]
                + cfg["sequence"][2]["modules"]):
        if "@" in mod:
            continue                      # instance configs already in `expected`
        if mod in UPSTREAM_DEFAULT_MODULES:
            continue                      # Calamares ships the default
        expected.add("%s.conf" % mod)
    for name in sorted(expected):
        p = mdir / name
        assert p.is_file(), "missing module config: config/calamares/modules/%s" % name
        t = read(p)
        assert t.startswith(("---", "#")), "%s must be YAML-ish (start with --- or a comment)" % name
        assert "---" in t, "%s lost its YAML document marker" % name
        assert "\t" not in t, "%s contains a TAB" % name
        assert "\r" not in t, "%s has CRLF line endings" % name
    ok("module configs: %d files present, YAML markers, no tabs/CRLF" % len(expected))

    # RISK-004: never auto-select a disk; always allow manual partitioning.
    part = read(mdir / "partition.conf")
    assert scalar(part, "initialPartitioningChoice") == "none", \
        "RISK-004: partition.conf must NOT auto-select a disk"
    assert scalar(part, "allowManualPartitioning") == "true", \
        "RISK-004: manual partitioning must be offered"
    assert scalar(part, "defaultFileSystemType") == "ext4", "ext4 is the v0.1 default"
    assert scalar(part, "luksDefault") == "false", "encryption must be OPT-IN"
    assert scalar(part, "efiSystemPartitionSize") == "512M", "ESP must be 512 MiB"
    ok("RISK-004 partition gate: no auto disk selection, manual offered, ext4, opt-in LUKS")

    # RISK-013: live user removed; no passwordless sudo / autologin on target.
    assert scalar(read(mdir / "removeuser.conf"), "username") == "ar0x", \
        "RISK-013: removeuser.conf must remove the live `ar0x` account"
    users = read(mdir / "users.conf")
    assert scalar(users, "doAutologin") == "false", "RISK-013: no autologin on target"
    assert "NOPASSWD" not in users, "RISK-013: NOPASSWD in users.conf"
    assert scalar(users, "sudoersGroup") == "wheel", "wheel sudo group required"
    ok("RISK-013 guards: live user removed, doAutologin=false, zero NOPASSWD")

    # Offline install: NEVER a bare pacman -Sy / -Syu / --noconfirm.
    pkgs = read(mdir / "packages.conf")
    assert scalar(pkgs, "backend") == "pacman", "packages backend must be pacman"
    for key in ("update_db", "update_system"):
        assert scalar(pkgs, key) == "false", \
            "%s=true would run pacman -Sy offline (forbidden)" % key
    assert scalar(pkgs, "skip_if_no_internet") == "true", "skip_if_no_internet required"
    # Strip comment lines first: the header legitimately NAMES the forbidden
    # operations while documenting why they are banned.
    pkgs_body = "\n".join(l for l in pkgs.splitlines()
                           if not l.lstrip().startswith("#"))
    for bad in ("-Syu", "--noconfirm", "pacman -Sy"):
        assert bad not in pkgs_body, \
            "forbidden pacman operation in packages.conf: %s" % bad
    ok("packages.conf: pacman backend, fully offline, no -Sy/-Syu/--noconfirm")

    # unpackfs: archiso 92 squashfs path, valid sourcefs only.
    unpack = read(mdir / "unpackfs.conf")
    assert "/run/archiso/bootmnt/ar0x/x86_64/airootfs.sfs" in unpack, \
        "unpackfs source must match install_dir=ar0x (archiso 92)"
    assert scalar(unpack, "sourcefs") == "squashfs" or "sourcefs: squashfs" in unpack, \
        "Calamares 3.4 accepts only sourcefs: squashfs"
    assert 'sourcefs: "directory"' not in unpack, "invalid sourcefs: directory"
    assert scalar(read(mdir / "umount.conf"), "emergency") == "true", \
        "umount.conf needs emergency: true or the target stays mounted"
    ok("unpackfs/umount: archiso 92 squashfs path, valid sourcefs, emergency umount")

    # shellprocess traps: NO `args:`/`arguments:` keys, no dontChroot on target jobs.
    for name in ("shellprocess-prep.conf", "shellprocess-finish.conf"):
        t = read(mdir / name)
        assert not re.search(r"^\s*(args|arguments)\s*:", t, re.M), \
            "%s uses a key shellprocess does not have" % name
        assert scalar(t, "dontChroot") == "false", \
            "%s must run INSIDE the target chroot" % name
        assert "script:" in t, "%s has no script list" % name
    assert "/usr/lib/ar0x/ar0x-installer-finish" in read(mdir / "shellprocess-finish.conf"), \
        "finish job lost the ar0x first-boot helper"
    ok("shellprocess: 2 instances, no args/arguments keys, dontChroot=false, finish helper wired")


def check_package_groups(root):
    t = read(root / "config/calamares/modules/ar0x-packages.conf")
    assert scalar(t, "method") == "packages", "packagechooser method must be `packages`"
    ids = re.findall(r"^\s*- id:\s*(\S+)\s*$", t, re.M)
    assert ids == ["minimal", "standard", "full"], \
        "ar0x-packages.conf must have exactly minimal/standard/full, got %r" % ids
    names = re.findall(r"^\s*- ([a-z0-9][a-z0-9.+-]*)\s*$", t, re.M)
    # Drop YAML keys that look like list entries (none in practice, but be safe).
    names = [n for n in names if n not in ("install", "remove", "localInstall")]
    official = read(root / "config/packages.x86_64") + "\n" + \
               read(root / "config/tools/extra-groups.conf")
    for n in names:
        for bad in FORBIDDEN_PACKAGE_WORDS:
            assert bad not in n, "RISK-010: forbidden package %r" % n
        assert re.search(r"(?m)^\s*%s(\s|$)" % re.escape(n), official), \
            "RISK-010: %r is not an in-tree official package" % n
    assert "calamares" not in names, "calamares is a Phase 11 ISO gate, not a user group"
    ok("ar0x-packages.conf: 3 groups, %d official-only packages, zero AUR/-git/-bin" % len(names))


def check_branding(root):
    desc = read(root / "config/calamares/branding/ar0x/branding.desc")
    assert scalar(desc, "componentName") == "ar0x", "componentName must be ar0x"
    assert scalar_any(desc, "productName") == "ar0x", "ADR-025: productName must be ar0x"
    assert "ar0x root" in desc, "ADR-025: versionedName must carry the ar0x root codename"
    assert scalar(desc, "slideshow") == "show.qml", "slideshow must point at show.qml"
    assert scalar(desc, "slideshowAPI") == "2", "slideshowAPI 2 required by Calamares 3.4"
    env = read(root / "config/versions.env")
    pins = dict(re.findall(
        r'^AR0X_(VOID|SURFACE|CYAN|MAGENTA|LIME|TEXT|MUTED|ALERT)="(#[0-9A-Fa-f]{6})"',
        env, re.M))
    assert len(pins) == 8, "versions.env lost the 8 ADR-015 palette pins"
    for key, hexv in pins.items():
        assert hexv in desc, "branding.desc missing %s %s" % (key, hexv)
    assert not any("SigLevel = %s" % b in desc for b in UNSAFE_SIGLEVELS)
    qml = read(root / "config/calamares/branding/ar0x/show.qml")
    for key in ("VOID", "CYAN", "MAGENTA", "LIME", "TEXT", "MUTED"):
        assert pins[key] in qml, "show.qml missing %s %s" % (key, pins[key])
    assert "function onActivate()" in qml and "function onLeave()" in qml, \
        "slideshowAPI 2 requires onActivate()/onLeave()"
    assert "import QtQuick" in qml, "show.qml must import QtQuick"
    logo = root / "config/calamares/branding/ar0x/ar0x-logo.png"
    assert logo.is_file(), "ar0x-logo.png mirror missing (run configure-installer.sh --sync)"
    master = root / "assets/logo/ar0x-logo-256.png"
    assert hashlib.sha256(logo.read_bytes()).digest() == \
           hashlib.sha256(master.read_bytes()).digest(), \
        "ar0x-logo.png is not byte-identical to assets/logo/ar0x-logo-256.png"
    assert "productLogo" in desc and "ar0x-logo.png" in desc, \
        "branding.desc must reference the logo mirror"
    ok("branding: componentName/strings, 8/8 palette pins, API-2 slideshow, byte-identical logo")


def check_finish(root):
    helper = read(root / "config/installer/ar0x-installer-finish")
    for needle in ("uninitialized", "ar0x-firstboot.service", "NOPASSWD",
                   "ln -sfn", "AR0X_TARGET_ROOT", "set -euo pipefail"):
        assert needle in helper, "ar0x-installer-finish missing %r" % needle
    assert "multi-user.target.wants" in helper, "first-boot unit not armed for multi-user.target"
    assert helper.startswith("#!/bin/bash"), "helper needs the bash shebang"
    desktop = read(root / "config/installer/ar0x-installer.desktop")
    assert "[Desktop Entry]" in desktop and "Exec=/usr/bin/pkexec /usr/bin/calamares" in desktop, \
        "ar0x-installer.desktop must launch calamares via pkexec (never bare root)"
    assert "NOPASSWD" not in desktop, "launcher must not grant passwordless sudo"
    unit = read(root / "packages/ar0x-welcome/ar0x-firstboot.service")
    assert "ConditionFirstBoot=yes" in unit, "first-boot unit lost ConditionFirstBoot"
    preset = read(root / "config/system/systemd/system-preset/50-ar0x.preset")
    # The preset legitimately DISCUSSES the unit in comments; only active
    # enable/disable directives may not mention it.
    preset_active = "\n".join(l for l in preset.splitlines()
                               if l.strip() and not l.strip().startswith("#"))
    assert "ar0x-firstboot.service" not in preset_active, \
        "RISK-013: first-boot unit must NOT be in the live-ISO preset"
    ok("finish wiring: first-boot sentinel, offline-safe symlink, RISK-013 guard, pkexec launcher")


def check_policy(root):
    env = read(root / "config/versions.env")
    ver = re.search(r'^AR0X_CALAMARES_VERSION="([^"]+)"', env, re.M)
    src = re.search(r'^AR0X_CALAMARES_SOURCE="([^"]+)"', env, re.M)
    sha = re.search(r'^AR0X_CALAMARES_SHA256="([^"]+)"', env, re.M)
    assert ver and ver.group(1) == "3.4.3", "RISK-003: Calamares must be pinned to 3.4.3"
    assert src and src.group(1) == "codeberg", "RISK-003: source must be codeberg"
    assert sha and len(sha.group(1)) == 64, "RISK-003: SHA256 must be 64 hex chars"
    for base in ("config/calamares", "config/installer"):
        for p in sorted((root / base).rglob("*")):
            if p.is_file() and p.suffix in (".conf", ".desc", ".qml", ".desktop", ""):
                t = read(p)
                assert "github.com/calamares/calamares" not in t, \
                    "RISK-003: archived GitHub mirror referenced in %s" % p.relative_to(root)
    flow = read(root / "docs/INSTALLER_FLOW.md")
    assert "lsblk -o NAME,SIZE,MODEL,TRAN" in flow, \
        "RISK-004: INSTALLER_FLOW.md lost the lsblk device verification"
    assert "RISK-004" in flow and "RISK-013" in flow, \
        "INSTALLER_FLOW.md must restate both risks at the top"
    assert "QEMU" in flow, "INSTALLER_FLOW.md needs the disposable-VM test flow"
    # calamares is NOT on the ISO package list yet (Phase 11 gate).
    active = [l.strip() for l in read(root / "config/packages.x86_64").splitlines()
              if l.strip() and not l.strip().startswith("#")]
    assert "calamares" not in active, \
        "calamares 3.4.3 is not in official repos; it must arrive from signed [ar0x] (Phase 11)"
    ok("policy gates: Codeberg 3.4.3 + SHA256, RISK-004 flow, calamares deferred to Phase 11")


def run_checks(source_root):
    root = Path(source_root)
    print("=== ar0x Phase 10 installer validation ===")
    cfg = parse_settings(read(root / "config/calamares/settings.conf"))
    check_settings(cfg)
    check_module_configs(root, cfg)
    check_package_groups(root)
    check_branding(root)
    check_finish(root)
    check_policy(root)
    print("[ OK ] Phase 10 installer validation PASSED")
    return 0


# --- Section 2: self-test ----------------------------------------------------
def _mini_root(src, tmp, mutate=None):
    """Copy just the files run_checks() needs into a temp SOURCE_ROOT."""
    for rel in ("config/calamares", "config/installer", "config/versions.env", "config/packages.x86_64",
                "config/tools/extra-groups.conf", "docs/INSTALLER_FLOW.md",
                "packages/ar0x-welcome/ar0x-firstboot.service",
                "config/system/systemd/system-preset/50-ar0x.preset",
                "assets/logo/ar0x-logo-256.png"):
        s, d = src / rel, tmp / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        if s.is_dir():
            shutil.copytree(s, d)
        else:
            shutil.copyfile(s, d)
    if mutate:
        mutate(tmp)


def _expect_fail(label, src, mutate, needle):
    tmp = Path(tempfile.mkdtemp(prefix="ar0x-p10-neg-"))
    try:
        _mini_root(src, tmp, mutate)
        try:
            run_checks(tmp)
        except AssertionError as exc:
            assert needle in str(exc) or needle == "*", \
                "%s: wrong failure: %s" % (label, exc)
            print("[ OK ] negative test: %s correctly rejected" % label)
            return
        raise AssertionError("%s: validator ACCEPTED a broken config" % label)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def self_test(source_root):
    src = Path(source_root)
    print("=== ar0x Phase 10 offline self-test ===")
    run_checks(src)

    def edit(rel, old, new):
        def fn(root):
            p = root / rel
            t = read(p)
            assert old in t, "self-test fixture drift: %r absent in %s" % (old, rel)
            p.write_text(t.replace(old, new, 1), encoding="utf-8")
        return fn

    _expect_fail("prompt-install disabled (RISK-004)", src,
                 edit("config/calamares/settings.conf", "prompt-install: true",
                      "prompt-install: false"), "prompt-install")
    _expect_fail("branding renamed", src,
                 edit("config/calamares/settings.conf", "branding: ar0x",
                      "branding: default"), "branding")
    _expect_fail("finished phase removed", src,
                 edit("config/calamares/settings.conf", "  - finished",
                      "  - welcome"), "final show phase")
    _expect_fail("auto disk selection enabled (RISK-004)", src,
                 edit("config/calamares/modules/partition.conf",
                      "initialPartitioningChoice: none",
                      "initialPartitioningChoice: erase"), "auto-select")
    _expect_fail("live user not removed (RISK-013)", src,
                 edit("config/calamares/modules/removeuser.conf",
                      "username: ar0x", "username: liveuser"), "live `ar0x`")
    _expect_fail("AUR package in group (RISK-010)", src,
                 edit("config/calamares/modules/ar0x-packages.conf",
                      "        - jq\n", "        - yay\n"), "RISK-010")
    _expect_fail("palette pin changed (ADR-015)", src,
                 edit("config/calamares/branding/ar0x/branding.desc",
                      '"#00E5FF"', '"#00E5FE"'), "missing CYAN")
    _expect_fail("bare pacman -Syu in offline install", src,
                 edit("config/calamares/modules/packages.conf",
                      "update_db: false", "update_db: true"), "update_db=true")
    _expect_fail("archived GitHub mirror (RISK-003)", src,
                 edit("config/calamares/settings.conf", "modules-search: [ local ]",
                      "# source: github.com/calamares/calamares\nmodules-search: [ local ]"),
                 "archived GitHub mirror")

    # --- REAL run of ar0x-installer-finish into a throwaway target root -----
    helper = src / "config/installer/ar0x-installer-finish"
    target = Path(tempfile.mkdtemp(prefix="ar0x-p10-target-"))
    try:
        (target / "etc/sudoers.d").mkdir(parents=True)
        (target / "etc/sudoers.d/10-ar0x-wheel").write_text("%wheel ALL=(ALL:ALL) ALL\n")
        env = dict(os.environ, AR0X_TARGET_ROOT=str(target))
        r = subprocess.run(["bash", str(helper)], env=env,
                           capture_output=True, text=True)
        assert r.returncode == 0, "finish helper failed: %s %s" % (r.stdout, r.stderr)
        assert (target / "etc/machine-id").read_text() == "uninitialized\n", \
            "systemd first-boot sentinel not written"
        link = target / "etc/systemd/system/multi-user.target.wants/ar0x-firstboot.service"
        assert link.is_symlink() and os.readlink(link) == \
               "/usr/lib/systemd/system/ar0x-firstboot.service", "first-boot unit not armed"
        assert (target / "var/lib/ar0x/installer-finished").is_file(), "install stamp missing"
        # Idempotency: second run must be a no-op, not an error.
        r2 = subprocess.run(["bash", str(helper)], env=env,
                            capture_output=True, text=True)
        assert r2.returncode == 0 and "idempotent no-op" in r2.stdout, \
            "finish helper is not idempotent"
        ok("finish helper: sentinel + symlink + stamp really written; second run is a no-op")

        # Negative: a surviving NOPASSWD sudoers rule MUST abort the install.
        bad = Path(tempfile.mkdtemp(prefix="ar0x-p10-bad-"))
        try:
            (bad / "etc/sudoers.d").mkdir(parents=True)
            (bad / "etc/sudoers.d/99-leak").write_text("%wheel ALL=(ALL) NOPASSWD: ALL\n")
            env2 = dict(os.environ, AR0X_TARGET_ROOT=str(bad))
            r3 = subprocess.run(["bash", str(helper)], env=env2,
                                capture_output=True, text=True)
            assert r3.returncode != 0 and "RISK-013" in r3.stderr, \
                "finish helper accepted a passwordless sudoers rule"
            ok("RISK-013 negative test: NOPASSWD sudoers rule correctly aborts the install")
        finally:
            shutil.rmtree(bad, ignore_errors=True)
    finally:
        shutil.rmtree(target, ignore_errors=True)

    print("[ OK ] Phase 10 offline self-test PASSED")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("usage: ar0x_installer.py <SOURCE_ROOT> [--self-test]\n")
        sys.exit(2)
    try:
        if "--self-test" in sys.argv:
            sys.exit(self_test(Path(sys.argv[1])))
        sys.exit(run_checks(Path(sys.argv[1])))
    except (AssertionError, OSError, ValueError) as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        sys.exit(1)
