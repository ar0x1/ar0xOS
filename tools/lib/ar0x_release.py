#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_release.py
# -----------------------------------------------------------------------------
# PHASE 12 — pure-stdlib release-engineering validator.
#
# NO PyYAML, NO gh, NO gpg, NO rsync, NO network, NO root, NO tag, NO upload.
# It asserts the exact 6-member artifact set, version-pin parity, the 5 welcome
# links, the DRAFT/UNRELEASED banners that prevent false release claims, and the
# RISK-051 PENDING-KEYGEN state. `self_test()` mutates copies of every config in
# a temp tree to prove each gate actually FAILS, and really assembles a mock
# release artifact set to prove the completeness gate works.
#
# Usage:
#   python3 tools/lib/ar0x_release.py <SOURCE_ROOT>
#   python3 tools/lib/ar0x_release.py <SOURCE_ROOT> --self-test
# -----------------------------------------------------------------------------

import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

ARTIFACT_SET = (
    "ar0x-0.1.0-x86_64.iso",
    "SHA256SUMS",
    "SHA256SUMS.sig",
    "ar0x-0.1.0-x86_64.iso.sig",
    "CHANGELOG.md",
    "README.md",
)
LINK_KEYS = ("DOCS", "ISSUES", "COMMUNITY", "SOURCE", "UPSTREAM")
DOC_FILES = (
    "docs/ANNOUNCEMENT.md", "docs/DISTROWATCH.md", "docs/ROADMAP.md",
    "docs/RELEASE_GUIDE.md", "docs/TESTING_CHECKLIST.md",
)
PRIVATE_KEY_RE = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY")


def read(path):
    return Path(path).read_text(encoding="utf-8")


def ok(msg):
    print("[ OK ] %s" % msg)


def parse_kv(text):
    """KEY="value" with optional trailing inline comment; no PyYAML needed."""
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


# --- Section 1: release options ---------------------------------------------
def check_options(root):
    r = conf(root, "config/release/release-options.conf")
    e = conf(root, "config/versions.env")
    assert r.get("AR0X_RELEASE_TAG") == "v" + e.get("AR0X_VERSION", ""), \
        "release tag must be v + AR0X_VERSION (v0.1.0)"
    assert r.get("AR0X_RELEASE_TAG") == e.get("AR0X_RELEASE_TAG"), \
        "release tag parity with versions.env lost"
    assert r.get("AR0X_RELEASE_ISO") == e.get("AR0X_ISO_NAME"), \
        "release ISO name must match AR0X_ISO_NAME"
    for key in ("AR0X_RELEASE_PRIMARY_HOST", "AR0X_RELEASE_REPO_SLUG",
                "AR0X_RELEASE_SECONDARY_HOST", "AR0X_RELEASE_EOL_POLICY",
                "AR0X_RELEASE_ARTIFACT_COUNT"):
        assert r.get(key) == e.get(key), "%s parity with versions.env lost" % key
    assert r.get("AR0X_RELEASE_ARTIFACT_COUNT") == "6", \
        "PROJECT_PLAN.md section 11 defines exactly 6 release artifacts"
    assert r.get("AR0X_RELEASE_MIN_CHECKLIST_GATE") == e.get("AR0X_RELEASE_CHECKLIST_GATE") == "100", \
        "release gate must require the 100% testing checklist"
    assert r.get("AR0X_RELEASE_SERIES") == "0.1.x", "0.1.x series pin drifted"
    assert "ar0x root" in r.get("AR0X_RELEASE_TITLE", ""), \
        "ADR-025: release title must carry the ar0x root codename"
    assert r.get("AR0X_RELEASE_DISTROWATCH_CONTACT") == "RESERVED-MANUAL", \
        "DistroWatch recipient must stay a RESERVED placeholder (RISK-054)"
    assert r.get("AR0X_RELEASE_FPR_FILE") == "config/repo/RELEASE_KEY_FINGERPRINT", \
        "FPR file must be the P9 canonical path"
    for key, rel in (("AR0X_RELEASE_NOTES_FILE", "CHANGELOG.md"),
                     ("AR0X_RELEASE_ANNOUNCEMENT_FILE", "docs/ANNOUNCEMENT.md"),
                     ("AR0X_RELEASE_DISTROWATCH_FILE", "docs/DISTROWATCH.md"),
                     ("AR0X_RELEASE_ROADMAP_FILE", "docs/ROADMAP.md"),
                     ("AR0X_RELEASE_GUIDE_FILE", "docs/RELEASE_GUIDE.md")):
        assert r.get(key) == rel, "%s must point at %s" % (key, rel)
        assert (root / rel).is_file(), "missing release document: %s" % rel
    names = tuple(x.strip() for x in r.get("AR0X_RELEASE_ARTIFACT_SET", "").split(","))
    assert names == ARTIFACT_SET, \
        "release artifact set drifted: %r (expected the exact 6 section-11 members)" % (names,)
    # A sourced conf must never contain a bare $ expansion (set -u would abort).
    for line in read(root / "config/release/release-options.conf").splitlines():
        if line.strip().startswith("AR0X_") and "=" in line:
            assert re.match(r'^[A-Z0-9_]+="[^$]*"$', line.strip()), \
                "bare $ expansion in a sourced release option: %r" % line
    ok("release-options.conf: 21 pins, v0.1.0/6-artifact/100% parity with versions.env")


# --- Section 2: artifact set -------------------------------------------------
def check_artifact_set(names):
    """Pure gate shared by --sync, --publish and the offline self-test."""
    return tuple(sorted(names)) == tuple(sorted(ARTIFACT_SET))


def check_artifacts(root):
    r = conf(root, "config/release/release-options.conf")
    assert check_artifact_set(r.get("AR0X_RELEASE_ARTIFACT_SET", "").split(",")), \
        "section 11 artifact set is incomplete"
    for name in ARTIFACT_SET:
        assert not (root / name).is_file() or name in ("README.md", "CHANGELOG.md"), \
            "derived artifact leaked into the Git checkout: %s" % name
    ok("artifact set: exactly 6 members, ISO/SHA256SUMS/*.sig never in the checkout")


# --- Section 3: documents (DRAFT banners prevent false claims) --------------
def check_docs(root):
    rd = read(root / "README.md")
    for needle in ("SOURCE-COMPLETE, RELEASE-PENDING", "NO downloadable ISO",
                   "PENDING-KEYGEN", "gpg --verify SHA256SUMS.sig SHA256SUMS",
                   "sha256sum -c SHA256SUMS", "lsblk -o NAME,SIZE,MODEL,TRAN",
                   "docs/TESTING_CHECKLIST.md", "repo.ar0x.dev"):
        assert needle in rd, "README.md missing %r" % needle
    assert "releases/download/v0.1.0" not in rd, \
        "RISK-054: README must NOT advertise a download link before a signed release"
    cl = read(root / "CHANGELOG.md")
    assert "## [0.1.0]" in cl and "UNRELEASED" in cl and "TEMPLATE" in cl, \
        "CHANGELOG.md lost its UNRELEASED / TEMPLATE banner (RISK-054)"
    ann = read(root / "docs/ANNOUNCEMENT.md")
    assert "DO NOT PUBLISH" in ann and "{{RELEASE_FINGERPRINT_40HEX}}" in ann \
           and "{{ISO_SHA256}}" in ann and "{{GITHUB_RELEASE_URL}}" in ann, \
        "ANNOUNCEMENT.md lost its DRAFT banner or a required placeholder"
    dw = read(root / "docs/DISTROWATCH.md")
    for needle in ("DO NOT SEND", "Project name", "Website", "Description",
                   "Installation media", "based on Arch Linux",
                   "{{DIRECT_ISO_URL}}", "waiting list", "DistroWatch Weekly"):
        assert needle in dw, "DISTROWATCH.md missing %r" % needle
    rm = read(root / "docs/ROADMAP.md")
    assert "PLANNING ONLY" in rm and "v0.2" in rm and "v1.0" in rm \
           and "Explicit non-goals" in rm, "ROADMAP.md missing its planning gate"
    g = read(root / "docs/RELEASE_GUIDE.md")
    for needle in ("--verify-tag", "--notes-file", "rsync", "gpg --verify",
                   "gh release create", "PENDING-KEYGEN", "RISK-054", "ADR-028",
                   "100%", "curl -IL", "OUT OF BAND", "6 signed artifacts"):
        assert needle in g, "RELEASE_GUIDE.md missing %r" % needle
    for rel in DOC_FILES:
        assert (root / rel).is_file(), "missing Phase 12 document: %s" % rel
    ok("docs: README/CHANGELOG/announcement/DistroWatch/roadmap/guide with DRAFT + no-fake-claim gates")


# --- Section 4: links, key state, gitignore ----------------------------------
def check_links(root):
    links = {}
    for line in read(root / "config/tools/links.conf").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        assert len(parts) == 3, "links.conf row must be KEY|Label|URL: %r" % line
        links[parts[0]] = parts[2]
    assert tuple(sorted(links)) == tuple(sorted(LINK_KEYS)), \
        "links.conf must have exactly the 5 AR0X_URL_* keys"
    e = conf(root, "config/versions.env")
    for key in LINK_KEYS:
        assert links[key] == e.get("AR0X_URL_" + key), \
            "RISK-050: AR0X_URL_%s parity with links.conf lost" % key
        assert links[key].startswith("https://"), "link must be HTTPS: %s" % key
    assert "repo.ar0x.dev" in e.get("AR0X_REPO_SERVER", ""), \
        "RISK-050: reserved mirror endpoint pin lost"
    ok("links: 5 AR0X_URL_* HTTPS pins byte-parity with versions.env, repo.ar0x.dev reserved")


def check_policy(root):
    fpr = [l.strip() for l in read(root / "config/repo/RELEASE_KEY_FINGERPRINT").splitlines()
           if l.strip() and not l.strip().startswith("#")]
    assert fpr == ["PENDING-KEYGEN"] or re.fullmatch(r"[0-9A-F]{40}", fpr[0]), \
        "RISK-051: FPR must be PENDING-KEYGEN or a published 40-hex fingerprint"
    gi = read(root / ".gitignore")
    for needle in ("SHA256SUMS", "*.iso", "*.gpg", "*.asc", "*.key", "packages.lock"):
        assert needle in gi, "RISK-051: %s must stay gitignored" % needle
    drv = read(root / "tools/prepare-release.sh")
    for needle in ("AR0X_CONFIRM_PUBLISH", "NEVER uploads", "--verify-tag",
                   "PENDING-KEYGEN", "gh release create", "rsync"):
        assert needle in drv, "prepare-release.sh missing %r" % needle
    assert "os.system" not in drv and "eval " not in drv, \
        "release driver must not exec arbitrary strings"
    skip = {".git", "build", "__pycache__"}
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip]
        for fn in files:
            p = Path(base) / fn
            if p.suffix in (".md", ".conf", ".py", ".sh", ".env", ""):
                try:
                    t = p.read_text(encoding="utf-8")
                except (UnicodeDecodeError, OSError):
                    continue
                assert not PRIVATE_KEY_RE.search(t), \
                    "RISK-051: private key material in %s" % p.relative_to(root)
    ok("policy: PENDING-KEYGEN, gitignored artifacts, print-only publish driver, no private keys")


def run_checks(source_root):
    root = Path(source_root)
    print("=== ar0x Phase 12 release validation ===")
    check_options(root)
    check_artifacts(root)
    check_docs(root)
    check_links(root)
    check_policy(root)
    print("[ OK ] Phase 12 release validation PASSED")
    return 0


# --- Section 5: self-test ----------------------------------------------------
NEEDED = (
    "config/release", "config/versions.env", "config/tools/links.conf",
    "config/repo/RELEASE_KEY_FINGERPRINT", ".gitignore",
    "README.md", "CHANGELOG.md", "docs/ANNOUNCEMENT.md",
    "docs/DISTROWATCH.md", "docs/ROADMAP.md", "docs/RELEASE_GUIDE.md",
    "docs/TESTING_CHECKLIST.md", "tools/prepare-release.sh",
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
    tmp = Path(tempfile.mkdtemp(prefix="ar0x-p12-neg-"))
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
    print("=== ar0x Phase 12 offline self-test ===")
    run_checks(src)

    def edit(rel, old, new):
        def fn(root):
            p = root / rel
            t = read(p)
            assert old in t, "self-test fixture drift: %r absent in %s" % (old, rel)
            p.write_text(t.replace(old, new, 1), encoding="utf-8")
        return fn

    _expect_fail("release tag drift (v9.9.9)", src,
                 edit("config/release/release-options.conf",
                      'AR0X_RELEASE_TAG="v0.1.0"', 'AR0X_RELEASE_TAG="v9.9.9"'),
                 "release tag must be v")
    _expect_fail("missing detached ISO signature", src,
                 edit("config/release/release-options.conf",
                      "ar0x-0.1.0-x86_64.iso.sig,", ""), "artifact set drifted")
    _expect_fail("extra artifact in the release set", src,
                 edit("config/release/release-options.conf",
                      "CHANGELOG.md,README.md", "CHANGELOG.md,README.md,EXTRA.txt"),
                 "artifact set drifted")
    _expect_fail("fake GitHub download link in README (RISK-054)", src,
                 edit("README.md", "## Status",
                      "Download: https://github.com/ar0x1/ar0xOS/releases/download/v0.1.0/\n\n## Status"),
                 "must NOT advertise")
    _expect_fail("CHANGELOG UNRELEASED banner removed", src,
                 edit("CHANGELOG.md", " — UNRELEASED", ""), "UNRELEASED")
    _expect_fail("announcement DRAFT banner removed", src,
                 edit("docs/ANNOUNCEMENT.md", "DO NOT PUBLISH", "READY TO PUBLISH"),
                 "DRAFT banner")
    def strip_iso_url(root):
        # The draft mentions the placeholder in the email body AND in the
        # pre-send checklist (intentional). Remove EVERY occurrence.
        f = root / "docs/DISTROWATCH.md"
        t = read(f)
        assert "{{DIRECT_ISO_URL}}" in t
        f.write_text(t.replace("{{DIRECT_ISO_URL}}", "a download page"),
                     encoding="utf-8")

    _expect_fail("DistroWatch direct ISO link removed", src,
                 strip_iso_url, "{{DIRECT_ISO_URL}}")
    def strip_verify_tag(root):
        # The guide mentions --verify-tag in both prose and the gh command.
        f = root / "docs/RELEASE_GUIDE.md"
        t = read(f)
        assert "--verify-tag" in t
        f.write_text(t.replace("--verify-tag", "--generate-notes"),
                     encoding="utf-8")

    _expect_fail("release guide lost --verify-tag", src,
                 strip_verify_tag, "--verify-tag")
    _expect_fail("welcome link URL drift (RISK-050)", src,
                 edit("config/tools/links.conf",
                      "https://github.com/ar0x1/ar0xOS/issues",
                      "http://example.invalid/issues"), "AR0X_URL_ISSUES")

    # --- REAL mock release artifact-set assembly ----------------------------
    tmp = Path(tempfile.mkdtemp(prefix="ar0x-p12-artifacts-"))
    try:
        for name in ARTIFACT_SET:
            (tmp / name).write_text("mock " + name + "\n", encoding="utf-8")
        names = [p.name for p in tmp.iterdir() if p.is_file()]
        assert check_artifact_set(names), "complete 6-artifact set REJECTED"
        (tmp / "SHA256SUMS.sig").unlink()
        assert not check_artifact_set([p.name for p in tmp.iterdir() if p.is_file()]), \
            "artifact set ACCEPTED a missing detached signature"
        (tmp / "SHA256SUMS.sig").write_text("restored\n", encoding="utf-8")
        (tmp / "EXTRA.txt").write_text("unexpected\n", encoding="utf-8")
        assert not check_artifact_set([p.name for p in tmp.iterdir() if p.is_file()]), \
            "artifact set ACCEPTED an extra file"
        ok("artifact-set gate: complete set ACCEPTED; missing .sig and extra file REJECTED")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("[ OK ] Phase 12 offline self-test PASSED")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("usage: ar0x_release.py <SOURCE_ROOT> [--self-test]\n")
        sys.exit(2)
    try:
        if "--self-test" in sys.argv:
            sys.exit(self_test(Path(sys.argv[1])))
        sys.exit(run_checks(Path(sys.argv[1])))
    except (AssertionError, OSError, ValueError) as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        sys.exit(1)
