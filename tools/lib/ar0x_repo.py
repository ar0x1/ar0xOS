#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_repo.py
# -----------------------------------------------------------------------------
# PHASE 9 — pure-standard-library validator for the signed [ar0x] repository.
#
# WHY NOT `repo-add`, `gpg`, `makepkg`, `namcap`, `shellcheck`, `pacman-key` or
# a YAML library: none is installed in this sandbox, and all of the real ones
# need an Arch host + root + a private key. This module does the STRUCTURAL
# checks that CAN be done offline, plus a mock-repo self-test.
# docs/REPO_GUIDE.md §9 lists exactly what still needs a real Arch host.
#
# Usage: python3 tools/lib/ar0x_repo.py <SOURCE_ROOT> [--self-test]
#        import ar0x_repo; ar0x_repo.run_checks(root)
# -----------------------------------------------------------------------------

"""Offline structural validation of the ar0x package repository layer."""

import hashlib
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ar0x_pkgbuild as P   # noqa: E402  (shared PKGBUILD + ownership checks)

ALL_PACKAGES = P.ALL_PACKAGES
# Dependency/topological build order. ar0x-meta depends on the other seven,
# ar0x-welcome depends on ar0x-info + ar0x-update. `makepkg --nodeps` avoids
# resolving intra-repo depends before the local db exists.
BUILD_ORDER = ("ar0x-info", "ar0x-update", "ar0x-keyring", "ar0x-welcome",
               "ar0x-theme", "ar0x-wallpapers", "ar0x-hypr-config", "ar0x-meta")
UNSAFE_SIGLEVELS = ("Never", "Optional", "TrustAll", "DatabaseNever",
                    "PackageOptional", "PackageTrustAll")


# --- Section 1: tiny helpers -------------------------------------------------

def read(rel):
    return Path(rel).read_text(encoding="utf-8")


def ok(msg):
    print("[ OK ] %s" % msg)


def warn(msg):
    print("[WARN] %s" % msg)


def parse_conf(path):
    """Parse plain KEY="value" lines. Comments and blank lines are ignored."""
    out = {}
    for line in read(path).splitlines():
        m = re.match(r'^\s*([A-Z0-9_]+)\s*=\s*"([^"]*)"\s*$', line)
        if m:
            # `\$arch` protects a literal pacman.conf placeholder from shell
            # expansion when the data file is sourced under `set -u`.
            out[m.group(1)] = m.group(2).replace("\\$", "$")
    return out


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def repo_problems(repo_dir, db="ar0x.db.tar.zst", files_db="ar0x.files.tar.zst",
                  require_sums=True):
    """Return a list of problems with a built repo directory. Pure filesystem
    inspection — NO gpg/pacman/network. Used by --verify and --self-test."""
    d = Path(repo_dir)
    problems = []
    if not d.is_dir():
        return ["not a directory: %s" % d]
    mandatory = [db, db + ".sig", files_db, files_db + ".sig"]
    if require_sums:
        mandatory += ["SHA256SUMS", "SHA256SUMS.sig"]
    for name in mandatory:
        if not (d / name).is_file():
            problems.append("missing %s" % name)
    pkgs = sorted(p.name for p in d.glob("*.pkg.tar.zst"))
    if not pkgs:
        problems.append("no *.pkg.tar.zst packages")
    for name in pkgs:
        if not name.startswith("ar0x-"):
            problems.append("non-ar0x package in repo: %s" % name)
        if not (d / (name + ".sig")).is_file():
            problems.append("missing detached signature for %s" % name)
    if require_sums and (d / "SHA256SUMS").is_file():
        for line in read(d / "SHA256SUMS").splitlines():
            if not line.strip():
                continue
            m = re.match(r'^([0-9a-f]{64})\s+\*?(\S+)$', line)
            if not m:
                problems.append("malformed SHA256SUMS line: %r" % line)
            elif not (d / m.group(2)).is_file():
                problems.append("SHA256SUMS references missing file: %s" % m.group(2))
    # A private key or an uncompressed keyring must never be published.
    for name in sorted(p.name for p in d.iterdir()):
        if any(k in name.lower() for k in ("private", "secret", "secring", ".key")):
            problems.append("secret-looking file in publish tree: %s" % name)
    return problems


def build_manifest(repo_dir):
    """name -> sha256 for every regular file in a repo tree (deterministic)."""
    d = Path(repo_dir)
    return {p.name: sha256(p) for p in sorted(d.iterdir()) if p.is_file()}


# --- Section 2: config / policy parity ---------------------------------------

def validate_repo_options(root):
    conf = parse_conf(root / "config/repo/repo-options.conf")
    env = P.parse_env(root / "config/versions.env")
    for key in ("AR0X_REPO_NAME", "AR0X_REPO_DB", "AR0X_REPO_FILES_DB",
                "AR0X_REPO_SIGLEVEL", "AR0X_REPO_SERVER", "AR0X_REPO_KEEP_OLD",
                "AR0X_REPO_CI_IMAGE", "AR0X_REPO_CI_BUILDER",
                "AR0X_REPO_SIGN_PACKAGES", "AR0X_REPO_INCLUDE_SIGS",
                "AR0X_REPO_VERIFY_EXISTING", "AR0X_REPO_REMOVE_OLD"):
        assert key in conf, "repo-options.conf missing %s" % key
    for key in ("AR0X_REPO_NAME", "AR0X_REPO_DB", "AR0X_REPO_FILES_DB",
                "AR0X_REPO_SIGLEVEL", "AR0X_REPO_SERVER", "AR0X_REPO_KEEP_OLD",
                "AR0X_REPO_CI_IMAGE", "AR0X_REPO_CI_BUILDER",
                "AR0X_REPO_SIGN_PACKAGES"):
        assert key in env, "versions.env missing %s" % key
        assert conf[key] == env[key], "%s differs between repo-options.conf and versions.env" % key
    assert conf["AR0X_REPO_SIGLEVEL"] == "Required", \
        "SigLevel must be Required (§9); never Optional/Never/TrustAll"
    assert conf["AR0X_REPO_NAME"] == "ar0x"
    assert conf["AR0X_REPO_DB"].endswith(".db.tar.zst")
    assert conf["AR0X_REPO_FILES_DB"].endswith(".files.tar.zst")
    assert conf["AR0X_REPO_SERVER"] == "https://repo.ar0x.dev/$arch", \
        "repo server must be the literal pacman $arch placeholder (RISK-051)"
    assert conf["AR0X_REPO_SERVER"].startswith("https://")
    assert conf["AR0X_REPO_SIGN_PACKAGES"] == "yes"
    assert conf["AR0X_REPO_INCLUDE_SIGS"] == "yes"
    assert conf["AR0X_REPO_VERIFY_EXISTING"] == "yes"
    assert conf["AR0X_REPO_REMOVE_OLD"] == "0", \
        "removing old tarballs breaks ar0x-update --rollback (ADR-024)"
    ok("repo-options.conf: 12 options, versions.env parity, SigLevel=Required, keep-old=0")


def validate_pacman_entry(root):
    entry = read(root / "config/repo/pacman.conf.ar0x-entry")
    installed = read(root / "config/pacman.conf.installed")
    env = P.parse_env(root / "config/versions.env")

    def block(text):
        lines = [l.strip() for l in text.splitlines()
                 if l.strip().startswith(("[ar0x]", "SigLevel", "Server"))
                 and not l.strip().startswith("#")]
        return [l for l in lines if "ar0x" in l.lower() or l.startswith("SigLevel = Required")]
    e = [l.strip() for l in entry.splitlines() if l.strip() and not l.strip().startswith("#")]
    assert e == ["[ar0x]", "SigLevel = Required",
                 "Server = https://repo.ar0x.dev/$arch"], \
        "config/repo/pacman.conf.ar0x-entry has unexpected data lines: %r" % e
    assert "SigLevel = Required" in installed, "installed pacman.conf lost SigLevel = Required"
    assert "Server = https://repo.ar0x.dev/$arch" in installed, \
        "installed pacman.conf lost the [ar0x] Server"
    # Compare SECTION HEADERS only: "[core]" also appears in a header comment
    # at line 10, which would false-positive a plain str.index() comparison.
    headers = [(i, l.strip()) for i, l in enumerate(installed.splitlines())
               if re.match(r'^\[[A-Za-z0-9_-]+\]\s*$', l)]
    names = [h for _, h in headers]
    assert "[ar0x]" in names and "[core]" in names and \
        names.index("[ar0x]") < names.index("[core]"), \
        "[ar0x] must precede [core] in the installed config too"
    assert env["AR0X_UPDATE_SIGLEVEL"] == "Required", "ar0x-update policy drifted"
    for bad in UNSAFE_SIGLEVELS:
        assert bad not in e[1], "unsafe SigLevel %s in [ar0x] entry" % bad
    ok("[ar0x] entry: 3 data lines, byte-policy parity with pacman.conf.installed")


def validate_release_key(root):
    fpr_file = read(root / "config/repo/RELEASE_KEY_FINGERPRINT")
    lines = [l.strip() for l in fpr_file.splitlines()
             if l.strip() and not l.strip().startswith("#")]
    assert len(lines) == 1, "fingerprint file must contain exactly one data line"
    fpr = lines[0]
    trusted = read(root / "packages/ar0x-keyring/ar0x-trusted")
    entries = [l.strip() for l in trusted.splitlines()
               if l.strip() and not l.strip().startswith("#")]
    if fpr == "PENDING-KEYGEN":
        assert not entries, "trusted list must be EMPTY before keygen"
        warn("release key NOT generated (MANUAL: sudo ./tools/setup-repo.sh --keygen); "
             "ar0x-trusted is empty, so an unsigned repo is correctly refused")
        return None
    assert re.fullmatch(r'[0-9A-F]{40}', fpr), \
        "fingerprint must be 40 uppercase hex digits, got %r" % fpr
    assert entries == ["%s:6:" % fpr], \
        "ar0x-trusted must contain exactly '%s:6:' (gpg --export-ownertrust format)" % fpr
    ok("release key: 40-hex fingerprint PENDING-free, ar0x-trusted ownertrust parity")
    return fpr


def validate_keyring(root):
    inst = read(root / "packages/ar0x-keyring/ar0x-keyring.install")
    for fn in ("post_install()", "post_upgrade()", "pacman-key --populate ar0x"):
        assert fn in inst, "ar0x-keyring.install missing %s" % fn
    # Regex, not substring: the header comment literally mentions the words.
    assert not re.search(r'^\s*set\s+-euo', inst, re.M), \
        "SOURCED scriptlet must not set strict mode"
    revoked = read(root / "packages/ar0x-keyring/ar0x-revoked")
    assert revoked == "", "ar0x-revoked must be EMPTY until a key is actually revoked"
    pb = read(root / "packages/ar0x-keyring/PKGBUILD")
    assert "gpg --batch --yes --dearmor" in pb, "PKGBUILD must dearmor the public key"
    assert "ar0x.gpg" in pb and "ar0x-trusted" in pb and "ar0x-revoked" in pb
    assert "BEGIN PGP PRIVATE KEY" not in pb
    ok("ar0x-keyring: dearmor + --populate ar0x, empty revoked list, sourced scriptlet")


def validate_build_order(root):
    assert len(BUILD_ORDER) == 8 and set(BUILD_ORDER) == set(ALL_PACKAGES), \
        "BUILD_ORDER must contain all 8 packages exactly once"
    assert BUILD_ORDER[-1] == "ar0x-meta", "ar0x-meta must be built last"
    meta = P.parse_pkgbuild(root / "packages/ar0x-meta/PKGBUILD")
    deps = set(meta["depends"])
    assert deps == set(ALL_PACKAGES) - {"ar0x-meta"}, \
        "ar0x-meta must depend on exactly the other 7 ar0x packages"
    welcome = P.parse_pkgbuild(root / "packages/ar0x-welcome/PKGBUILD")
    assert {"ar0x-info", "ar0x-update"} <= set(welcome["depends"]), \
        "ar0x-welcome must depend on ar0x-info + ar0x-update"
    assert BUILD_ORDER.index("ar0x-info") < BUILD_ORDER.index("ar0x-welcome")
    assert BUILD_ORDER.index("ar0x-update") < BUILD_ORDER.index("ar0x-welcome")
    ok("build order: 8 packages, meta last, intra-repo depends consistent")


def validate_mirrors(root):
    """Canonical -> package byte-identical mirrors for the 4 payload packages."""
    pairs = []
    for rel in ('gtk-3.0/settings.ini','gtk-3.0/gtk.css','gtk-4.0/settings.ini',
                'gtk-4.0/gtk.css','qt5ct/qt5ct.conf','qt6ct/qt6ct.conf'):
        pairs.append(('config/desktop/'+rel, 'packages/ar0x-theme/'+rel))
    pairs.append(('config/desktop/fontconfig/conf.d/99-ar0x-fonts.conf',
                  'packages/ar0x-theme/fontconfig/99-ar0x-fonts.conf'))
    for rel in ('hyprland.lua','hyprpaper.conf','hyprlock.conf','hypridle.conf'):
        pairs.append(('config/desktop/hypr/'+rel, 'packages/ar0x-hypr-config/'+rel))
    for n in ('animations','autostart','env','input','keybinds','looknfeel',
              'monitors','palette','programs','rules'):
        pairs.append(('config/desktop/hypr/lua/%s.lua'%n,
                      'packages/ar0x-hypr-config/lua/%s.lua'%n))
    for f in ('ar0x-neon-grid.png','ar0x-void.png','ar0x-circuit.png'):
        pairs.append(('assets/wallpapers/'+f, 'packages/ar0x-wallpapers/'+f))
    for f in ('ar0x-logo.svg','ar0x-logo-mono.svg','ar0x-wordmark.svg','LICENSE'):
        pairs.append(('assets/logo/'+f, 'packages/ar0x-wallpapers/'+f))
    pairs.append(('assets/grub-theme/ar0x/theme.txt','packages/ar0x-wallpapers/theme.txt'))
    pairs.append(('assets/sddm/ar0x/Main.qml','packages/ar0x-wallpapers/Main.qml'))
    pairs.append(('config/repo/pacman.conf.ar0x-entry',
                  'packages/ar0x-keyring/pacman.conf.ar0x-entry'))
    for a, b in pairs:
        assert (root / b).is_file(), "mirror missing: %s" % b
        assert (root / a).read_bytes() == (root / b).read_bytes(), \
            "%s is stale vs canonical %s (run ./tools/setup-repo.sh --sync)" % (b, a)
    ok("%d canonical -> package mirrors byte-identical (theme/hypr/wallpapers/keyring)" % len(pairs))


def validate_workflows(root):
    wf = root / "ci/workflows"
    validate = wf / "validate-packages.yml"
    build = wf / "build-packages.yml"
    release = wf / "release.yml"
    for f in (validate, build, release):
        assert f.is_file(), "missing workflow: %s" % f.name
        txt = read(f)
        assert "\t" not in txt, "%s contains a TAB (YAML forbids tabs)" % f.name
        assert "name:" in txt and "on:" in txt and "jobs:" in txt, \
            "%s is missing name/on/jobs" % f.name
    v = read(validate)
    assert "pull_request" in v, "validate workflow must run on PRs"
    assert "secrets." not in v, "PR-safe validate workflow must NOT reference secrets"
    assert "setup-repo.sh --check" in v and "validate-versions.sh" in v
    ok("ci/workflows/validate-packages.yml: PR-safe, zero secrets, runs both validators")
    b = read(build)
    for needle in ("archlinux:base-devel", "useradd", "makepkg", "--nodeps",
                   "namcap", "shellcheck", "repo-add"):
        assert needle in b, "build workflow missing %r" % needle
    assert "secrets." not in b, "build workflow must NOT reference secrets (runs on PRs)"
    assert "pull_request" in b, "build workflow should also run on PRs (unsigned)"
    # Strip comments: the build workflow EXPLAINS that release.yml is the only
    # place with `repo-add -s`, which would false-positive a raw search.
    b_code = "\n".join(l.split("#", 1)[0] for l in b.splitlines())
    assert "repo-add -s" not in b_code and "GPGKEY" not in b_code, \
        "build workflow must NOT sign; signing belongs in release.yml only"
    assert ("sudo -u \"$AR0X_REPO_CI_BUILDER\"" in b or
            "sudo -u builder" in b or "su - builder" in b), \
        "makepkg must run as a NON-ROOT builder"
    ok("ci/workflows/build-packages.yml: Arch container, non-root builder, --nodeps, namcap/shellcheck, unsigned")
    r = read(release)
    for needle in ("secrets.AR0X_RELEASE_GPG_KEY", "secrets.AR0X_GPG_PASSPHRASE",
                   "repo-add -s", "--include-sigs", "gpg --batch", "workflow_dispatch",
                   "SHA256SUMS.sig"):
        assert needle in r, "release workflow missing %r" % needle
    # Strip comments: the header EXPLAINS that pull_request is forbidden.
    pre_code = "\n".join(l.split("#", 1)[0]
                         for l in r.split("jobs:")[0].splitlines())
    assert "pull_request" not in pre_code, \
        "release workflow MUST NOT be triggered by pull_request (RISK-051)"
    assert "github.event.pull_request" in r or "fork" in r, \
        "release workflow needs an explicit fork-PR guard"
    for bad in UNSAFE_SIGLEVELS:
        assert ("SigLevel = " + bad) not in r, "release workflow weakens SigLevel: %s" % bad
    ok("ci/workflows/release.yml: secrets only on push/tag, fork guard, repo-add -s, gpg --batch")


def validate_no_secrets(root):
    text_ext = {".sh", ".py", ".yml", ".conf", ".md", ".install", ".env", ""}
    scan = []
    for sub in ("config/repo", "ci/workflows", "packages", "tools"):
        for p in sorted((root / sub).rglob("*")):
            if p.is_file() and (p.suffix in text_ext or p.name == "PKGBUILD"):
                scan.append(p)
    # Match the FULL PEM delimiter, not the bare words: the PR-safe workflow
    # legitimately uses `BEGIN PGP PRIVATE KEY` as a grep PATTERN to detect
    # leaks. Only an actual "-----BEGIN ... PRIVATE KEY" armored block is a leak.
    bad_re = re.compile(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY')
    for p in scan:
        try:
            txt = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue                     # binary PNG / SVG assets
        assert not bad_re.search(txt), "private-key material in %s" % p
        if p.suffix in (".yml", ".sh") and ".gitkeep" not in p.name:
            assert "SigLevel = Never" not in txt, "SigLevel = Never in %s" % p
    # No private key / derived public key may be committed to Git.
    for name in ("packages/ar0x-keyring/ar0x-public-key.asc",
                 "config/repo/ar0x-private-key.asc"):
        if (root / name).is_file():
            warn("derived key artifact exists locally (gitignored, MANUAL): %s" % name)
    ok("no private-key material in %d scanned source files; no SigLevel = Never" % len(scan))


# --- Section 3: offline self-test with a mock repo ---------------------------

def self_test(root):
    print("=== ar0x Phase 9 offline self-test ===")
    tmp = tempfile.mkdtemp(prefix="ar0x-repo-selftest-")
    try:
        d = Path(tmp) / "x86_64"
        d.mkdir()
        names = ["ar0x.db.tar.zst", "ar0x.files.tar.zst"]
        for n in names:
            (d / n).write_bytes(b"mock-db")
            (d / (n + ".sig")).write_bytes(b"mock-sig")
        pkgs = ["%s-0.1.0-1-any.pkg.tar.zst" % n for n in ALL_PACKAGES]
        for n in pkgs:
            (d / n).write_bytes(("mock-" + n).encode())
            (d / (n + ".sig")).write_bytes(b"mock-sig")
        sums = "".join("%s  %s\n" % (sha256(d / n), n)
                       for n in sorted(p.name for p in d.iterdir() if p.is_file()))
        (d / "SHA256SUMS").write_text(sums, encoding="utf-8")
        (d / "SHA256SUMS.sig").write_bytes(b"mock-sig")

        probs = repo_problems(d)
        assert not probs, "valid mock repo rejected: %r" % probs
        ok("repo_problems(): valid signed mock repo accepted (8 packages + 2 dbs + SHA256SUMS)")

        (d / (pkgs[0] + ".sig")).unlink()
        probs = repo_problems(d)
        assert any("detached signature" in x for x in probs), \
            "missing package .sig was NOT detected"
        (d / (pkgs[0] + ".sig")).write_bytes(b"mock-sig")
        ok("repo_problems(): missing package .sig correctly rejected (negative test)")

        (d / "my-private-key.asc").write_bytes(b"x")
        probs = repo_problems(d)
        assert any("secret-looking" in x for x in probs), "secret-looking file NOT detected"
        (d / "my-private-key.asc").unlink()
        ok("repo_problems(): secret-looking file in publish tree correctly rejected")

        (d / "evil-1-any.pkg.tar.zst").write_bytes(b"x")
        (d / "evil-1-any.pkg.tar.zst.sig").write_bytes(b"x")
        probs = repo_problems(d)
        assert any("non-ar0x" in x for x in probs), "foreign package NOT detected"
        (d / "evil-1-any.pkg.tar.zst").unlink(); (d / "evil-1-any.pkg.tar.zst.sig").unlink()
        ok("repo_problems(): foreign package correctly rejected")

        man = build_manifest(d)
        assert man["ar0x.db.tar.zst"] == sha256(d / "ar0x.db.tar.zst")
        assert len(man) == len(list(p.name for p in d.iterdir() if p.is_file()))
        ok("build_manifest(): deterministic sha256 over every repo file")

        conf = parse_conf(root / "config/repo/repo-options.conf")
        assert conf["AR0X_REPO_SIGLEVEL"] == "Required"
        ok("parse_conf(): plain KEY=value repo policy parsed without executing a shell")

        validate_build_order(root)
        validate_pacman_entry(root)
        validate_repo_options(root)
        validate_keyring(root)
        validate_mirrors(root)
        validate_workflows(root)
        validate_no_secrets(root)
        print("[ OK ] Phase 9 offline self-test PASSED")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --- Section 4: entry point --------------------------------------------------

def run_checks(source_root):
    root = Path(source_root)
    print("=== ar0x Phase 9 repository validation ===")
    P.run_checks(root)                 # all 8 PKGBUILDs + ownership + parity
    validate_repo_options(root)
    validate_pacman_entry(root)
    validate_release_key(root)
    validate_keyring(root)
    validate_build_order(root)
    validate_mirrors(root)
    validate_workflows(root)
    validate_no_secrets(root)
    print("[ OK ] Phase 9 repository validation PASSED")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("usage: ar0x_repo.py <SOURCE_ROOT> [--self-test]\n")
        sys.exit(2)
    try:
        if "--self-test" in sys.argv:
            sys.exit(self_test(Path(sys.argv[1])))
        sys.exit(run_checks(sys.argv[1]))
    except (AssertionError, OSError, ValueError) as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        sys.exit(1)
