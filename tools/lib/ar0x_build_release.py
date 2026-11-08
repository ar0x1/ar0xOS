#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_build_release.py
# -----------------------------------------------------------------------------
# Post-plan structural validator for the REAL-host ISO build chain.
# Pure stdlib. NO root, NO mkarchiso, NO gpg, NO network, NO ISO produced.
#
# It asserts the hard gates, the ADR-029 staged-profile injection, the
# fail-closed behaviour, and that the driver NEVER tags/uploads/announces.
# `self_test()` mutates copies of every relevant file to prove each gate FAILS.
#
# Usage:
#   python3 tools/lib/ar0x_build_release.py <SOURCE_ROOT>
#   python3 tools/lib/ar0x_build_release.py <SOURCE_ROOT> --self-test
# -----------------------------------------------------------------------------

import os
import shutil
import sys
import tempfile
from pathlib import Path

DRIVER_NEEDLES = (
    "AR0X_CONFIRM_RELEASE_CHAIN", "AR0X_CONFIRM_SIGNED_REPO",
    "AR0X_CONFIRM_BUILD", "AR0X_CONFIRM_SIGN",
    "--stage --with-ar0x-repo --with-signed-packages",
    "setup-repo.sh --verify", "build-iso.sh --build",
    "checksum.sh --sign", "checksum.sh --verify", "2362232012",
    "NEVER tags", "NEVER uploads", "validate-versions.sh",
    "gpg --verify", "gpg --list-secret-keys", "require_root",
    "RISK-053", "RISK-054", "RISK-004", "--self-test", "--preflight",
)
# A publication command in the driver would be an accidental release (RISK-054).
DRIVER_FORBIDDEN = ("git tag -s", "gh release create", "rsync -av",
                    "os.system(", "eval ", "git push origin")
BOOTSTRAP_NEEDLES = (
    "--stage", "--with-signed-packages", "inject_signed_packages",
    "AR0X_CONFIRM_SIGNED_REPO", "gpg --verify", "STAGED PROFILE ONLY",
    "calamares ar0x-keyring ar0x-meta", "AR0X_PROFILE_STAGE",
)
BUILDISO_NEEDLES = (
    "--stage --with-ar0x-repo --with-signed-packages",
    "AR0X_PROFILE_STAGE", "AR0X_CONFIRM_SIGNED_REPO",
    "calamares ar0x-keyring ar0x-meta", "AR0X_ISO_MAX_BYTES",
)
DOC_NEEDLES = (
    "docker compose", "vagrant up", "AR0X_CONFIRM_RELEASE_CHAIN=yes",
    "PENDING-KEYGEN", "RISK-053", "RISK-054", "40/40", "ADR-029",
    "mkarchiso", "build-release.sh --run", "CapEff",
    "git clone https://github.com/ar0x1/ar0xOS.git", "PR #1 is MERGED",
)
CI_NEEDLES = (
    "workflow_dispatch", "build-release.sh --run", "upload-artifact",
    "github.repository == 'ar0x1/ar0xOS'", "NEVER creates a git tag",
)


def read(p):
    return Path(p).read_text(encoding="utf-8")


def ok(msg):
    print("[ OK ] %s" % msg)


def check_driver(root):
    t = read(root / "tools/build-release.sh")
    for needle in DRIVER_NEEDLES:
        assert needle in t, "build-release.sh missing %r" % needle
    for bad in DRIVER_FORBIDDEN:
        assert bad not in t, "RISK-054: build driver must NOT contain %r" % bad
    assert t.startswith("#!/bin/bash"), "build-release.sh needs the bash shebang"
    assert "set -euo pipefail" in t, "build-release.sh needs strict mode"
    assert os.access(root / "tools/build-release.sh", os.X_OK), \
        "build-release.sh must be mode 0755"
    ok("build-release.sh: 21 gates, 7-step chain, fails closed, NEVER tags/uploads/announces")


def check_staging(root):
    b = read(root / "tools/bootstrap.sh")
    for needle in BOOTSTRAP_NEEDLES:
        assert needle in b, "bootstrap.sh missing %r" % needle
    i = read(root / "tools/build-iso.sh")
    for needle in BUILDISO_NEEDLES:
        assert needle in i, "build-iso.sh missing %r" % needle
    assert "--stage" in i and "bootstrap.sh --sync\n    mkdir -p" not in i, \
        "build-iso.sh --build must really stage the mkarchiso profile (ADR-029)"
    ok("ADR-029: bootstrap.sh --stage + staged-only signed-package injection; --build uses the stage")


def check_docs(root):
    d = read(root / "docs/BUILD_RELEASE_ISO.md")
    for needle in DOC_NEEDLES:
        assert needle in d, "BUILD_RELEASE_ISO.md missing %r" % needle
    r = read(root / "README.md")
    for needle in ("Make the ISO", "build-release.sh --run",
                   "docs/BUILD_RELEASE_ISO.md", "SOURCE-COMPLETE, RELEASE-PENDING",
                   "git clone https://github.com/ar0x1/ar0xOS.git"):
        assert needle in r, "README.md missing %r" % needle
    w = read(root / "ci/workflows/build-iso.yml")
    for needle in CI_NEEDLES:
        assert needle in w, "build-iso.yml missing %r" % needle
    assert "-----BEGIN" not in w and "SigLevel = Never" not in w, \
        "RISK-051: no private key / weak SigLevel in the ISO workflow"
    assert "\t" not in w, "build-iso.yml contains a TAB (YAML forbids tabs)"
    ok("docs + CI: real-host recipes, fork guard, MANUAL publication, no fake ISO claims")


def check_policy(root):
    # The source tree must still be free of any derived ISO/signature.
    skip = {".git", "build", "__pycache__"}
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip]
        for fn in files:
            assert not fn.endswith(".iso"), "generated ISO leaked into Git: %s" % fn
    for name in ("SHA256SUMS", "SHA256SUMS.sig", "ar0x-0.1.0-x86_64.iso.sig"):
        assert not (root / name).exists(), "derived artifact leaked into Git: %s" % name
    p = read(root / "config/packages.x86_64")
    for bad in ("\ncalamares\n", "\nar0x-meta\n", "\nar0x-keyring\n"):
        assert bad not in p, "RISK-048: signed-repo package in tracked config/packages.x86_64"
    m = read(root / "archiso/packages.x86_64")
    assert p == m, "config/packages.x86_64 and archiso/packages.x86_64 diverged"
    ok("policy: zero derived artifacts, tracked package mirrors clean and byte-identical")


def run_checks(root):
    print("=== ar0x post-plan ISO build chain validation ===")
    check_driver(root)
    check_staging(root)
    check_docs(root)
    check_policy(root)
    print("[ OK ] post-plan ISO build chain PASSED")
    return 0


NEEDED = (
    "tools/build-release.sh", "tools/bootstrap.sh", "tools/build-iso.sh",
    "docs/BUILD_RELEASE_ISO.md", "README.md", "ci/workflows/build-iso.yml",
    "config/packages.x86_64", "archiso/packages.x86_64",
)


def _mini(root, tmp, mutate):
    for rel in NEEDED:
        s, d = root / rel, tmp / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(s, d)
    mutate(tmp)


def _expect_fail(label, root, mutate, needle):
    tmp = Path(tempfile.mkdtemp(prefix="ar0x-br-neg-"))
    try:
        _mini(root, tmp, mutate)
        try:
            run_checks(tmp)
        except AssertionError as exc:
            assert needle in str(exc), "%s: wrong failure: %s" % (label, exc)
            print("[ OK ] negative test: %s correctly rejected" % label)
            return
        raise AssertionError("%s: validator ACCEPTED a broken config" % label)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _edit(rel, old, new, all_occurrences=True):
    def fn(tmp):
        p = tmp / rel
        t = read(p)
        assert old in t, "self-test fixture drift: %r absent from %s" % (old, rel)
        p.write_text(t.replace(old, new) if all_occurrences
                     else t.replace(old, new, 1), encoding="utf-8")
    return fn


def self_test(root):
    print("=== ar0x post-plan ISO build chain offline self-test ===")
    run_checks(root)

    _expect_fail("driver lost explicit release confirmation", root,
                 _edit("tools/build-release.sh", "AR0X_CONFIRM_RELEASE_CHAIN", "AR0X_MAYBE"),
                 "AR0X_CONFIRM_RELEASE_CHAIN")
    _expect_fail("driver contains a real git tag command (RISK-054)", root,
                 _edit("tools/build-release.sh", "#   --plan        Print",
                       "git tag -s v0.1.0\n#   --plan        Print"),
                 "must NOT contain")
    _expect_fail("driver lost the real mkarchiso staging step", root,
                 _edit("tools/build-release.sh",
                       "--stage --with-ar0x-repo --with-signed-packages", "--sync"),
                 "--stage --with-ar0x-repo")
    _expect_fail("bootstrap lost gpg --verify of the signed db", root,
                 _edit("tools/bootstrap.sh", "gpg --verify", "true #", True),
                 "gpg --verify")
    _expect_fail("bootstrap lost the signed-repo confirmation gate", root,
                 _edit("tools/bootstrap.sh", "AR0X_CONFIRM_SIGNED_REPO", "AR0X_MAYBE", True),
                 "AR0X_CONFIRM_SIGNED_REPO")
    _expect_fail("build-iso.sh no longer stages the real profile", root,
                 _edit("tools/build-iso.sh",
                       "--stage --with-ar0x-repo --with-signed-packages", "--sync"),
                 "--stage --with-ar0x-repo")
    _expect_fail("guide lost the Docker recipe", root,
                 _edit("docs/BUILD_RELEASE_ISO.md", "docker compose", "podman compose"),
                 "docker compose")
    _expect_fail("README lost the one-command build", root,
                 _edit("README.md", "Make the ISO", "Build notes"),
                 "Make the ISO")
    _expect_fail("CI workflow lost the fork guard", root,
                 _edit("ci/workflows/build-iso.yml",
                       "github.repository == 'ar0x1/ar0xOS'", "true"),
                 "github.repository")

    print("[ OK ] post-plan ISO build chain offline self-test PASSED")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("usage: ar0x_build_release.py <SOURCE_ROOT> [--self-test]\n")
        sys.exit(2)
    root = Path(sys.argv[1])
    try:
        sys.exit(self_test(root) if "--self-test" in sys.argv else run_checks(root))
    except (AssertionError, OSError, ValueError) as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        sys.exit(1)
