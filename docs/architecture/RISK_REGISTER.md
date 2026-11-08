# ar0x — Risk Register & ⚠️ Warnings

> Phase 1 companion to [`PROJECT_PLAN.md`](../../PROJECT_PLAN.md).
> Severity: **CRITICAL** (data loss / unbootable release) · **HIGH** (release blocked) ·
> **MEDIUM** (feature degraded) · **LOW** (cosmetic).
> Every ⚠️ item is restated at the top of the phase that touches it — never buried.

---

## 1. Risk table

| ID | Severity | Risk | Trigger | Mitigation | Owner / phase |
|---|---|---|---|---|---|
| **RISK-001** | ⚠️ **CRITICAL** | Custom kernel `.config` edits or out-of-tree patches produce an unbootable ISO | Phase 4 deviates from stock `linux-lts` | v0.1 uses the **unmodified signed Arch `linux-lts 6.18.59`**; `config/kernel/ar0x-lts.config` is a reference doc only; a known-good fallback kernel stays in the ISO; `build-kernel.sh` refuses to patch without `--i-accept-the-risk`; warn again at Phase 4 | You, P4 |
| **RISK-002** | **HIGH** | `hyprland.conf` shipped instead of `hyprland.lua` → blank/unconfigured session | Anyone copies a pre-0.57 guide | Hyprland 0.57 removed `.conf`; `tools/validate-versions.sh` **fails the build** if any `hyprland.conf` exists under `config/`, `archiso/`, `packages/`; Phase 6 uses Lua modules with keybinds loaded first | P1/P6 |
| **RISK-003** | **HIGH** | Calamares built from the archived GitHub mirror (`3.3.14`) → QML keyboard input broken on Wayland, `/boot` EFI bug | CI clones `github.com/calamares/calamares` | Pin **3.4.3 from Codeberg**, verify SHA256 `144cbbf…` + detached `.asc` with key `6D08 3784 … 56D6`; vendor the tarball; `setup-repo.sh` asserts the source URL | P9/P10 |
| **RISK-004** | ⚠️ **CRITICAL** | Calamares partitioning writes to the **wrong disk** → irreversible data loss | Manual install on a multi-disk host | Documented as **MANUAL INTERVENTION**; `INSTALLER_FLOW.md` requires printing `lsblk -o NAME,SIZE,MODEL,TRAN` and typing the target device before partitioning; test only on a disposable VM disk; never auto-select a device when >1 disk is present | You, P10/P11 |
| **RISK-005** | **HIGH** | Trimming `linux-firmware` to meet the 2 GB gate breaks WiFi/GPU on real hardware | Size budget exceeded → lever #1 applied | Keep `linux-firmware-whence` and a curated subset for Intel/AMD/Realtek/Atheros; ship the full firmware in the `[ar0x]` repo as `ar0x-firmware-extras`; Phase 11 checklist **must** include a real-hardware WiFi test | P11 |
| **RISK-006** | **MEDIUM** | Frozen `pacman.conf.build` accidentally shipped as `/etc/pacman.conf` → installed systems permanently pinned to 2026-11-01 | A single wrong `cp` in `bootstrap.sh` | Two distinct files with distinct names; `build-iso.sh` asserts installed conf contains `[ar0x]` and does **not** contain `archive.archlinux.org`; `bootstrap.sh` comments state the destination explicitly | P3/P11 |
| **RISK-007** | ⚠️ **HIGH** | Secure Boot MOK enrollment mishandled → soft-bricked machine / boot failure | User enrolls the wrong key or loses the MOK password | SB is **optional and not enforced** in v0.1; shim path documented but requires an explicit manual decision; firmware reset procedure documented in Phase 11 | You, P4/P11 |
| **RISK-008** | **MEDIUM** | AppArmor enforcing breaks xdg-desktop-portal → screen sharing / screenshots / GPU helpers fail | `aa-enforce` applied globally | v0.1 ships `complain`; enforcing is an opt-in in `ar0x-welcome` via `/usr/lib/ar0x/ar0x-apparmor-ctl enforce` (marker `/etc/apparmor/ar0x-enforce`); `--dry-run` lists targets with NO root; ONE-COMMAND REVERT `pkexec /usr/lib/ar0x/ar0x-apparmor-ctl complain`; test screen sharing before enabling | P5/P8 |
| **RISK-009** | **MEDIUM** | SDDM 0.21.0 X11 greeter fails on NVIDIA / Wayland-only setups | Proprietary NVIDIA driver + no XWayland | Include NVIDIA + SDDM in the Phase 11 GPU matrix; fallback to `greetd` + `gtkgreet` documented (v0.2); XWayland kept in the ISO | P6/P11 |
| **RISK-010** | **LOW** | Snapshot drift despite archive pin (AUR/git-sourced packages) | Any `*-git` or AUR package in `packages.x86_64` | No AUR packages in the base ISO; Calamares/Hyprland are HARD-pinned to exact tags with checksums; `packages.lock` records every installed version | P3 |
| **RISK-011** | **MEDIUM** | Signing key lost or leaked → `[ar0x]` updates blocked or compromised | Key stored in Git / on CI | `keys/` is mode `0700` and git-ignored; private key offline; CI uses a separate, limited repo-signing subkey; `ar0x-keyring` ships the public key; rotation procedure in Phase 9 | You, P9 |
| **RISK-012** | **MEDIUM** | ISO exceeds 2.2 GB gate after Calamares + firmware | Any package list growth | `build-iso.sh` fails the build with a per-directory size report; lever order fixed in PROJECT_PLAN.md §7; dropping Calamares requires your approval | P11 |
| **RISK-013** | **MEDIUM** | Live autologin / passwordless `ar0x` user leaks into the installed system | Calamares `removeuser` module misconfigured | `removeuser` module removes the live user; `ar0x-firstboot.service` asserts no passwordless sudoers entry remains; Phase 10 test checks `sudo -l` on the installed system | P10 |
| **RISK-014** | **LOW** | Strong global sysctl hardening breaks Docker/VPN/VMware | `rp_filter=1`, `unprivileged_bpf_disabled=1` | Values documented with rationale in Phase 5; developer audience gets a documented `99-ar0x-dev-override.conf` example; QA includes Docker networking | P5 |
| **RISK-015** | **LOW** | GPG/ISO signature mismatch at release | Signing before the final ISO is written | `checksum.sh` hashes the final file and signs the hash list in one atomic step; release gate requires `gpg --verify` | P11/P12 |

| **RISK-016** | ⚠️ **HIGH** | Docker `--privileged` grants `CAP_SYS_ADMIN`, `MKNOD` and host device access to the build container | Using the Docker option (§7 of BUILD_HOST.md) | Local use only, trusted code only, **never** in PR-driven CI; compose binds only the repo + build root (no Docker socket, no host `/`); documented in `docker/Dockerfile` and `docker/compose.yaml` | P2 |
| **RISK-017** | **MEDIUM** | Host `archiso` drifts past `92-1` and `profiledef.sh` keys (`buildmodes`, `bootmodes`) change | Rolling host update | `setup-build-env.sh` compares `pacman -Q archiso` to the pin and warns; Phase 3 diffs `/usr/share/archiso/configs/baseline/profiledef.sh` | P2/P3 |
| **RISK-018** | **MEDIUM** | `--no-upgrade` creates a partial upgrade; `pacman`/`pacstrap` ABI mismatch | User passes `--no-upgrade` | Default is `-Syu`; explicit warning in script + BUILD_HOST.md §6; flag documented as last resort | P2 |
| **RISK-019** | **MEDIUM** | `work/` on `noexec`/`nodev`/NTFS/exFAT causes cryptic chroot + mknod failures | Wrong build-root filesystem | `check_mount_options` preflight fails early; troubleshooting table in BUILD_HOST.md §10 | P2 |
| **RISK-020** | **LOW** | HARD-pinned source builds fail on missing makedepends (Hyprland has 79 deps) | Phase 8/9 `makepkg` | `makepkg -s` auto-resolves; `--prewarm-calamares` surfaces failures early; PKGBUILDs built in clean chroots. Phase 8 tool PKGBUILDs use LOCAL `source=()` files only (no network/VCS source), so this risk applies to the 5 deferred packages and Phase 9 CI | P8/P9 |

| **RISK-021** | **HIGH** | `Include = /etc/pacman.d/mirrorlist` or wrong `CacheDir` silently bypasses the frozen snapshot | Only explicit `Server =` lines; `bootstrap.sh --check` greps for the exact archive date; archiso 92's `_make_pacman_conf` forces `HookDir` | P3 |
| **RISK-022** | **HIGH** | Missing `mkinitcpio-archiso` or `syslinux` → unbootable ISO | `--check` asserts all 6 mandatory packages against archiso 92's own validators | P3 |
| **RISK-023** | ⚠️ **HIGH** | `bootstrap.sh --clean` irreversibly deletes 10–25 GiB of `work/` | Requires typing the literal word `DELETE`; never invoked automatically | P3 |
| **RISK-024** | **MEDIUM** | `customize_airootfs.sh` removed in a future archiso breaks the build | Not used; pacman hooks are supported; `--check` fails if one appears | P3 |
| **RISK-025** | **MEDIUM** | `[ar0x]` listed after `[core]`/`[extra]` → stale `hyprland 0.57.0-3` wins | `--check` compares repo line numbers; `AR0X_HARD_PIN_REPO_PRIORITY=first` | P3/P11 |
| **RISK-026** | **LOW** | `.gitkeep` placeholders ship inside the live root | `bootstrap.sh` deletes every `.gitkeep` from the staged profile | P3 |

| **RISK-027** | **HIGH** | `CONFIG_RD_ZSTD` absent → zstd initramfs cannot be unpacked → black screen | Asserted `=y` in `config/kernel/ar0x-lts.config`; `--audit-config` on the real kernel; FAILSAFE entry | P4/P11 |
| **RISK-028** | **MEDIUM** | GRUB theme not embedded → unbranded boot menu | Verified archiso 92 `files_to_copy` non-`.cfg` rule puts `archiso/grub/themes/ar0x/` at ISO `/boot/grub/themes/`; `--check` asserts `set theme=` | P4/P11 |
| **RISK-029** | **MEDIUM** | `plymouth` hook before `udev` → no splash / broken initramfs | `--check` enforces hook order in both live drop-in and base config | P4 |
| **RISK-030** | **LOW** | LUKS passphrase prompt invisible (no message renderer in script theme) | Documented `details` theme fallback + FAILSAFE entry; v0.1 defaults to unencrypted ext4 | P4/P10 |
| **RISK-031** | ✅ **CLOSED** | Placeholder PNG art shipped as final branding | **Phase 7 DELIVERED**: `tools/gen-theme-assets.sh` now draws the official SVG-derived logomark into GRUB/Plymouth/syslinux art at the same paths/dimensions; `theme.txt` re-laid out so the menu never overlaps it | P4/P7 |

| **RISK-032** | **HIGH** | Frozen `pacman.conf.build` accidentally shipped as `/etc/pacman.conf` → users stuck on 2026-11-01 | RISK-006: two files, `--sync` writes only the installed one to `/etc`, two validators assert the split | P5/P10 |
| **RISK-033** | ⚠️ **HIGH** | Passwordless `root`/`ar0x` on the LIVE ISO | Warned at every `--check`; never copied to target; Calamares creates hashed passwords | P5/P10 |
| **RISK-034** | **HIGH** | `sysctl --system` or `nft -f` inside a chroot reconfigures the HOST kernel (or firewalls off the build machine) | `--apply` uses only `nft -c -f` / `visudo -cf`; documented prominently in `docs/SYSTEM_CONFIG.md` | P5/P11 |
| **RISK-035** | **MEDIUM** | Two DHCP clients (NM + networkd/dhcpcd) | Explicit `disable` lines in `50-ar0x.preset` | P5 |
| **RISK-036** | **MEDIUM** | `repo.ar0x.dev` not live → `[ar0x]` sync failure | Reserved endpoint documented; `SigLevel = Required` never weakened | P5/P9/P12 |
| **RISK-037** | **LOW** | WirePlumber 0.4 legacy path → silent config loss | Phase 5 corrected to `/etc/pipewire/wireplumber.conf.d/`; `--check` fails if legacy dir returns | P5 |

| **RISK-038** | **MEDIUM** | Arch `sddm 0.21.0-7` hard-depends on `xorg-server`; the GREETER is X11 while the user session is Wayland; Qt5-only QML imports break the Qt6 greeter | Documented in ADR-021 + `docs/DESKTOP_GUIDE.md`; QML uses only `QtQuick`/`SddmComponents 2.0`; `QtVersion=6` asserted; `DisplayServer=wayland` NOT enabled | P6/P11 |
| **RISK-039** | **MEDIUM** | Global `GDK_BACKEND` breaks GTK apps that must run under XWayland | Absent from `lua/env.lua` and `/etc/environment.d/`; `--check` and `validate-versions.sh` both fail if reintroduced | P6 |
| **RISK-040** | ✅ **CLOSED** | Adwaita cursor + generated geometric wallpapers are placeholders, not final ar0x identity | **Phase 7 DELIVERED**: real `ar0x-cursors` XCursor theme (5 shapes × 3 sizes + 12 aliases, generated + parsed back), `XCURSOR_THEME=ar0x-cursors` in Lua/environment.d/skel; boot art finalised. Generated geometric wallpapers are kept as the **deliberate v0.1 art** (licence-clean, reproducible) — see ADR-021 D4. `assets/wallpapers/PLACEHOLDERS.md` records sources | P6/P7 |
| **RISK-041** | **MEDIUM** | Blur/animations look broken under QEMU/llvmpipe software rendering | Conservative blur (2 passes) and animation speeds; QEMU Wayland QA is manual | P6/P11 |
| **RISK-042** | **MEDIUM** | libadwaita hard-codes Adwaita; GTK4 apps ignore `gtk-theme-name` by upstream design | `GTK_THEME` + 20 `@define-color` overrides; documented; full theme engine deferred to `ar0x-theme` (P8) | P6/P8 |
| **RISK-043** | ⚠️ **HIGH** | SDDM QML theme and Wayland session were NEVER rendered in this sandbox (no root / display / QEMU / Hyprland binary) | `--check` does structural validation (balanced delimiters, imports, metadata, palette, JSONC, XML, Lua `require()` resolution); §7 of `DESKTOP_GUIDE.md` is the MANDATORY manual test matrix | P6/P11 |
| **RISK-044** | ⚠️ **HIGH** | Phase 7 brand art (GRUB gfxmenu, Plymouth script splash, syslinux vesamenu, XCursor shapes) was NEVER rendered on a live display in this sandbox | `configure-branding.sh --check` parses back every SVG (XML), PNG (signature + IHDR), Xcursor (magic/TOC/chunk/pixel count), JSONC and shell snippet; §8 of `BRANDING_GUIDE.md` lists exactly what was verified; QEMU UEFI+BIOS visual QA is a Phase 11 MANUAL gate | P7/P11 |
| **RISK-045** | **LOW** | `assets/logo/ar0x-wordmark.svg` uses LIVE `<text>` in Inter; machines without Inter reflow or substitute the wordmark | Inter (`inter-font`) IS on the ISO; `BRANDING_GUIDE.md` §1.4 gives the exact Inkscape *Path → Object to Path* manual step for print/outlining | P7/P12 |
| **RISK-046** | **LOW** | Deterministic PNG raster uses distance-to-segment (round joins) where the SVG polygon has mitre joins | SVG remains authoritative for all vector/print use; PNGs exist only for GRUB/Plymouth/syslinux/raster fallback; documented in `BRANDING_GUIDE.md` §1.9 | P7/P12 |
| **RISK-047** | ⚠️ **HIGH** | GTK4 `ar0x-welcome` window was NEVER rendered: no GTK4, no PyGObject (`gi`), no display, no Wayland session, no QEMU/KVM and no root in this sandbox | `gi` is imported LAZILY so `--self-test` covers every pure-Python path headless; `ar0x_pkgbuild.py` validates the widget source structurally (AST, GTK4 version pin, zero `shell=True` calls, 8 CSS pins, 5 https links, 4 safe groups); `--firstboot` marker skip is tested without a GUI; **MANUAL Phase 8/11 gate**: boot the ISO, click every button, verify polkit agent + CSS palette | P8/P11 |
| **RISK-048** | ⚠️ **HIGH** | **STILL OPEN after Phase 9**: the signed `[ar0x]` database was NOT built/published, so all 8 packages remain SOURCE + PKGBUILD only and `ar0x-meta` is not installable. `config/packages.x86_64` carries ZERO `ar0x-*` packages | Phase 9 shipped the complete tooling: `setup-repo.sh`, `ar0x_repo.py`, 3 CI workflows, `config/repo/**`, all 8 PKGBUILDs (57/57 sums), ADR-024. **MANUAL gates**: air-gapped `--keygen` → `--sync` → `--build` → `--sign` → `--verify` → Phase 12 `--publish`/DNS/TLS. `ar0x_pkgbuild.validate_iso_package_policy()` still FAILS if any `ar0x-*` appears in the ISO list before Phase 11; acceptance criterion 7 remains explicitly blocked | P8/P9 → P11/P12 |
| **RISK-049** | **MEDIUM** | `makepkg`, `gpg`, `repo-add`, `pacman`, `namcap`, `desktop-file-validate`, `systemd-analyze verify` and `shellcheck` are unavailable here — **all 8** PKGBUILDs were NEVER built, only structurally validated | 8/8 PKGBUILDs pass `bash -n`; `ar0x_pkgbuild.py` verifies 57/57 sums (56 real + 1 MANUAL `SKIP`), `ADR-024: 0/8 overlay paths`, 3 `.desktop` files + 2 units; `setup-repo.sh --sync` refreshes all sums; `ar0x_repo.py --self-test` exercises a mock signed repo + 3 negative cases. **MANUAL gate**: `AR0X_CONFIRM_BUILD=yes ./tools/setup-repo.sh --build` as a NON-ROOT `builder` on `archlinux:base-devel`, then `namcap` + `shellcheck` | P8/P9 |
| **RISK-050** | **LOW** | The five `AR0X_URL_*` link endpoints AND `https://repo.ar0x.dev/$arch` are RESERVED; `/tree/main/docs` resolves only AFTER the PR is merged | `links.conf` keeps URL pins in ONE place with `AR0X_URL_*` parity asserted by `--check`; `repo-options.conf` / `pacman.conf.ar0x-entry` / `pacman.conf.installed` all use the same https `$arch` placeholder, asserted by `ar0x_repo.validate_repo_options()`. **MANUAL Phase 12 gate**: `curl -IL` every endpoint, provision DNS + TLS, replace any dead one before tagging v0.1.0 | P8/P9/P12 |
| **RISK-054** | ⚠️ **HIGH** | **NOTHING was released.** No git tag `v0.1.0`, no GitHub Release, no `rsync`/SourceForge/OSDN upload, no announcement, no DistroWatch email. `RELEASE_KEY_FINGERPRINT = PENDING-KEYGEN`, no signed ISO, `docs/TESTING_CHECKLIST.md` is 0/40 | Anyone publishes a DRAFT document, calls `--publish` "released", or fills in an invented SHA256/FPR/ISO URL (RISK-051/053) | `README.md` says `SOURCE-COMPLETE, RELEASE-PENDING` + `NO downloadable ISO`; `CHANGELOG.md` is `UNRELEASED`; `docs/ANNOUNCEMENT.md` says `DO NOT PUBLISH`; `docs/DISTROWATCH.md` says `DO NOT SEND`; `docs/ROADMAP.md` says `PLANNING ONLY`; every missing value is a `{{PLACEHOLDER}}`; `ar0x_release.check_docs()` + `validate-versions.sh §7m` assert all banners and reject a `releases/download/v0.1.0` link; `--publish` is PRINT-ONLY, NEVER uploads, and requires `AR0X_CONFIRM_PUBLISH=yes`. **MANUAL**: the 9 gates in `docs/RELEASE_GUIDE.md §2` | You, P12 |
| **RISK-053** | ⚠️ **HIGH** | **No ISO exists.** `mkarchiso`, `qemu-system-x86_64`, `qemu-img`, `edk2-ovmf`, `xorriso`, `gpg`, KVM, loop devices and root are ALL absent in this sandbox; the ISO was never built, booted, hashed or signed, and the offline release key is `PENDING-KEYGEN` | Anyone claims "ISO built / QEMU booted / signatures verified" from `--check` output alone, or publishes an unsigned artifact (RISK-051) | `tools/build-iso.sh --build` requires `AR0X_CONFIRM_BUILD=yes` + root + `mkarchiso` + a published 40-hex FPR + the signed `ar0x.db.tar.zst`; `tools/checksum.sh --sign` REFUSES on `PENDING-KEYGEN`; derived artifacts are gitignored and never committed; `docs/TESTING_CHECKLIST.md` ships exactly **40 unchecked** `- [ ] T-NN` boxes with a **100%** exit gate, asserted by `ar0x_iso.check_docs()` (negative-tested); `--preflight`/`--qemu-*` are print-only when QEMU is absent. **MANUAL**: real Arch host build, QEMU BIOS+UEFI, disposable-qcow2 install, real-hardware QA, detached signatures | You, P11/P12 |
| **RISK-052** | ⚠️ **HIGH** | Phase 10 Calamares GUI was **NEVER launched**: no Qt6/QML/KPMcore runtime, no Wayland session, no QEMU/KVM, no root, no real target disk in this sandbox; configuration, branding, first-boot wiring and offline self-tests only | Anyone claims "full install → reboot → first boot succeeds" based on structural validation alone | `docs/INSTALLER_FLOW.md §2/§6/§7` marks the whole flow MANUAL; `config/calamares` is validated by `ar0x_installer.py` (9 negative tests + a REAL `ar0x-installer-finish` run into a temp root, NOT an install); `configure-installer.sh --preflight` is print-only and NEVER launches calamares; `calamares` is deliberately absent from `config/packages.x86_64` until the signed `[ar0x]` repo exists. **MANUAL Phase 11 gate**: QEMU UEFI+BIOS install → reboot → `ar0x-welcome` first login | You, P10/P11 |
| **RISK-051** | ⚠️ **CRITICAL** | Offline private GPG release key + CI signing secrets: leakage, an unprotected key, or a bad signature published to users is a **security incident** requiring key rotation, revocation and re-signing every package | `RELEASE_KEY_FINGERPRINT = PENDING-KEYGEN`; `ar0x-trusted` is EMPTY so `SigLevel = Required` correctly refuses an unsigned repo; `ar0x-public-key.asc` is a MANUAL gitignored keygen artifact with `SKIP` checksum; `--keygen` uses `gpg --quick-generate-key` WITHOUT `--batch`/`--passphrase` so gpg-agent demands a real passphrase, `GNUPGHOME` is `0700` under `/opt/ar0x-build/keys`; `validate-packages.yml` + `build-packages.yml` run on forked PRs with **ZERO secrets**; `release.yml` has NO `pull_request` trigger + an explicit fork guard + a protected `release` Environment; `ar0x_repo.validate_workflows()` and `validate_no_secrets()` assert all of this; `ar0x-revoked` is the revocation path. **MANUAL**: air-gapped keygen, fingerprint publication, key rotation | You, P9/P12 |

---

## 2. Risk-by-phase warning index

> **RISK-053 (HIGH, Phase 11):** no `mkarchiso`, `qemu-system-x86_64`,
> `qemu-img`, `edk2-ovmf`, `xorriso`, `gpg`, KVM, loop devices or root in this
> sandbox. `tools/build-iso.sh --build` is MANUAL and REFUSES until the signed
> `[ar0x]` repo exists. `docs/TESTING_CHECKLIST.md` ships **0/40 PASS** — its
> 40 unchecked boxes are the deliverable, NOT a test result. Only `--check`,
> `--sync`, `--self-test`, `--preflight`, the sparse-file size gate and the
> checksum create/verify/tamper round-trip were really executed.


These exact warnings will be repeated at the start of the corresponding phase response:

| Phase | Warnings to repeat |
|---|---|
| 2 | ⚠️ **RISK-016** (Docker `--privileged`), RISK-017, RISK-018, RISK-019; `setup-build-env.sh` must run as **root** on a real Arch host |
| 3 | ⚠️ **RISK-023** (destructive `--clean`), RISK-021, RISK-022, RISK-024, RISK-025, RISK-006 |
| 4 | ⚠️ **RISK-001** (kernel patching — ZERO patches applied), RISK-027, RISK-028, RISK-029, RISK-030, RISK-031, RISK-007 (Secure Boot/MOK) |
| 5 | ⚠️ **RISK-033** (passwordless live user), RISK-032, RISK-034 (host-kernel safety), RISK-008, RISK-014, RISK-035, RISK-036, RISK-037 |
| 6 | ⚠️ **RISK-043** (no live desktop QA), **RISK-002** (Lua-only), RISK-038, RISK-039, RISK-041, RISK-042, RISK-009; RISK-040 CLOSED in P7 |
| 7 | ⚠️ **RISK-044** (no live art render), RISK-045 (live SVG text), RISK-046 (raster joins), **RISK-040 CLOSED**; `configure-branding.sh --apply` is ROOT-only, rebuilds initramfs + `grub.cfg`, and has NO automatic rollback |
| 8 | ⚠️ **RISK-047** (GTK4 never rendered), **RISK-048** (no signed repo yet), RISK-049 (no `makepkg`/`namcap`), **RISK-013** (NOPASSWD guard), RISK-008 (AppArmor opt-in), RISK-020, RISK-042, RISK-050; `configure-tools.sh --build` is MANUAL and RISKY |
| 9 | ⚠️ **RISK-051** (CRITICAL: private release key NEVER on a PR workflow), **RISK-048** (no signed repo after P9 tooling), RISK-049 (no `makepkg`/`gpg`/`repo-add`), RISK-003 (Codeberg), RISK-011 (key custody), RISK-050 (reserved `repo.ar0x.dev`) |
| 10 | ⚠️ **RISK-004** (CRITICAL: destructive partitioning — `lsblk` + TYPED device + disposable VM disk), **RISK-052** (GUI NEVER launched), **RISK-003** (Codeberg 3.4.3 only), **RISK-048/051** (no signed repo → `calamares` not on ISO), RISK-013 (NOPASSWD guard), RISK-033 (empty-password live user), RISK-010 (official-only groups) |
| 11 | ⚠️ **RISK-053** (NO ISO built/booted/hashed/signed), ⚠️ **RISK-004** (destructive partitioning), **RISK-048/051** (no signed repo / release key), **RISK-052** (GUI never rendered), RISK-005, RISK-007, RISK-009, RISK-012, RISK-015, RISK-003 |
| 12 | ⚠️ **RISK-054** (NOTHING released), ⚠️ **RISK-051** (key custody + FPR out of band), **RISK-048/053** (no signed repo / ISO), RISK-015 (signature mismatch), RISK-050 (reserved endpoints), RISK-011 |
| Post-plan | ⚠️ **RISK-053/054** (still NO ISO), **RISK-048/051** (key + signed db), RISK-016 (privileged container), RISK-004 (QEMU install) |

---

## 3. Explicit "do not do this" list (from the 15 years of scar tissue)

1. **Never** run `grub-install` on the *host* while testing the ISO target — always target the
   VM disk or the loop device explicitly with `--target` and `--boot-directory`.
2. **Never** put a private GPG key in Git, in `assets/`, or in a GitHub Actions secret that is
   available to `pull_request` workflows from forks.
3. **Never** ship `hyprland.conf` with Hyprland ≥ 0.57.
4. **Never** clone `github.com/calamares/calamares` expecting the current release.
5. **Never** use a frozen archive mirror in the installed system's `/etc/pacman.conf`.
6. **Never** enable AppArmor enforce globally before testing portals and screen capture.
7. **Never** skip the `lsblk` verification before a manual partitioning step.
8. **Never** run `mkarchiso` from inside the Git checkout with `work/` inside the repo — it
   will produce gigabytes of untracked files and slow Git to a crawl.
9. **Never** mix Hyprland 0.56-era `hyprlock`/`hypridle` with a 0.57 compositor (session-lock
   protocol mismatch).
10. **Never** apply a kernel patch without a second, known-good kernel still present in the ISO.
11. **Never** add an AUR helper, `*-git`/`*-bin` package or `--noconfirm` to `extra-groups.conf`
    or `ar0x-update` (RISK-010 + §9 security contract) — `ar0x_pkgbuild.py` fails the build.
12. **Never** run `ar0x-update --upgrade` as bare root, or lower `[ar0x] SigLevel` below
    `Required` to make an unsigned repo work.
13. **Never** ship a target system with a surviving `NOPASSWD` sudoers rule —
    `/usr/lib/ar0x/ar0x-firstboot` fails loudly (RISK-013).
14. **Never** let a PKGBUILD own an airootfs-overlay path (`/etc/skel/**` or the
    Phase 6/7 `/usr/share/**` trees). ADR-024 resolved ADR-023: all 8 packages now
    have PKGBUILDs, but ONLY into `/usr/share/ar0x/<pkg>/**`, `/usr/share/pacman/keyrings/**`,
    `/usr/share/doc/ar0x-*/**` and `/usr/bin/ar0x-apply-*`. `validate_ownership()` fails the build.
15. **Never** put a private GPG key, passphrase or `*.gpg`/`*.asc`/`*.key` artifact in Git,
    in `assets/`, or in a GitHub Actions secret available to a `pull_request` workflow
    from a fork (RISK-051). `release.yml` is the ONLY signing workflow.
16. **Never** weaken installed `[ar0x] SigLevel` below `Required` — not to `Optional`,
    `Never`, `TrustAll`, `DatabaseOptional` or `PackageOptional`. `Optional TrustAll`
    is **build-only** (`config/pacman.conf.build`, RISK-006).
17. **Never** rely on `repo-add -s` to create package signatures: run `makepkg --sign`
    or `gpg --detach-sign` for EVERY tarball first (`repo-add --include-sigs` embeds them).
18. **Never** run `makepkg` as root, or use `makepkg -s` without `--nodeps` for these 8
    packages — their intra-repo depends do not exist until the build job finishes.
19. **Never** auto-select a Calamares target disk. `partition.conf` keeps
    `initialPartitioningChoice: none`, `settings.conf` keeps
    `prompt-install: true`, and `INSTALLER_FLOW.md` requires a human
    `lsblk -o NAME,SIZE,MODEL,TRAN` read + TYPED device (RISK-004).
20. **Never** enable `ar0x-firstboot.service` in `50-ar0x.preset` (the live-ISO
    preset owns live service state only) or use `systemctl`/D-Bus inside the
    Calamares chroot; Phase 10 uses a plain symlink (ADR-026, RISK-013).
21. **Never** put `args:`/`arguments:` in a `shellprocess.conf`, omit
    `emergency: true` from `umount.conf`, or set `sourcefs` to anything but
    `squashfs` in `unpackfs.conf` — all three are known Calamares 3.4 traps.
22. **Never** run `pacman -Sy`/`-Syu` during an OFFLINE ISO install; `packages.conf`
    sets `update_db: false` and `update_system: false` (§9 contract).
23. **Never** claim an ISO was built/booted/hashed/signed from structural
    validation alone (RISK-053). `--build` needs root + `mkarchiso` + a
    published FPR + the signed `[ar0x]` db; `--sign` REFUSES on `PENDING-KEYGEN`.
24. **Never** put a host device in `--qemu-install`: it creates a **disposable
    qcow2** in a temp dir only, requires `AR0X_CONFIRM_DISPOSABLE_VM=yes` and a
    TYPED `AR0X_TARGET_DISK`, and the guest must run
    `lsblk -o NAME,SIZE,MODEL,TRAN` first (RISK-004).
25. **Never** commit `*.iso`, `SHA256SUMS*`, `*.sig`, `*.gpg`, `packages.lock`
    or a private key (RISK-051); they are gitignored and live in `out/`.
26. **Never** use `md5`/`sha1` for release artifacts, write directly to the
    packaged `OVMF_VARS_4m.fd`, or mix `uefi.grub` with `uefi.systemd-boot`.
27. **Never** remove a DRAFT/UNRELEASED banner, fill in an invented
    SHA256/FPR/ISO URL, or call `--publish` "released" (RISK-054). The driver is
    PRINT-ONLY and NEVER uploads.
28. **Never** run `gh release create` without `--verify-tag` and an EXPLICIT
    list of all 6 artifacts; a glob can silently omit a detached `.sig`
    (RISK-015). Create and push the annotated signed tag FIRST.
29. **Never** publish the release fingerprint only in the release notes —
    publish it OUT OF BAND in `README.md`, a website and a keyserver (RISK-051).
30. **Never** send the DistroWatch draft without a real direct ISO URL; the
    submission needs exactly 4 fields and goes on a waiting list.
31. **Never** add `calamares`, `ar0x-keyring` or `ar0x-meta` to the TRACKED
    `config/packages.x86_64` / `archiso/packages.x86_64` to "finish" the ISO:
    `bootstrap.sh --stage --with-signed-packages` injects them into the
    DISPOSABLE staged profile ONLY, after a `gpg --verify`-passing signed db
    (ADR-029, RISK-048/051).
32. **Never** fabricate a placeholder `.iso` in a sandbox without `mkarchiso`,
    `pacman`, root and Arch mirrors; `build-release.sh --run` FAILS CLOSED
    instead (RISK-053/054).

---

## 4. Residual risk statement

v0.1 is a **developer preview**. The residual risks accepted at release are:

- No bit-for-bit reproducible ISO yet (only package-level reproducibility).
- No default full-disk encryption (offered as a Calamares checkbox).
- No Secure Boot enforcement and no enforcing MAC.
- Single architecture (`x86_64`), single primary download host (GitHub Releases).
- AppArmor policies are minimal; most processes remain unconfined.
- The GTK4 welcome window has had NO live render QA (RISK-047); only headless
  structural + self-test coverage exists.
- The Calamares GUI has had NO live render/install QA (RISK-052): no Qt6, QML,
  Wayland, QEMU/KVM, root or disposable target disk here. `docs/INSTALLER_FLOW.md`
  is a validated CONFIGURATION plus a MANUAL test procedure, NOT a test result.
- **No ISO exists (RISK-053).** `mkarchiso`, QEMU, OVMF, gpg, KVM, loop devices
  and root are absent; `docs/TESTING_CHECKLIST.md` is 0/40 and every QEMU,
  hardware, signature and size item is a MANUAL gate. Phase 11 delivered the
  build/sign/test TOOLING, not a release artifact.
- `ar0x-meta` is STILL not installable: Phase 9 delivered all 8 PKGBUILDs and the
  signing/CI tooling, but the offline key is `PENDING-KEYGEN` and no signed
  `[ar0x]` repository has been built or published (RISK-048/051).
- No PKGBUILD has been built with `makepkg`; no `gpg`, `repo-add`, `pacman-key --populate`
  or `pacman -S ar0x-meta` has run (RISK-049).
- `ar0x-update --upgrade` has NO automatic rollback; `--rollback` can only reach
  versions still present in `/var/cache/pacman/pkg/`.

- **Nothing was released (RISK-054).** No `v0.1.0` tag, GitHub Release,
  mirror upload, announcement or DistroWatch submission exists. Phase 12
  delivered only the print-only tooling and DRAFT/UNRELEASED templates.

- **The real ISO was still NOT built here (RISK-053/054).**
  `tools/build-release.sh --run` is the one-command path on a real Arch host,
  but the Arena sandbox has no root, no Linux capabilities, no `mkarchiso`/
  `pacman`/`gpg` and no Arch mirror access. `--self-test` really stages a
  mkarchiso profile offline; it never produces or claims an ISO.

Each of these is a candidate for v0.2 / v1.0 in the Phase 12 roadmap.
