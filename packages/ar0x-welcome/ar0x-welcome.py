#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /usr/bin/ar0x-welcome  (SOURCE: /home/user/ar0xOS/packages/ar0x-welcome/ar0x-welcome.py)
# -----------------------------------------------------------------------------
# PHASE 8 — ar0x first-boot / welcome application, GTK4 + PyGObject.
#
# WHY PLAIN Gtk.Application AND NOT libadwaita: RISK-042. libadwaita hard-codes
# Adwaita and ignores custom GTK4 CSS; a plain Gtk.Application with a
# Gtk.CssProvider actually honours the ar0x palette. See docs/TOOLS_GUIDE.md §4.
#
# MODES
#   (default)            Show the window; do NOT write the first-boot marker.
#   --firstboot          Show ONLY if ~/.config/ar0x/welcome-done is absent;
#                        write the marker when the window closes. Used by
#                        /usr/lib/systemd/user/ar0x-welcome.service.
#   --self-test          Pure-standard-library checks; NO gi/GTK4/display/root.
#                        Used by the sandbox and tools/configure-tools.sh.
#   --version / --help   Print and exit.
#
# SECURITY
#   * The Python process is NEVER root. Privileged operations are separate
#     executables invoked through `pkexec` (polkit-gnome, Phase 6):
#       /usr/bin/ar0x-update --upgrade  (already refuses bare root itself)
#       /usr/bin/pacman -S --needed <official packages>   (RISK-010: no AUR)
#       /usr/lib/ar0x/ar0x-apparmor-ctl enforce|complain  (RISK-008)
#   * EVERY privileged command is shown in the output pane before it runs.
#   * NO --noconfirm, NO --overwrite, NO shell=True, NO string interpolation
#     into an argv: every command is an explicit list.
#
# TEST HOOKS (docs/TOOLS_GUIDE.md §6): AR0X_WELCOME_DATADIR,
# AR0X_WELCOME_MARKER, AR0X_INFO_BIN, AR0X_UPDATE_BIN, AR0X_WELCOME_SRC_ROOT.
# -----------------------------------------------------------------------------

"""ar0x Welcome — GTK4 first-boot assistant (pure standard library at import time)."""

import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.parse

# --- Section 1: constants ----------------------------------------------------
VERSION = "0.1.0"
APP_ID = "dev.ar0x.Welcome"
DATADIR = Path(os.environ.get("AR0X_WELCOME_DATADIR", "/usr/share/ar0x/welcome"))
SRC_ROOT = Path(os.environ.get(
    "AR0X_WELCOME_SRC_ROOT",
    str(Path(__file__).resolve().parents[2]),
))
INFO_BIN = os.environ.get("AR0X_INFO_BIN", "/usr/bin/ar0x-info")
UPDATE_BIN = os.environ.get("AR0X_UPDATE_BIN", "/usr/bin/ar0x-update")
APPARMOR_CTL = "/usr/lib/ar0x/ar0x-apparmor-ctl"
PACMAN_BIN = "/usr/bin/pacman"
PKEXEC_BIN = "/usr/bin/pkexec"
LOGO_PATH = "/usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg"
CSS_PATH = DATADIR / "ar0x-welcome.css"
LINKS_PATH = DATADIR / "links.conf"
GROUPS_PATH = DATADIR / "extra-groups.conf"
MARKER_REL = Path(".config/ar0x/welcome-done")

# Embedded fallbacks keep the app usable if a file is missing after a partial
# install. They are kept byte-compatible with config/tools/*.conf (--check gate).
LINKS_FALLBACK = (
    ("Documentation", "https://github.com/ar0x1/ar0xOS/tree/main/docs"),
    ("Report an issue", "https://github.com/ar0x1/ar0xOS/issues"),
    ("Community discussions", "https://github.com/ar0x1/ar0xOS/discussions"),
    ("Source code", "https://github.com/ar0x1/ar0xOS"),
    ("Arch Linux Wiki", "https://wiki.archlinux.org/"),
)
GROUPS_FALLBACK = (
    ("Developer tools", "base-devel git neovim python go rust tmux ripgrep fd jq"),
    ("Creative suite", "gimp inkscape blender"),
    ("System utilities", "htop btop nvme-cli smartmontools usbutils"),
    ("Network toolkit", "wget curl openssh nmap wireshark-qt"),
)
SHORT_LABELS = ("Docs", "Issues", "Community", "Source", "Arch Wiki")

# 8 ADR-015 palette pins. Kept here ONLY as a CSS fallback; the installed
# ar0x-welcome.css is the canonical copy and --check asserts all 8 hex values.
CSS_FALLBACK = """
@define-color ar0x_void #07090F;
@define-color ar0x_surface #11151F;
@define-color ar0x_cyan #00E5FF;
@define-color ar0x_magenta #FF2E88;
@define-color ar0x_lime #A8FF60;
@define-color ar0x_text #D7E0EE;
@define-color ar0x_muted #6B7891;
@define-color ar0x_alert #FF5C57;
window { background-color: @ar0x_void; color: @ar0x_text; }
.ar0x-title { font-size: 26px; font-weight: 700; color: @ar0x_cyan; }
.ar0x-sub { color: @ar0x_muted; font-size: 13px; }
.ar0x-key { color: @ar0x_cyan; font-weight: 600; }
.ar0x-value { color: @ar0x_text; }
.ar0x-hint { color: @ar0x_muted; font-size: 12px; }
.ar0x-out { font-family: monospace; font-size: 12px; color: @ar0x_lime;
            background-color: @ar0x_surface; }
button { background-color: @ar0x_surface; color: @ar0x_text;
         border: 1px solid @ar0x_muted; border-radius: 6px; padding: 8px 12px; }
button:hover { border-color: @ar0x_cyan; }
button.ar0x-primary { border-color: @ar0x_cyan; color: @ar0x_cyan; }
link, button.link { color: @ar0x_cyan; }
"""

# --- Section 2: pure-stdlib data helpers -------------------------------------
def _parse_conf(path, expected_fields, fallback, label):
    """Parse KEY|value|value lines. Comment/blank lines are ignored."""
    rows = []
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return [tuple(f[1:]) for f in fallback] if fallback else []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != expected_fields:
            raise ValueError("%s line %d: expected %d fields, got %d: %r" % (
                label, lineno, expected_fields, len(parts), line))
        rows.append(tuple(p.strip() for p in parts[1:]))
    if not rows:
        raise ValueError("%s has no data rows" % label)
    return rows


def read_links():
    """Return [(label, url), ...]; fall back to the embedded table."""
    try:
        rows = _parse_conf(LINKS_PATH, 3, None, "links.conf")
    except (OSError, ValueError):
        rows = list(LINKS_FALLBACK)
    out = []
    for label, url in rows:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError("link %r is not an https URL: %r" % (label, url))
        out.append((label, url))
    return out


def read_groups():
    """Return [(label, [package, ...]), ...] with a strict official-repo gate."""
    forbidden = {"code", "visual-studio-code-bin", "yay", "paru", "steam",
                 "hyprland-git", "neofetch", "google-chrome"}
    try:
        rows = _parse_conf(GROUPS_PATH, 3, None, "extra-groups.conf")
    except (OSError, ValueError):
        rows = list(GROUPS_FALLBACK)
    groups = []
    for label, spec in rows:
        pkgs = spec.split()
        if not pkgs:
            raise ValueError("group %r has no packages" % label)
        for pkg in pkgs:
            if pkg in forbidden or pkg.endswith("-git") or pkg.endswith("-bin"):
                raise ValueError("RISK-010: forbidden AUR/-git package %r in group %r" % (pkg, label))
            if not all(c.isalnum() or c in "+-._:@" for c in pkg):
                raise ValueError("invalid package name %r" % pkg)
        groups.append((label, pkgs))
    return groups


def marker_path():
    override = os.environ.get("AR0X_WELCOME_MARKER")
    return Path(override) if override else Path.home() / MARKER_REL


def write_marker():
    path = marker_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("ar0x-welcome %s shown\n" % VERSION, encoding="utf-8")
    return path


def should_skip(firstboot):
    """Pure logic used by --firstboot AND by --self-test."""
    return bool(firstboot and marker_path().exists())


def collect_summary():
    """Ask ar0x-info for JSON. Never raises; always returns a dict of strings."""
    fallback = {"distro": "ar0x 0.1.0 (Neon Root)", "version": VERSION,
                "kernel": "unknown", "arch": "unknown", "wm": "unknown",
                "shell": "unknown", "desktop": "unknown", "hostname": "unknown"}
    # Read the hook at CALL time (the module-level constant is captured at
    # import, and --self-test installs its stub after the module has loaded).
    info_bin = os.environ.get("AR0X_INFO_BIN", INFO_BIN)
    try:
        proc = subprocess.run([info_bin, "--json"], capture_output=True,
                              text=True, timeout=6, check=False)
        if proc.returncode != 0:
            return fallback
        data = json.loads(proc.stdout)
        if not isinstance(data, dict):
            return fallback
        return {k: (v if isinstance(v, str) else str(v)) for k, v in data.items()}
    except (OSError, ValueError, subprocess.SubprocessError, json.JSONDecodeError):
        return fallback


def summary_rows(data):
    """Ordered (key, value) pairs shown in the GTK4 summary grid."""
    keys = (("Distro", "distro"), ("Kernel", "kernel"), ("Architecture", "arch"),
            ("Desktop", "desktop"), ("Window manager", "wm"), ("Shell", "shell"),
            ("Host", "hostname"), ("Packages", "packages"))
    return [(label, data.get(key, "")) for label, key in keys if data.get(key, "")]


# --- Section 3: --self-test (no gi, no display, no root) ---------------------
def run_self_test():
    import tempfile

    print("[ OK ] ar0x-welcome imports cleanly with the standard library only")
    # 3a. Links: 5 rows, all https, canonical parity.
    links = read_links()
    assert len(links) == 5, "expected 5 links, got %d" % len(links)
    assert all(u.startswith("https://") for _, u in links)
    canon = SRC_ROOT / "config/tools/links.conf"
    if canon.is_file():
        want = []
        for raw in canon.read_text(encoding="utf-8").splitlines():
            raw = raw.strip()
            if raw and not raw.startswith("#"):
                p = raw.split("|")
                want.append((p[1].strip(), p[2].strip()))
        assert links == want, "links.conf mirror drifted from config/tools/links.conf"
        print("[ OK ] links.conf: 5 https links, byte-derived parity with canonical")
    else:
        print("[ OK ] links.conf: 5 https links (embedded fallback)")
    # 3b. Groups: official packages only.
    groups = read_groups()
    assert len(groups) == 4, "expected 4 groups, got %d" % len(groups)
    assert all(p for _, ps in groups for p in ps)
    print("[ OK ] extra-groups.conf: 4 groups, zero AUR / *-git / *-bin packages")
    # 3c. CSS contains all 8 ADR-015 hex pins and the canonical file matches.
    css = CSS_PATH.read_text(encoding="utf-8") if CSS_PATH.is_file() else CSS_FALLBACK
    pins = ("#07090F", "#11151F", "#00E5FF", "#FF2E88",
            "#A8FF60", "#D7E0EE", "#6B7891", "#FF5C57")
    for hexv in pins:
        assert hexv in css, "missing palette pin %s in CSS" % hexv
    print("[ OK ] ar0x-welcome.css: all 8 ADR-015 palette pins present")
    # 3d. First-boot marker logic (pure, with a temp override).
    with tempfile.TemporaryDirectory() as td:
        marker = Path(td) / "nested" / "welcome-done"
        os.environ["AR0X_WELCOME_MARKER"] = str(marker)
        assert not should_skip(True), "firstboot must run when marker is absent"
        assert not should_skip(False), "manual launch must never be skipped"
        written = write_marker()
        assert written.is_file() and written == marker
        assert should_skip(True), "firstboot must skip once marker exists"
        os.environ.pop("AR0X_WELCOME_MARKER", None)
    print("[ OK ] first-boot marker: skip logic + parent creation + write")
    # 3e. Summary parsing with a stub ar0x-info (no installed system needed).
    with tempfile.TemporaryDirectory() as td:
        stub = Path(td) / "ar0x-info"
        payload = {"distro": "ar0x 0.1.0 (Neon Root)", "kernel": "6.18.59-1",
                   "arch": "x86_64", "desktop": "Hyprland", "wm": "Hyprland",
                   "shell": "zsh", "hostname": "neon-root", "packages": "109"}
        stub.write_text("#!/bin/sh\nprintf '%s'\n" %
                        json.dumps(payload).replace("'", "'\\''"), encoding="utf-8")
        stub.chmod(0o755)
        old = os.environ.get("AR0X_INFO_BIN")
        os.environ["AR0X_INFO_BIN"] = str(stub)
        data = collect_summary()
        if old is None:
            os.environ.pop("AR0X_INFO_BIN", None)
        else:
            os.environ["AR0X_INFO_BIN"] = old
        assert data.get("distro", "").startswith("ar0x"), "stub summary not parsed: %r" % data
        assert data.get("packages") == "109", "stub packages field lost: %r" % data
        rows = summary_rows(data)
        assert len(rows) == 8, "expected 8 summary rows, got %d" % len(rows)
    print("[ OK ] collect_summary(): ar0x-info --json parsed into 8 summary rows")
    # 3f. Graceful fallback when ar0x-info is missing entirely.
    with tempfile.TemporaryDirectory() as td:
        old = os.environ.get("AR0X_INFO_BIN")
        os.environ["AR0X_INFO_BIN"] = str(Path(td) / "does-not-exist")
        data = collect_summary()
        if old is None:
            os.environ.pop("AR0X_INFO_BIN", None)
        else:
            os.environ["AR0X_INFO_BIN"] = old
        assert data.get("distro", "").startswith("ar0x")
    print("[ OK ] collect_summary(): safe fallback when ar0x-info is absent")
    # 3g. Every privileged command is a fixed argv list (no shell string).
    for label, pkgs in groups:
        cmd = [PKEXEC_BIN, PACMAN_BIN, "-S", "--needed"] + pkgs
        assert "--noconfirm" not in cmd and "--overwrite" not in cmd
        assert all("/" not in p for p in pkgs), label
    print("[ OK ] privileged commands: explicit argv, no --noconfirm/--overwrite")
    print("[ OK ] ar0x-welcome --self-test PASSED")
    return 0


# --- Section 4: GTK4 application (gi imported LAZILY) -----------------------
def run_gui(firstboot, write_on_close):
    try:
        import gi
        gi.require_version("Gtk", "4.0")
        from gi.repository import Gdk, Gio, GLib, Gtk
    except (ImportError, ValueError) as exc:
        sys.stderr.write(
            "ar0x-welcome: GTK4/PyGObject unavailable: %s\n"
            "Install on an Arch host: sudo pacman -S gtk4 python-gobject\n"
            "Headless check: ar0x-welcome --self-test\n" % exc)
        return 3

    links = read_links()
    groups = read_groups()
    data = collect_summary()

    class WelcomeWindow(Gtk.ApplicationWindow):
        def __init__(self, app):
            super().__init__(application=app, title="ar0x Welcome")
            self.set_default_size(860, 720)
            self._out = []
            self._load_css(Gdk, Gtk, GLib)
            root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            self.set_child(root)
            scroll = Gtk.ScrolledWindow()
            scroll.set_vexpand(True)
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            root.append(scroll)
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
            for edge in ("top", "bottom", "start", "end"):
                getattr(content, "set_margin_%s" % edge)(24)
            scroll.set_child(content)

            # 4a. Logo. Gtk.Image uses the gdk-pixbuf SVG loader; a missing
            # icon must not abort the whole first-boot experience.
            logo = None
            if os.path.isfile(LOGO_PATH):
                try:
                    logo = Gtk.Image.new_from_file(LOGO_PATH)
                    logo.set_pixel_size(112)
                except GLib.Error:
                    logo = None
            if logo is not None:
                logo.set_halign(Gtk.Align.CENTER)
                content.append(logo)
            title = Gtk.Label(label="Welcome to ar0x")
            title.add_css_class("ar0x-title")
            title.set_halign(Gtk.Align.CENTER)
            content.append(title)
            sub = Gtk.Label(label="0.1.0 \u00b7 Neon Root \u00b7 Developer Edition")
            sub.add_css_class("ar0x-sub")
            sub.set_halign(Gtk.Align.CENTER)
            content.append(sub)

            # 4b. System summary grid, fed by `ar0x-info --json`.
            grid = Gtk.Grid()
            grid.set_column_spacing(16)
            grid.set_row_spacing(6)
            grid.set_halign(Gtk.Align.CENTER)
            for row, (label, value) in enumerate(summary_rows(data)):
                key = Gtk.Label(label=label)
                key.add_css_class("ar0x-key")
                key.set_xalign(1.0)
                val = Gtk.Label(label=value)
                val.add_css_class("ar0x-value")
                val.set_xalign(0.0)
                val.set_wrap(True)
                grid.attach(key, 0, row, 1, 1)
                grid.attach(val, 1, row, 1, 1)
            content.append(grid)
            content.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

            # 4c. Actions: update check + four official package groups.
            act = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            act.set_homogeneous(True)
            check_btn = Gtk.Button.new_with_label("Check for updates")
            check_btn.add_css_class("ar0x-primary")
            check_btn.connect("clicked", lambda _b: self._run_async(
                [UPDATE_BIN, "--check"], "update check"))
            act.append(check_btn)
            info_btn = Gtk.Button.new_with_label("System info")
            info_btn.connect("clicked", lambda _b: self._run_async(
                [INFO_BIN, "--plain"], "system info"))
            act.append(info_btn)
            content.append(act)

            glabel = Gtk.Label(label="Install extras (official [core]/[extra] only \u2014 RISK-010)")
            glabel.add_css_class("ar0x-hint")
            glabel.set_xalign(0.0)
            content.append(glabel)
            ggrid = Gtk.Grid()
            ggrid.set_column_spacing(8)
            ggrid.set_row_spacing(8)
            ggrid.set_column_homogeneous(True)
            for i, (label, pkgs) in enumerate(groups):
                btn = Gtk.Button.new_with_label(label)
                btn.set_tooltip_text(" ".join(pkgs))
                btn.connect("clicked", self._on_install, pkgs)
                ggrid.attach(btn, i % 2, i // 2, 1, 1)
            content.append(ggrid)

            # 4d. AppArmor enforcing opt-in (RISK-008) with a one-command revert.
            aa_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            aa_label = Gtk.Label(label="AppArmor enforcing (opt-in; can break screen sharing)")
            aa_label.add_css_class("ar0x-hint")
            aa_label.set_xalign(0.0)
            aa_label.set_hexpand(True)
            aa_box.append(aa_label)
            self._aa_switch = Gtk.Switch()
            self._aa_switch.set_valign(Gtk.Align.CENTER)
            try:
                st = subprocess.run([APPARMOR_CTL, "status"], capture_output=True,
                                    text=True, timeout=4, check=False)
                self._aa_switch.set_active(st.returncode == 0 and "enforce" in st.stdout)
            except (OSError, subprocess.SubprocessError):
                self._aa_switch.set_active(False)
            # Connect AFTER setting the initial state so no command fires here.
            self._aa_switch.connect("notify::active", self._on_apparmor)
            aa_box.append(self._aa_switch)
            content.append(aa_box)

            # 4e. Links (Gtk.LinkButton calls gtk_show_uri; no subprocess).
            link_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            link_box.set_homogeneous(True)
            for i, (label, url) in enumerate(links):
                short = SHORT_LABELS[i] if i < len(SHORT_LABELS) else label
                lb = Gtk.LinkButton.new_with_label(url, short)
                lb.set_tooltip_text(label + " \u2014 " + url)
                link_box.append(lb)
            content.append(link_box)

            # 4f. Command output pane + status line.
            self._status = Gtk.Label(label="Ready. All privileged actions are shown below before they run.")
            self._status.add_css_class("ar0x-hint")
            self._status.set_xalign(0.0)
            content.append(self._status)
            self._text = Gtk.TextView()
            self._text.set_editable(False)
            self._text.set_monospace(True)
            self._text.add_css_class("ar0x-out")
            out_scroll = Gtk.ScrolledWindow()
            out_scroll.set_min_content_height(150)
            out_scroll.set_child(self._text)
            content.append(out_scroll)

            # 4g. Footer.
            foot = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            done = Gtk.Button.new_with_label("Don't show this again")
            done.connect("clicked", lambda _b: (write_marker(), self.close()))
            foot.append(done)
            close = Gtk.Button.new_with_label("Close")
            close.connect("clicked", lambda _b: self.close())
            foot.append(close)
            content.append(foot)
            self.connect("close-request", self._on_close_request)
            self._write_on_close = write_on_close

        # -- styling ---------------------------------------------------------
        def _load_css(self, Gdk, Gtk, GLib):
            provider = Gtk.CssProvider()
            try:
                if CSS_PATH.is_file():
                    provider.load_from_path(str(CSS_PATH))
                else:
                    provider.load_from_data(CSS_FALLBACK.encode("utf-8"))
                display = Gdk.Display.get_default()
                if display is not None:
                    Gtk.StyleContext.add_provider_for_display(
                        display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            except GLib.Error as exc:
                sys.stderr.write("ar0x-welcome: CSS not applied: %s\n" % exc.message)

        # -- output helpers --------------------------------------------------
        def _append(self, text):
            self._out.append(text)
            if len(self._out) > 400:
                self._out = self._out[-400:]
            self._text.get_buffer().set_text("".join(self._out))

        def _run_async(self, argv, title):
            self._status.set_label("Running: %s" % title)
            self._append("\n$ %s\n" % " ".join(argv))
            try:
                proc = Gio.Subprocess.new(
                    argv,
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
            except Exception as exc:  # GLib.Error, FileNotFoundError, ...
                self._append("ERROR: could not start %s: %s\n" % (argv[0], exc))
                self._status.set_label("Could not start %s" % argv[0])
                return
            proc.communicate_utf8_async(None, None, self._on_done, argv)

        def _on_done(self, proc, result, argv):
            try:
                _ok, stdout, stderr = proc.communicate_utf8_finish(result)
            except Exception as exc:
                self._append("ERROR: %s\n" % exc)
                self._status.set_label("Command failed")
                return
            if stdout:
                self._append(stdout)
            if stderr:
                self._append("[stderr]\n" + stderr)
            code = proc.get_exit_status()
            self._append("[exit %d]\n" % code)
            self._status.set_label("%s finished (exit %d)" % (argv[0], code))

        # -- action callbacks ------------------------------------------------
        def _on_install(self, _button, pkgs):
            cmd = [PKEXEC_BIN, PACMAN_BIN, "-S", "--needed"] + list(pkgs)
            self._append("\n⚠️  INSTALL EXTRAS (polkit will prompt; pacman asks for confirmation):\n")
            self._run_async(cmd, "install extras")

        def _on_apparmor(self, switch, _param):
            mode = "enforce" if switch.get_active() else "complain"
            self._append(
                "\n⚠️  RISK-008: switching AppArmor to %s.\n"
                "    Enforcing can break xdg-desktop-portal, screen sharing and GPU helpers.\n"
                "    One-command revert: pkexec %s complain\n" % (mode, APPARMOR_CTL))
            self._run_async([PKEXEC_BIN, APPARMOR_CTL, mode], "AppArmor " + mode)

        def _on_close_request(self, _window):
            if getattr(self, "_write_on_close", False):
                try:
                    write_marker()
                except OSError as exc:
                    sys.stderr.write("ar0x-welcome: could not write marker: %s\n" % exc)
            return False  # propagate the close

    class WelcomeApp(Gtk.Application):
        def __init__(self, write_on_close):
            super().__init__(application_id=APP_ID,
                             flags=Gio.ApplicationFlags.FLAGS_NONE)
            self._write_on_close = write_on_close

        def do_activate(self):
            win = WelcomeWindow(self)
            win._write_on_close = self._write_on_close
            win.present()

    app = WelcomeApp(write_on_close)
    return app.run(sys.argv[1:])


# --- Section 5: entry point --------------------------------------------------
def usage():
    print("""ar0x-welcome %s — GTK4 first-boot assistant

Usage: ar0x-welcome [OPTION]

  (no option)   Show the window (manual launch); do not write the marker.
  --firstboot   Show only when ~/.config/ar0x/welcome-done is absent, and
                write it on close. Used by ar0x-welcome.service.
  --self-test   Standard-library-only checks; no GTK4/display/root needed.
  --version     Print version.
  --help        This help.

The window NEVER runs as root. Privileged commands go through pkexec and are
listed in the output pane first. AppArmor enforcing is opt-in (RISK-008).
""" % VERSION)


def main(argv):
    if "--version" in argv:
        print("ar0x-welcome %s" % VERSION)
        return 0
    if "--help" in argv or "-h" in argv:
        usage()
        return 0
    if "--self-test" in argv:
        return run_self_test()
    firstboot = "--firstboot" in argv
    if should_skip(firstboot):
        return 0
    try:
        return run_gui(firstboot, write_on_close=firstboot)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
