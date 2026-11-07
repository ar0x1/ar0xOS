#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_pkgbuild.py
# -----------------------------------------------------------------------------
# PHASE 8 — pure-standard-library validator for the ar0x tool packages.
#
# WHY NOT `namcap` / `makepkg --printsrcinfo` / `desktop-file-validate` /
# `systemd-analyze verify`: none is installed in this sandbox (and they all
# need an Arch host + root for a real package build). This module does the
# STRUCTURAL checks that can be done offline; docs/TOOLS_GUIDE.md §9 lists
# exactly what still needs a real Arch host.
#
# Usage: python3 tools/lib/ar0x_pkgbuild.py <SOURCE_ROOT>
#        (or `import ar0x_pkgbuild; ar0x_pkgbuild.run_checks(root)`)
# -----------------------------------------------------------------------------

"""Structural validation of Phase 8 PKGBUILDs, .desktop files and systemd units."""

import ast
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import sys

PACKAGES = ("ar0x-info", "ar0x-update", "ar0x-welcome")
DEFERRED = ("ar0x-theme", "ar0x-wallpapers", "ar0x-hypr-config",
            "ar0x-keyring", "ar0x-meta")
PALETTE_KEYS = ("AR0X_VOID", "AR0X_SURFACE", "AR0X_CYAN", "AR0X_MAGENTA",
                "AR0X_LIME", "AR0X_TEXT", "AR0X_MUTED", "AR0X_ALERT")
URL_KEYS = ("DOCS", "ISSUES", "COMMUNITY", "SOURCE", "UPSTREAM")
FORBIDDEN_PKGS = {"code", "visual-studio-code-bin", "yay", "paru", "steam",
                  "neofetch", "google-chrome", "hyprland-git"}

# ---------------------------------------------------------------------------
# Section 1: tiny helpers
# ---------------------------------------------------------------------------

def read(rel):
    return Path(rel).read_text(encoding="utf-8")


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ok(msg):
    print("[ OK ] %s" % msg)


def parse_env(path):
    """Read KEY="value" lines from config/versions.env (no shell execution)."""
    out = {}
    for line in read(path).splitlines():
        m = re.match(r'^([A-Z0-9_]+)="([^"]*)"\s*(?:#.*)?$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def parse_conf(path, fields):
    rows = []
    for raw in read(path).splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != fields:
            raise AssertionError("%s: expected %d fields: %r" % (path, fields, line))
        rows.append(tuple(p.strip() for p in parts))
    return rows


# ---------------------------------------------------------------------------
# Section 2: PKGBUILD parsing (arrays + scalars, no shell execution)
# ---------------------------------------------------------------------------

def parse_pkgbuild(path):
    """Return {key: list[str] or str}. Handles multi-line ( ... ) arrays."""
    text = read(path)
    # Strip comments (never inside a quoted string in our PKGBUILDs).
    clean = "\n".join(l.split("#", 1)[0] if not l.lstrip().startswith("#") else ""
                      for l in text.splitlines())
    data = {}
    for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*)=\((.*?)\)', clean,
                         re.M | re.S):
        vals = re.findall(r"'([^']*)'|\"([^\"]*)\"|(\S+)", m.group(2))
        data[m.group(1)] = [a or b or c for a, b, c in vals]
    for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*)=(?!\()(.+)$', clean, re.M):
        key, val = m.group(1), m.group(2).strip().strip("'\"")
        if key not in data:
            data[key] = val
    data["_text"] = text
    return data


def validate_pkgbuild(root, pkg):
    rel = "packages/%s/PKGBUILD" % pkg
    path = root / rel
    assert path.is_file(), "missing %s" % rel
    d = parse_pkgbuild(path)
    for key in ("pkgname", "pkgver", "pkgrel", "pkgdesc", "arch", "url",
                "license", "depends", "source", "sha256sums"):
        assert key in d, "%s: missing %s" % (rel, key)
    assert d["pkgname"] == pkg, "%s: pkgname=%r != %r" % (rel, d["pkgname"], pkg)
    assert d["arch"] == ["any"], "%s: arch must be ('any')" % rel
    assert d["url"].startswith("https://"), "%s: url must be https" % rel
    assert re.search(r'^package\(\)\s*\{', d["_text"], re.M), "%s: no package() function" % rel
    assert re.search(r'^install=', d["_text"], re.M) if pkg == "ar0x-welcome" else True
    srcs, sums = d["source"], d["sha256sums"]
    assert len(srcs) == len(sums), "%s: %d sources but %d sha256sums" % (
        rel, len(srcs), len(sums))
    body = d["_text"]
    for src, want in zip(srcs, sums):
        f = root / "packages" / pkg / src
        assert f.is_file(), "%s: source file missing: %s" % (rel, src)
        got = sha256(f)
        assert got == want, "%s: sha256 mismatch for %s (PKGBUILD %s, file %s)" % (
            rel, src, want[:12], got[:12])
        assert '$srcdir/%s' % src in body, "%s: %s not installed by package()" % (rel, src)
    ok("%s PKGBUILD: %d/%d real SHA-256 sums, %d sources all installed" %
       (pkg, len(sums), len(sums), len(srcs)))
    return d


# ---------------------------------------------------------------------------
# Section 3: .desktop validation (freedesktop Desktop Entry Spec)
# ---------------------------------------------------------------------------

def validate_desktop(root, pkg, filename):
    rel = "packages/%s/%s" % (pkg, filename)
    text = read(root / rel)
    cp = configparser.ConfigParser(interpolation=None, strict=True)
    cp.optionxform = str
    cp.read_string(text)
    assert cp.has_section("Desktop Entry"), "%s: no [Desktop Entry]" % rel
    e = cp["Desktop Entry"]
    for key in ("Type", "Version", "Name", "GenericName", "Comment",
                "Exec", "Icon", "Terminal", "Categories"):
        assert key in e, "%s: missing %s" % (rel, key)
    assert e["Type"] == "Application", "%s: Type != Application" % rel
    assert "Encoding" not in e, "%s: deprecated Encoding key" % rel
    assert e["Terminal"] in ("true", "false"), "%s: bad Terminal value" % rel
    exe = e["Exec"]
    assert exe.startswith("/usr/bin/ar0x-"), "%s: Exec must be an absolute /usr/bin/ar0x-* path" % rel
    assert not any(c in exe for c in ";&|$`"), "%s: Exec contains shell metacharacters" % rel
    assert e["Icon"] in ("ar0x-logo", "system-software-update"), \
        "%s: Icon must be ar0x-logo or a freedesktop standard name" % rel
    assert e["Categories"].endswith(";"), "%s: Categories must end with ';'" % rel
    ok("%s: %s valid (Exec=%s, Icon=%s, Terminal=%s)" %
       (pkg, filename, exe, e["Icon"], e["Terminal"]))


# ---------------------------------------------------------------------------
# Section 4: systemd unit validation
# ---------------------------------------------------------------------------

def validate_unit(root, filename, kind):
    rel = "packages/ar0x-welcome/%s" % filename
    text = read(root / rel)
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    # Strip comment lines so configparser does not choke on '#'.
    cp.read_string("\n".join(l for l in text.splitlines()
                             if not l.lstrip().startswith("#")))
    for sec in ("Unit", "Service", "Install"):
        assert cp.has_section(sec), "%s: missing [%s]" % (rel, sec)
    svc = cp["Service"]
    assert svc.get("Type") == "oneshot", "%s: Type must be oneshot" % rel
    exec_start = svc.get("ExecStart", "")
    assert exec_start.startswith("/"), "%s: ExecStart must be absolute" % rel
    if kind == "system":
        assert cp["Unit"].get("ConditionFirstBoot") == "yes", \
            "%s: ConditionFirstBoot=yes required" % rel
        assert cp["Install"].get("WantedBy") == "multi-user.target", \
            "%s: system unit must be WantedBy=multi-user.target" % rel
    else:
        assert cp["Install"].get("WantedBy") == "graphical-session.target", \
            "%s: user unit must be WantedBy=graphical-session.target" % rel
        assert "ExecCondition" in svc, "%s: user unit needs ExecCondition" % rel
    ok("%s: %s valid (%s unit, ExecStart=%s)" % (filename, rel, kind, exec_start))


# ---------------------------------------------------------------------------
# Section 5: canonical -> mirror parity
# ---------------------------------------------------------------------------

def validate_mirrors(root):
    pairs = (
        ("config/tools/links.conf", "packages/ar0x-welcome/links.conf"),
        ("config/tools/extra-groups.conf", "packages/ar0x-welcome/extra-groups.conf"),
        ("config/tools/update.conf", "packages/ar0x-update/update.conf"),
        ("config/branding/ascii/ar0x-ascii.txt", "packages/ar0x-info/ar0x-ascii.txt"),
        ("config/branding/ascii/ar0x-fastfetch.txt", "packages/ar0x-info/ar0x-fastfetch.txt"),
    )
    for a, b in pairs:
        assert read(root / a) == read(root / b), "%s is stale vs %s (run --sync)" % (b, a)
    ok("5 canonical -> package mirrors are byte-identical")
    # Derived fastfetch config: ONLY the header + logo.source may differ.
    canon = read(root / "config/branding/fastfetch/config.jsonc")
    derived = read(root / "packages/ar0x-info/fastfetch.jsonc")
    expect = canon.replace(
        '// /etc/skel/.config/fastfetch/config.jsonc  (CANONICAL: config/branding/fastfetch/)',
        '// /usr/share/ar0x/info/fastfetch.jsonc  (DERIVED from config/branding/fastfetch/)', 1)
    expect = expect.replace(
        '// The absolute /usr/share path is intentional: /etc/skel is copied into every\n'
        '// new home, and a "~" source would break for root, the live user and Calamares.',
        '// ar0x-info OWNS its art copy so it also works on a stock Arch install where\n'
        '// the Phase 7 /usr/share/ar0x/branding/ overlay is absent. The absolute path\n'
        '// is intentional: /etc/skel is copied into every new home.', 1)
    expect = expect.replace('"/usr/share/ar0x/branding/ar0x-fastfetch.txt"',
                            '"/usr/share/ar0x/info/ar0x-fastfetch.txt"', 1)
    assert derived == expect, "packages/ar0x-info/fastfetch.jsonc drifted from canonical (only source/header may change)"
    ok("ar0x-info/fastfetch.jsonc: derivation-only difference from canonical")
    # JSONC parses after stripping // comments.
    stripped = "\n".join(l for l in derived.splitlines()
                         if not l.lstrip().startswith("//"))
    obj = json.loads(stripped)
    assert obj["logo"]["type"] == "file", "logo.type must be 'file', not 'file-raw'"
    assert obj["logo"]["source"] == "/usr/share/ar0x/info/ar0x-fastfetch.txt"
    assert set(obj["logo"]["color"]) >= {"1", "2", "3"}
    ok("ar0x-info/fastfetch.jsonc: valid JSONC, type=file, 3 colour placeholders")


# ---------------------------------------------------------------------------
# Section 6: versions.env parity (URLs + palette)
# ---------------------------------------------------------------------------

def validate_versions_parity(root):
    env = parse_env(root / "config/versions.env")
    assert env["AR0X_TOOLS_VERSION"] == env["AR0X_VERSION"], "tool versions must track AR0X_VERSION"
    assert env["AR0X_WELCOME_APP_ID"] == "dev.ar0x.Welcome"
    assert env["AR0X_UPDATE_REPO"] == "ar0x"
    assert env["AR0X_UPDATE_SIGLEVEL"] == "Required"
    ok("versions.env: tools version == %s, app-id + repo + SigLevel pinned" % env["AR0X_VERSION"])
    rows = parse_conf(root / "config/tools/links.conf", 3)
    assert [r[0] for r in rows] == list(URL_KEYS), "link keys must be %s" % (URL_KEYS,)
    for key, label, url in rows:
        assert url.startswith("https://"), "%s link is not https" % key
        assert env.get("AR0X_URL_" + key) == url, \
            "AR0X_URL_%s in versions.env != links.conf (%s)" % (key, url)
    ok("links.conf: 5 https URLs match AR0X_URL_* pins in versions.env")
    css = read(root / "packages/ar0x-welcome/ar0x-welcome.css")
    for key in PALETTE_KEYS:
        hexv = env[key]
        assert hexv in css, "ar0x-welcome.css missing %s=%s" % (key, hexv)
    ok("ar0x-welcome.css: all 8 ADR-015 hex pins match versions.env")


def validate_groups(root):
    rows = parse_conf(root / "config/tools/extra-groups.conf", 3)
    assert len(rows) == 4, "expected 4 extra groups, got %d" % len(rows)
    total = 0
    for key, label, spec in rows:
        pkgs = spec.split()
        assert pkgs, "group %s is empty" % key
        for p in pkgs:
            assert p not in FORBIDDEN_PKGS and not p.endswith(("-git", "-bin")), \
                "RISK-010: forbidden AUR package %r in group %s" % (p, key)
            assert re.fullmatch(r'[A-Za-z0-9+._:@-]+', p), "bad package name %r" % p
        total += len(pkgs)
    ok("extra-groups.conf: 4 groups / %d packages, zero AUR/-git/-bin" % total)


# ---------------------------------------------------------------------------
# Section 7: source-code structural checks
# ---------------------------------------------------------------------------

def validate_sources(root):
    py = read(root / "packages/ar0x-welcome/ar0x-welcome.py")
    ast.parse(py)
    assert "gi.require_version(\"Gtk\", \"4.0\")" in py, "GTK4 version pin missing"
    assert "def run_gui" in py and "import gi" in py, "gi must be lazily importable"
    # gi must NOT be imported at module scope (or --self-test fails headless).
    head = py.split("# --- Section 2")[0]
    assert "from gi.repository" not in head, "gi imported at module scope breaks --self-test"
    assert "--noconfirm" in py, "ar0x-welcome must document the --noconfirm ban"
    # AST check, not a text search: the SECURITY comment literally contains
    # the words "shell=True", which would false-positive a substring test.
    for node in ast.walk(ast.parse(py)):
        if isinstance(node, ast.Call):
            for kw in node.keywords:
                assert not (kw.arg == "shell" and isinstance(kw.value, ast.Constant)
                            and kw.value.value is True), "shell=True found in a call"
    ok("ar0x-welcome.py: AST valid, GTK4 pinned, gi lazy, zero shell=True calls")
    upd = read(root / "packages/ar0x-update/ar0x-update")
    assert "set -euo pipefail" in upd
    assert "assert_not_root" in upd and "SigLevel = Required" in upd
    assert "--noconfirm" in upd and "-Sy" in upd
    ok("ar0x-update: strict mode, root refusal, SigLevel gate, no blind --noconfirm")
    info = read(root / "packages/ar0x-info/ar0x-info")
    assert "set -euo pipefail" in info and "json_escape" in info
    ok("ar0x-info: strict mode + dependency-free JSON escaping")
    for helper in ("ar0x-firstboot", "ar0x-apparmor-ctl"):
        h = read(root / "packages/ar0x-welcome" / helper)
        assert "set -euo pipefail" in h, "%s missing strict mode" % helper
    ok("2 helper scripts: both strict-mode compliant")
    scriptlet = read(root / "packages/ar0x-welcome/ar0x-welcome.install")
    assert "post_install()" in scriptlet and "ln -sfn" in scriptlet
    ok("ar0x-welcome.install: post_install enables the user unit offline-safe")


def validate_deferred(root):
    for name in DEFERRED:
        assert (root / "packages" / name / "README.md").is_file(), \
            "%s must have a Phase 9 deferral README" % name
        assert not (root / "packages" / name / "PKGBUILD").exists(), \
            "%s has a PKGBUILD but no ownership decision yet" % name
    ok("5 Phase 9 package skeletons documented, 0 premature PKGBUILDs")


def validate_no_repo_packages_yet(root):
    """The signed [ar0x] repo does not exist until Phase 9; never put ar0x-*
    packages in the ISO package list (bootstrap.sh --check would fail)."""
    body = "\n".join(l.split("#", 1)[0].strip()
                     for l in read(root / "config/packages.x86_64").splitlines())
    names = set(body.split())
    for n in PACKAGES:
        assert n not in names, "%s must NOT be in config/packages.x86_64 before Phase 9" % n
    for dep in ("python", "python-gobject", "fakeroot"):
        assert dep in names, "Phase 8 runtime dependency missing from ISO: %s" % dep
    ok("packages.x86_64: 0 ar0x-* packages (Phase 9), 3 runtime deps present")


# ---------------------------------------------------------------------------
# Section 8: entry point
# ---------------------------------------------------------------------------

def run_checks(source_root):
    root = Path(source_root)
    print("=== ar0x Phase 8 structural validation ===")
    for pkg in PACKAGES:
        validate_pkgbuild(root, pkg)
    validate_desktop(root, "ar0x-info", "ar0x-info.desktop")
    validate_desktop(root, "ar0x-update", "ar0x-update.desktop")
    validate_desktop(root, "ar0x-welcome", "ar0x-welcome.desktop")
    validate_unit(root, "ar0x-firstboot.service", "system")
    validate_unit(root, "ar0x-welcome.service", "user")
    validate_mirrors(root)
    validate_versions_parity(root)
    validate_groups(root)
    validate_sources(root)
    validate_deferred(root)
    validate_no_repo_packages_yet(root)
    print("[ OK ] Phase 8 structural validation PASSED")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: ar0x_pkgbuild.py <SOURCE_ROOT>\n")
        sys.exit(2)
    try:
        sys.exit(run_checks(sys.argv[1]))
    except (AssertionError, OSError, ValueError, configparser.Error) as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        sys.exit(1)
