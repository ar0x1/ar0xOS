# ar0x Custom Tools Guide — Phase 8 (COMPLETE)

**Distribution:** ar0x `0.1.0` "Neon Root" · Developer Edition
**Status:** ✅ COMPLETE — three tools, three buildable PKGBUILDs, `.desktop` files,
first-boot units, helpers, canonical configs, driver and offline self-tests.
**Depends on:** Phase 5 (pacman.conf split), Phase 6 (GTK4/Qt6/SDDM), Phase 7 (brand assets).
**Next:** Phase 9 — Package Repository (GPG key, `repo-add -s`, CI).

> ⚠️ **RISK-047 (HIGH):** no GTK4, no PyGObject, no display, no Wayland session,
> no QEMU/KVM and no root in this sandbox. **The ar0x-welcome WINDOW was NEVER
> rendered.** Every pure-Python path is covered by `--self-test`; the GTK4
> widget tree is structurally validated only.
> ⚠️ **RISK-048 (HIGH):** the signed `[ar0x]` repository does not exist until
> Phase 9. The three packages are **source + PKGBUILD**, NOT installed on the
> live ISO. `config/packages.x86_64` carries only their runtime dependencies.
> ⚠️ **RISK-049 (MEDIUM):** `makepkg`, `namcap`, `desktop-file-validate`,
> `systemd-analyze verify` and `shellcheck` are unavailable here. PKGBUILDs are
> syntax-checked, checksum-verified and structurally validated, but **NOT built**.
> ⚠️ **RISK-050 (LOW):** the five welcome hyperlinks are RESERVED endpoints;
> `/tree/main/docs` resolves only after the PR is merged (Phase 12 gate).

---

## 1. Deliverables (complete files, absolute installed paths)

### 1.1 `ar0x-info` — `/usr/bin/ar0x-info`

| Canonical source | Installed path |
|---|---|
| `/home/user/ar0xOS/packages/ar0x-info/ar0x-info` | `/usr/bin/ar0x-info` (`0755`) |
| `/home/user/ar0xOS/packages/ar0x-info/ar0x-info.desktop` | `/usr/share/applications/ar0x-info.desktop` |
| `/home/user/ar0xOS/packages/ar0x-info/fastfetch.jsonc` | `/usr/share/ar0x/info/fastfetch.jsonc` |
| `/home/user/ar0xOS/packages/ar0x-info/ar0x-ascii.txt` | `/usr/share/ar0x/info/ar0x-ascii.txt` |
| `/home/user/ar0xOS/packages/ar0x-info/ar0x-fastfetch.txt` | `/usr/share/ar0x/info/ar0x-fastfetch.txt` |
| `/home/user/ar0xOS/packages/ar0x-info/PKGBUILD` | builds `ar0x-info-0.1.0-1-any.pkg.tar.zst` |

| Mode | Behaviour |
|---|---|
| (default) | `fastfetch --config /usr/share/ar0x/info/fastfetch.jsonc` ; auto-falls back to `--plain` when fastfetch is absent |
| `--plain` | 8-line ASCII logo + key/value summary, **pure Bash**, no fastfetch/root/network/Python |
| `--json` | 17 UTF-8 string keys, no ANSI colours — consumed by `ar0x-welcome` |
| `--logo` | just the ASCII art |
| `--version` / `--help` / `--self-test` | metadata / help / 6 offline checks |
| `-- <ARGS>` | passed straight through to fastfetch |

`--json` keys: `distro id id_like version codename logo ansi_color kernel arch
hostname shell desktop session wm uptime_seconds packages generator`.
`/etc/os-release` is **parsed**, never sourced, so a malformed value cannot
execute code in this process. JSON escaping is done in Bash (no `jq`/`python`
dependency).

### 1.2 `ar0x-update` — `/usr/bin/ar0x-update`

| Canonical source | Installed path |
|---|---|
| `/home/user/ar0xOS/packages/ar0x-update/ar0x-update` | `/usr/bin/ar0x-update` (`0755`) |
| `/home/user/ar0xOS/packages/ar0x-update/ar0x-update.desktop` | `/usr/share/applications/ar0x-update.desktop` |
| `/home/user/ar0xOS/config/tools/update.conf` | `/etc/ar0x/update.conf` (`backup=()` → `.pacnew` on upgrade) |
| `/home/user/ar0xOS/packages/ar0x-update/PKGBUILD` | builds `ar0x-update-0.1.0-1-any.pkg.tar.zst` |

| Mode | Root? | Network? | Behaviour |
|---|---|---|---|
| `--check` (default) | **NO — refuses bare root** | yes | assert `[ar0x] SigLevel=Required`; isolated `pacman -Sy` verifies `ar0x.db.sig`; temporary-dbpath `-Qu` lists pending updates |
| `--verify-repo` | no | yes | only the isolated signature/metadata gate |
| `--rollback` | no | no | parse `/var/log/pacman.log` for old versions + cached tarballs |
| `--status` | no | no | effective config + binary capability map |
| `--upgrade` | ⚠️ via `pkexec` | yes | ONE `pacman -Syu`, interactive `yes` required |
| `--self-test` | no | no | 9 stubbed unit checks, no pacman/network |
| `--version` / `--help` | no | no | metadata |

`check_updates()` inlines the well-known `checkupdates` algorithm: a temporary
`--dbpath`, symlinked to the real `local` database, refreshed with
`fakeroot pacman -Sy`, then `pacman -Qu`. It **never touches
`/var/lib/pacman/sync`**, so it cannot create a partial-upgrade state.

### 1.3 `ar0x-welcome` — `/usr/bin/ar0x-welcome`

| Canonical source | Installed path |
|---|---|
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-welcome.py` | `/usr/bin/ar0x-welcome` (`0755`) |
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-welcome.desktop` | `/usr/share/applications/ar0x-welcome.desktop` |
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-welcome.css` | `/usr/share/ar0x/welcome/ar0x-welcome.css` |
| `/home/user/ar0xOS/config/tools/links.conf` | `/usr/share/ar0x/welcome/links.conf` |
| `/home/user/ar0xOS/config/tools/extra-groups.conf` | `/usr/share/ar0x/welcome/extra-groups.conf` |
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-welcome.service` | `/usr/lib/systemd/user/ar0x-welcome.service` |
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-firstboot.service` | `/usr/lib/systemd/system/ar0x-firstboot.service` |
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-firstboot` | `/usr/lib/ar0x/ar0x-firstboot` (`0755`) |
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-apparmor-ctl` | `/usr/lib/ar0x/ar0x-apparmor-ctl` (`0755`) |
| `/home/user/ar0xOS/packages/ar0x-welcome/ar0x-welcome.install` | pacman scriptlet (also copied to `/usr/share/doc/ar0x-welcome/`) |
| `/home/user/ar0xOS/packages/ar0x-welcome/PKGBUILD` | builds `ar0x-welcome-0.1.0-1-any.pkg.tar.zst` |

Window contents: logo, system summary from `ar0x-info --json`, **Check for
updates**, **System info**, four **Install extras** groups, an **AppArmor
enforcing** opt-in switch (RISK-008), five `Gtk.LinkButton`s, a read-only
command-output pane and a **Don't show this again** button.

`gi` is imported **lazily** inside `run_gui()`, so `--self-test` runs headless
on a CI box with no GTK4. If `gi` is missing on a real machine, the app prints
`sudo pacman -S gtk4 python-gobject` and exits 3 instead of crashing.

### 1.4 Canonical configs and driver

| Source | Purpose |
|---|---|
| `/home/user/ar0xOS/config/tools/links.conf` | 5 `KEY\|Label\|https://URL` links; parity with `AR0X_URL_*` in `config/versions.env` |
| `/home/user/ar0xOS/config/tools/extra-groups.conf` | 4 `KEY\|Label\|packages` groups; **official `[core]`/`[extra]` only**, RISK-010 |
| `/home/user/ar0xOS/config/tools/update.conf` | 9 `ar0x-update` options (see §4) |
| `/home/user/ar0xOS/tools/configure-tools.sh` | `--check` / `--sync` / `--self-test` / `--build` driver |
| `/home/user/ar0xOS/tools/lib/ar0x_pkgbuild.py` | pure-stdlib PKGBUILD/`.desktop`/systemd/parity validator |
| `/home/user/ar0xOS/config/packages.x86_64` | 112 packages; adds `python`, `python-gobject`, `fakeroot` as Phase 8 runtime deps |

---

## 2. Exact commands (copy-pasteable)

```bash
cd /home/user/ar0xOS

# 1. READ-ONLY validation (default). No root, no writes.
./tools/configure-tools.sh --check

# 2. Regenerate canonical mirrors + REAL SHA-256 sums + disposable test prefix.
./tools/configure-tools.sh --sync

# 3. Actually RUN all three tools offline (no root / network / GTK4).
./tools/configure-tools.sh --self-test

# 4. Whole-repo gates.
bash -n tools/*.sh tools/lib/*.sh packages/*/PKGBUILD
./tools/validate-versions.sh
./tools/bootstrap.sh --check
./tools/configure-branding.sh --check
./tools/configure-desktop.sh --check
./tools/configure-tools.sh --check

# 5. ⚠️ MANUAL, REAL ARCH HOST ONLY (root-capable, network, ~2 GiB free):
#    makepkg -s may INSTALL build deps via sudo/pacman. NO automatic rollback.
AR0X_CONFIRM_BUILD=yes ./tools/configure-tools.sh --build
```

Useful commands **inside the booted system** (after Phase 9/10):

```bash
ar0x-info                       # fastfetch with the branded config
ar0x-info --plain               # pure-Bash ASCII fallback (no fastfetch)
ar0x-info --json | jq .         # 17 keys for scripts
ar0x-update --status            # effective config, no network
ar0x-update --verify-repo       # ONLY the [ar0x] db.sig check
ar0x-update --check             # signed-metadata check + pending updates
ar0x-update --rollback          # old versions + cached tarballs
ar0x-welcome                    # manual launch (does NOT write the marker)
ar0x-welcome --firstboot        # skip when ~/.config/ar0x/welcome-done exists
ar0x-welcome --self-test        # headless pure-Python checks
systemctl --user status ar0x-welcome.service
systemctl status ar0x-firstboot.service
```

⚠️ **Do not** run `ar0x-update --upgrade` until you have read §5. It replaces
the kernel, glibc and GPU drivers and has no automatic rollback.

---

## 3. First-boot flow (exactly as shipped)

```
Calamares `finished` module (Phase 10, MANUAL wiring)
   │  enables ar0x-firstboot.service on the TARGET and regenerates /etc/machine-id
   ▼
/usr/lib/systemd/system/ar0x-firstboot.service
   ConditionFirstBoot=yes
   ConditionPathExists=!/var/lib/ar0x/firstboot-done
   ExecStart=/usr/lib/ar0x/ar0x-firstboot   (ROOT, oneshot, NO GUI)
        ├─ RISK-013 guard: FAIL if any NOPASSWD sudoers rule survived
        ├─ symlink /etc/systemd/user/graphical-session.target.wants/ar0x-welcome.service
        └─ write /var/lib/ar0x/firstboot-done
   ▼
/usr/lib/systemd/user/ar0x-welcome.service   (enabled by ar0x-welcome.install)
   WantedBy=graphical-session.target
   ExecCondition=/bin/sh -c 'test ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/ar0x/welcome-done"'
   ExecStart=/usr/bin/ar0x-welcome --firstboot
   ▼
GTK4 window (NORMAL USER, never root)
   ├─ logo + ar0x-info --json summary
   ├─ "Check for updates"   → /usr/bin/ar0x-update --check
   ├─ "Install extras"      → pkexec /usr/bin/pacman -S --needed <official pkgs>
   ├─ AppArmor switch       → pkexec /usr/lib/ar0x/ar0x-apparmor-ctl enforce|complain
   ├─ links                 → Gtk.LinkButton (gtk_show_uri, no subprocess)
   └─ on close              → writes ~/.config/ar0x/welcome-done
```

**Why TWO units:** a system unit cannot open a Wayland window; a user unit has
no `ConditionFirstBoot`. The system unit does the root-only arming, the user
unit owns the GUI. **Why NOT in `50-ar0x.preset`:** that preset is the single
owner of *live-ISO* system service state; enabling `ar0x-firstboot.service`
there would emit "unit not found" on the ISO because the package is not
installed until Phase 9/10.

---

## 4. Configuration tradeoffs (many options ⇒ explained)

### 4.1 `/etc/ar0x/update.conf` — every option

| Option | Default | Alternatives rejected | Tradeoff |
|---|---|---|---|
| `AR0X_UPDATE_REPO` | `ar0x` | `""` / all repos | A named repo lets us assert a **per-repo** `SigLevel`. Checking all repos would be weaker and noisier. |
| `AR0X_UPDATE_SIGLEVEL` | `Required` | `Never`, `Optional`, `TrustAll`, `DatabaseOptional` | `Never`/`Optional` accept unsigned or tampered metadata; `TrustAll` accepts any key. `Required` is the only value §9 permits. `--check` refuses anything else. |
| `AR0X_UPDATE_BACKEND` | `pkexec` | `sudo`, `none` | `pkexec` uses the graphical polkit agent (`polkit-gnome`, Phase 6) — correct on Wayland. `sudo` needs a TTY. `none` prints the exact command without running it (CI/review). |
| `AR0X_UPDATE_PACMAN_ARGS` | `-Syu` | `-Sy`, `-Syy`, `-S` | Arch forbids partial upgrades. `-Sy` alone desynchronises the db from installed packages. `--noconfirm`, `--overwrite`, `-d`, `--dbonly`, `--nodeps`, `--force` are **hard-rejected** by `assert_safe_pacman_args()`. |
| `AR0X_UPDATE_KEEP_CACHED` | `3` | `0`, `10` | `0` keeps every tarball (best rollback, unbounded disk). `3` is the v0.1 compromise; rollback can only reach versions still in `/var/cache/pacman/pkg/`. |
| `AR0X_UPDATE_ROLLBACK_LIMIT` | `20` | `5`, `all` | Bounds `--rollback` output. `all` makes the list unreadable after a year of updates. |
| `AR0X_UPDATE_CONFIRM` | `yes` | `no` | Requires an interactive `yes` even when `--yes` was given. `no` is for scripted CI on **disposable VMs only**. |
| `AR0X_UPDATE_SYNC_TIMEOUT` | `120` | `30`, `600` | 30 s breaks on slow mirrors; 600 s hangs a first-boot GUI. 120 s is the compromise (documented; enforced by the caller's own timeout). |
| `AR0X_UPDATE_REPO_FILTER` | `""` (all) | `core`, `extra` | Filtering hides pending updates from other repos, which is misleading. Left empty by default. |

The file is declared `backup=('etc/ar0x/update.conf')`, so `pacman -Syu` writes
`update.conf.pacnew` instead of clobbering a local edit.

### 4.2 UI / architecture decisions

| Decision | Chosen | Rejected / cost |
|---|---|---|
| GTK toolkit | plain `Gtk.Application` + `Gtk.CssProvider` | **libadwaita** hard-codes Adwaita and ignores custom GTK4 CSS (RISK-042). Cost: no `Adw.PreferencesWindow` polish. |
| `gi` import | lazy, inside `run_gui()` | top-level import would make `--self-test` fail on headless CI. Cost: one extra function boundary. |
| Privilege model | separate executables via `pkexec`, explicit argv | running the Python app as root, or `shell=True` strings. Cost: needs `polkit` + an agent. |
| Package extras | 4 fixed official-package groups | free-form entry (RISK-010: AUR/`-git`), `code`, `steam` (multilib disabled). Cost: less choice. |
| Update check | inlined `checkupdates` algorithm | `pacman -Sy` (partial upgrade), `pacman-contrib`'s `checkupdates` (extra runtime dep + `fakeroot` anyway). Cost: ~25 lines of Bash we own. |
| Links | external `links.conf` + `AR0X_URL_*` pins | hardcoded Python strings (two owners). Cost: one more mirror to keep in sync (`--check` enforces it). |
| First-boot marker | `~/.config/ar0x/welcome-done` | a global `/var/lib` flag (would show welcome for only ONE user), or `ConditionFirstBoot` on the user unit (not available). Cost: one dotfile. |
| `.install` scriptlet | direct `ln -sfn` into `graphical-session.target.wants` | `systemctl --global enable` needs a manager/D-Bus and fails inside a Calamares chroot. Cost: one unowned symlink. |
| 5 remaining packages | **deferred to Phase 9** | writing them now would duplicate `/etc/skel/**` paths already owned by the ISO overlay → `pacman: conflicting files`. Cost: `ar0x-meta` is not installable until Phase 9. |

---

## 5. ⚠️ Manual interventions (do NOT run in this sandbox)

1. **`ar0x-update --upgrade`** — ⚠️ ⚠️ replaces the kernel, glibc and GPU
   drivers, rewrites bootloader-relevant files, needs a working network and a
   backup. **There is NO automatic rollback.** The tool refuses bare root,
   prints a warning, demands an interactive `yes`, and lets `pacman` ask for its
   own confirmation. Revert path: `ar0x-update --rollback` → `sudo pacman -U
   /var/cache/pacman/pkg/<name>-<old>-x86_64.pkg.tar.zst`.
2. **`AR0X_CONFIRM_BUILD=yes ./tools/configure-tools.sh --build`** — ⚠️ needs a
   REAL Arch host, `base-devel`, network and ~2 GiB. `makepkg -s` may call
   `sudo pacman` to install build dependencies **on the host**. No automatic
   rollback. Output is unsigned and unpublished until Phase 9.
3. **`sudo ./tools/configure-tools.sh --build` is WRONG** — run as a normal
   user; `makepkg` refuses root itself.
4. **AppArmor enforcing** — ⚠️ RISK-008: can silently break
   `xdg-desktop-portal` screen sharing, screenshots and GPU helpers. Test those
   BEFORE toggling. One-command revert:
   `pkexec /usr/lib/ar0x/ar0x-apparmor-ctl complain`.
5. **Calamares `finished` wiring (Phase 10)** — must enable
   `ar0x-firstboot.service` on the TARGET and regenerate `/etc/machine-id`, or
   `ConditionFirstBoot=yes` will never fire. Also verify `removeuser` removed
   the live passwordless sudoers rule (RISK-013).
6. **Phase 9 GPG key + `repo-add -s` + CI** — until then, `[ar0x]` has no db and
   `pacman -S ar0x-meta` cannot work (acceptance criterion 7).
7. **Phase 12 link verification** — `curl -IL` all five `AR0X_URL_*` endpoints;
   `/tree/main/docs` resolves only after the PR is merged (RISK-050).
8. **GTK4 visual QA** — boot the ISO, launch `ar0x-welcome`, click every button,
   confirm the polkit agent appears, confirm the CSS palette renders (RISK-047).
9. **`shellcheck` / `namcap` / `desktop-file-validate` / `systemd-analyze verify`**
   — unavailable here; run all four on an Arch host before tagging v0.1.0.

---

## 6. Test hooks (documented, not hidden)

Every hook is read at **call time** so the offline self-tests can swap binaries
and data dirs without installing anything.

| Variable | Applies to | Default |
|---|---|---|
| `AR0X_INFO_DATADIR` | `ar0x-info` | `/usr/share/ar0x/info` |
| `AR0X_INFO_OS_RELEASE` | `ar0x-info` | `/etc/os-release` |
| `AR0X_UPDATE_CONF` | `ar0x-update` | `/etc/ar0x/update.conf` |
| `AR0X_UPDATE_PACMAN_CONF` | `ar0x-update` | `/etc/pacman.conf` |
| `AR0X_UPDATE_PACMAN_LOG` | `ar0x-update` | `/var/log/pacman.log` |
| `AR0X_UPDATE_CACHE_DIR` | `ar0x-update` | `/var/cache/pacman/pkg` |
| `AR0X_UPDATE_PACMAN_BIN` / `_FAKEROOT_BIN` / `_PACMANCONF_BIN` / `_CURL_BIN` | `ar0x-update` | `pacman` / `fakeroot` / `pacman-conf` / `curl` |
| `AR0X_WELCOME_DATADIR` | `ar0x-welcome` | `/usr/share/ar0x/welcome` |
| `AR0X_WELCOME_MARKER` | `ar0x-welcome` | `$HOME/.config/ar0x/welcome-done` |
| `AR0X_WELCOME_SRC_ROOT` | `ar0x-welcome --self-test` | repo root inferred from `__file__` |
| `AR0X_INFO_BIN` / `AR0X_UPDATE_BIN` | `ar0x-welcome` | `/usr/bin/ar0x-info` / `/usr/bin/ar0x-update` |
| `AR0X_CONFIRM_BUILD` | `configure-tools.sh --build` | unset (must be `yes`) |

`./tools/configure-tools.sh --sync` installs a disposable prefix at
`/home/user/ar0xOS/build/tools-prefix/` (`/build/` is gitignored). All three
tools are then runnable HERE with those hooks — this is how Phase 8 was tested.

---

## 7. Canonical → installed mapping (single-owner rule)

```
config/tools/links.conf ─────────► packages/ar0x-welcome/links.conf ────► /usr/share/ar0x/welcome/links.conf
config/tools/extra-groups.conf ──► packages/ar0x-welcome/extra-groups.conf ► /usr/share/ar0x/welcome/extra-groups.conf
config/tools/update.conf ────────► packages/ar0x-update/update.conf ─────► /etc/ar0x/update.conf  (backup=())
config/branding/ascii/ar0x-ascii.txt     ─► packages/ar0x-info/ar0x-ascii.txt     ─► /usr/share/ar0x/info/
config/branding/ascii/ar0x-fastfetch.txt ─► packages/ar0x-info/ar0x-fastfetch.txt ─► /usr/share/ar0x/info/
config/branding/fastfetch/config.jsonc ──► packages/ar0x-info/fastfetch.jsonc (DERIVED: header + logo.source ONLY)
packages/ar0x-*/PKGBUILD ───────────────► /usr/bin/ar0x-*, /usr/share/applications/*.desktop, /usr/lib/{systemd,ar0x}/**
```

`./tools/configure-tools.sh --sync` writes the mirrors and refreshes the real
SHA-256 sums; `--check` asserts 5 byte-identical pairs, 1 derivation-only
difference, and 18/18 checksums across the three PKGBUILDs.

> ⚠️ **File ownership (ADR-023):** `ar0x-welcome` deliberately does NOT own
> `/usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg`. It is installed by the
> Phase 7 overlay / Phase 9 `ar0x-wallpapers`. Owning it twice would produce
> `pacman: conflicting files` during a Calamares install.

---

## 8. Packaging: what is built and what is deferred

> **Phase 9 UPDATE (2026-11-07): RESOLVED.** This section is retained as the
> Phase 8 snapshot. ADR-024 "ONE OWNER PER PATH" has since written real
> PKGBUILDs for all FIVE packages below. The airootfs overlay keeps its 92
> ISO-owned paths; the packages install `/usr/share/ar0x/<pkg>/**` reference
> trees + `/usr/bin/ar0x-apply-*` helpers instead. All 8 PKGBUILDs now carry
> 57/57 SHA-256 sums and `validate_ownership()` proves `0/8` overlay paths.
> See `docs/REPO_GUIDE.md §1.4` — the guide for the CURRENT state.

| Package | Phase | Contents | Depends |
|---|---|---|---|
| `ar0x-info` | 8 ✅ | `/usr/bin/ar0x-info`, `.desktop`, `/usr/share/ar0x/info/**` | `bash coreutils grep gawk`; `fastfetch` optional |
| `ar0x-update` | 8 ✅ | `/usr/bin/ar0x-update`, `.desktop`, `/etc/ar0x/update.conf` | `bash coreutils pacman fakeroot polkit grep gawk` |
| `ar0x-welcome` | 8 ✅ | GTK4 app, `.desktop`, CSS, 2 tables, 2 units, 2 helpers, scriptlet | `python python-gobject gtk4 polkit apparmor hicolor-icon-theme ar0x-info ar0x-update` |
| `ar0x-theme` | 9 ✅ | `/usr/share/ar0x/theme/**` + `ar0x-apply-theme` | `bash coreutils` |
| `ar0x-wallpapers` | 9 ✅ | `/usr/share/ar0x/wallpapers/**` + `ar0x-apply-wallpapers` | `bash coreutils` |
| `ar0x-hypr-config` | 9 ✅ | `/usr/share/ar0x/hypr-config/**` (Lua-only) + `ar0x-apply-hypr-config` | `bash coreutils` |
| `ar0x-keyring` | 9 ✅ | `/usr/share/pacman/keyrings/ar0x*` + `--populate ar0x` | `pacman gnupg`; ⚠️ MANUAL keygen |
| `ar0x-meta` | 9 ✅ | `/usr/share/doc/ar0x-meta/RELEASE` | the other 7 |

**Why the Phase 8 deferral**: their sources already exist in
`config/desktop/**`, `config/branding/**` and `assets/**` and are installed into
the live ISO by the Phase 6/7 `--sync` chains. A second package owning the same
`/etc/skel/**` paths would break `pacman -U`. **Phase 9 resolution (ADR-024)**:
ONE OWNER PER PATH is recorded in `DECISIONS.md`; the five packages now own
`/usr/share/ar0x/<pkg>/**` instead, and the three `ar0x-apply-*` helpers copy
into one user's XDG directories with timestamped backups. 31 canonical mirrors
are byte-identical (`ar0x_repo.validate_mirrors()`).

All three shipped PKGBUILDs use `arch=('any')`, `pkgver=0.1.0`, `pkgrel=1`,
SPDX `GPL-3.0-or-later` for code (brand assets remain CC BY-SA 4.0 under
`/usr/share/ar0x/logo/LICENSE`), **local** `source=()` files with real SHA-256
`sha256sums`, and explicit `install -Dm` in `package()`. No network source, no
VCS source, no AUR (RISK-010).

---

## 9. Verification actually performed in the sandbox

```
bash -n tools/*.sh tools/lib/*.sh packages/*/PKGBUILD packages/*/*.install   → PASS
python3 AST parse (ar0x-welcome.py, ar0x_pkgbuild.py)                       → PASS
./tools/configure-tools.sh --check                                           → PASS
./tools/configure-tools.sh --sync                                            → PASS (18/18 SHA-256)
./tools/configure-tools.sh --self-test                                       → PASS
   ar0x-info --self-test   (6 checks), --json (jq/python), --plain
   ar0x-update --self-test (9 stubbed checks), --status
   ar0x-welcome --self-test (9 checks), --firstboot skip with marker
   ar0x-apparmor-ctl status → complain
./tools/validate-versions.sh                                                → PASS
./tools/bootstrap.sh --check / configure-branding.sh --check
./tools/configure-desktop.sh --check / configure-system.sh --check
./tools/build-kernel.sh --check / --self-test / setup-build-env.sh --check  → PASS
```

`ar0x_pkgbuild.py` verifies 18/18 real SHA-256 sums, 3 × `package()` installing
every source, 3 `.desktop` files (Type/Exec/Icon/Terminal/Categories), 2 systemd
units, 5 byte-identical mirrors, the derivation-only fastfetch config, 5 https
URLs vs `AR0X_URL_*`, 8 CSS hex pins vs `versions.env`, 4 groups / 23 packages
with zero AUR/`-git`/`-bin`, lazy `gi` import, zero `shell=True` calls, and zero
`ar0x-*` packages in `config/packages.x86_64`.

**NOT verified here (requires an Arch host / root / display):**
`makepkg`, `namcap`, `shellcheck`, `desktop-file-validate`,
`systemd-analyze verify`, `pacman -U`, `pacman -Syu`, `pkexec`, polkit agent,
`gtk-update-icon-cache`, real GTK4/welcome window, `fastfetch`, `screenfetch`,
QEMU UEFI/BIOS boot, Calamares `finished` wiring, `ConditionFirstBoot`,
WiFi/audio/GPU QA, live `curl -IL` of the 5 links.

---

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ar0x-update: Refusing to run as bare root` | by design (§9) | `runuser -u <user> -- ar0x-update --check` |
| `[ar0x] repository metadata signature check FAILED` | missing `ar0x.db.sig` / key not in pacman keyring | Phase 9: `repo-add -s` + install `ar0x-keyring`; do **not** lower `SigLevel` |
| `Insecure SigLevel` | someone set `Never`/`Optional`/`TrustAll` | restore `SigLevel = Required` in `/etc/pacman.conf` |
| `Cannot find the fakeroot binary` | `fakeroot` missing | `sudo pacman -S fakeroot` (already in `base-devel`) |
| `--check` prints nothing / hangs | mirror unreachable | check network; `ar0x-update --status`; `AR0X_UPDATE_SYNC_TIMEOUT` |
| `--rollback` says `(not in cache)` | `pacman -Sc` pruned the tarball | cannot downgrade that version; use the next fixed `-Syu` |
| welcome shows a blank/Adwaita window | CSS not loaded or libadwaita used | confirm `/usr/share/ar0x/welcome/ar0x-welcome.css`; `ar0x-welcome.py` must use `Gtk.Application` |
| `ModuleNotFoundError: No module named 'gi'` | `python-gobject` missing | `sudo pacman -S python-gobject gtk4`; `--self-test` still works headless |
| welcome opens on EVERY login | marker not written | check write permission on `~/.config/ar0x/`; `--firstboot` writes on close |
| welcome never opens at all | `ar0x-firstboot.service` not armed or `ConditionFirstBoot` false | Phase 10 Calamares `finished` + `machineid` module; then `systemctl --user status ar0x-welcome.service` |
| `ar0x-firstboot.service` FAILS with RISK-013 | passwordless sudoers rule survived install | fix Calamares `removeuser`/`finished`; never ship `NOPASSWD` on the target |
| `.desktop` icon missing | `ar0x-logo` icon not installed | install `ar0x-wallpapers` (Phase 9) or the Phase 7 overlay |
| AppArmor switch broke screen sharing | RISK-008 | `pkexec /usr/lib/ar0x/ar0x-apparmor-ctl complain` |
| `--check` says "stale mirror" | canonical edited without `--sync` | `./tools/configure-tools.sh --sync` |
| `makepkg` says checksum mismatch | source edited without refreshing sums | `./tools/configure-tools.sh --sync` rewrites all sums |

---

## 11. Risks

| ID | Level | Note |
|---|---|---|
| **RISK-008** | MEDIUM | AppArmor enforcing opt-in; one-command revert provided and tested structurally. |
| **RISK-010** | LOW | No AUR / `-git` / `-bin` packages anywhere in the ISO or the extras groups. |
| **RISK-013** | MEDIUM | `ar0x-firstboot` fails loudly if any `NOPASSWD` sudoers rule survives. |
| **RISK-020** | LOW | `makepkg -s` on missing makedepends; surfaced by Phase 9 clean-chroot CI. |
| **RISK-042** | MEDIUM | libadwaita ignored by design; plain GTK4 CSS used instead. |
| **RISK-047** | **HIGH** | GTK4 welcome window NEVER rendered here; structural + headless self-tests only. |
| **RISK-048** | **HIGH** | Signed `[ar0x]` db STILL does not exist after P9 tooling; all 8 packages are source-only, NOT on the ISO (MANUAL keygen → sign → publish). |
| **RISK-051** | **CRITICAL** | Offline private release key: `PENDING-KEYGEN`, PR workflows have ZERO secrets, `release.yml` has a fork guard. See `docs/REPO_GUIDE.md §5`. |
| **RISK-049** | MEDIUM | PKGBUILDs structurally validated and checksum-verified but NOT built with `makepkg`/`namcap`. |
| **RISK-050** | LOW | 5 reserved link endpoints; `/tree/main/docs` needs the PR merged (Phase 12). |

---

## 12. Companion documents

`/home/user/ar0xOS/PROJECT_PLAN.md` · `docs/architecture/BUILD_LAYOUT.md` ·
`docs/architecture/DECISIONS.md` (ADR-023, **ADR-024**) · `docs/REPO_GUIDE.md` ·
`docs/architecture/RISK_REGISTER.md` ·
`docs/architecture/DEPENDENCY_GRAPH.md` ·
`docs/architecture/COMPONENT_VERSIONS.md` · `docs/BRANDING_GUIDE.md` ·
`docs/DESKTOP_GUIDE.md` · `docs/SYSTEM_CONFIG.md` · `docs/KERNEL_BOOT.md`.
