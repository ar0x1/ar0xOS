# ar0x Package Repository Guide — Phase 9 (COMPLETE)

**Distribution:** ar0x `0.1.0` "ar0x root" · Developer Edition
**Status:** ✅ COMPLETE — **all 8** `ar0x-*` PKGBUILDs, ONE-OWNER-PER-PATH
resolution (ADR-024), offline GPG key tooling, `repo-add -s` driver, three
GitHub Actions workflows, repo policy files, and offline validators.
**Depends on:** Phase 5 (`pacman.conf` split), Phase 6 (desktop), Phase 7
(brand assets), Phase 8 (three tools + ADR-023 deferral).
**Next:** Phase 10 — Calamares installer. **Do not auto-advance.**

> ⚠️ **RISK-051 (CRITICAL):** the **private release key is NOT generated**.
> `config/repo/RELEASE_KEY_FINGERPRINT` is `PENDING-KEYGEN`,
> `packages/ar0x-keyring/ar0x-trusted` has ZERO entries, and
> `ar0x-public-key.asc` is a MANUAL, **gitignored** keygen artifact whose
> PKGBUILD checksum is `SKIP`. Generating it is an AIR-GAPPED, human decision
> (§3). A private key must NEVER enter this Git checkout or a PR workflow.
>
> ⚠️ **RISK-048 (HIGH):** the signed `[ar0x]` database **does not exist**.
> No `makepkg`, `gpg`, `repo-add`, `pacman`, `namcap`, `shellcheck` or
> `shellcheck`-equivalent ran here. Phase 9 ships the *complete tooling +
> CI*, not a published repository. Publication is a Phase 12 MANUAL gate.
>
> ⚠️ **RISK-049 (MEDIUM):** `makepkg`/`namcap`/`shellcheck` are unavailable in
> this sandbox. All 8 PKGBUILDs are syntax-checked, checksum-verified and
> structurally validated, but **NOT built**. `ar0x-keyring` in particular
> cannot be built until the public key exists.
>
> ⚠️ **RISK-047 (HIGH):** still no GTK4 / Wayland / QEMU / root here. The
> welcome window has never been rendered. See `docs/TOOLS_GUIDE.md`.
>
> ⚠️ **RISK-010 (LOW):** `Server = https://repo.ar0x.dev/$arch` is a
> **RESERVED endpoint**. DNS + TLS + the mirror upload are Phase 12.
> `config/pacman.conf.build` remains FROZEN and build-only (RISK-006).

---

## 1. Deliverables

### 1.1 All 8 packages (Phases 8 + 9)

| Package | `source=` / `sha256sums=` | Installed paths (complete) |
|---|---|---|
| `ar0x-info` | 5 / 5 | `/usr/bin/ar0x-info`, `/usr/share/applications/ar0x-info.desktop`, `/usr/share/ar0x/info/{fastfetch.jsonc,ar0x-ascii.txt,ar0x-fastfetch.txt}` |
| `ar0x-update` | 3 / 3 | `/usr/bin/ar0x-update`, `/usr/share/applications/ar0x-update.desktop`, `/etc/ar0x/update.conf` |
| `ar0x-welcome` | 10 / 10 | `/usr/bin/ar0x-welcome`, `/usr/bin/ar0x-firstboot`, `/usr/lib/ar0x/ar0x-apparmor-ctl`, CSS, 2 `.desktop`, 2 units, 2 conf mirrors, `.install` |
| **`ar0x-theme`** | 8 / 8 | `/usr/share/ar0x/theme/{gtk-3.0,gtk-4.0,qt5ct,qt6ct,fontconfig}/**` (`7` files) + `/usr/bin/ar0x-apply-theme` |
| **`ar0x-wallpapers`** | 10 / 10 | `/usr/share/ar0x/wallpapers/**` (`9` files: 3 PNG, 4 SVG/LICENSE, GRUB `theme.txt`, SDDM `Main.qml`) + `/usr/bin/ar0x-apply-wallpapers` |
| **`ar0x-hypr-config`** | 15 / 15 | `/usr/share/ar0x/hypr-config/**` (`14` files: `hyprland.lua`, 4 `.conf`, 10 `lua/*.lua`) + `/usr/bin/ar0x-apply-hypr-config` |
| **`ar0x-keyring`** | 5 / 5 (1 `SKIP`) | `/usr/share/pacman/keyrings/{ar0x.gpg,ar0x-trusted,ar0x-revoked}`, `/usr/share/doc/ar0x-keyring/{ar0x-keyring.install,pacman.conf.ar0x-entry}` |
| **`ar0x-meta`** | 1 / 1 | `/usr/share/doc/ar0x-meta/RELEASE`; `depends` on exactly the other 7 |

Totals: **57 `source` entries / 57 `sha256sums` = 56 real SHA-256 + 1 MANUAL
`SKIP`** (`ar0x-public-key.asc`). There are no generated placeholder sources:
every checksum is computed from a real committed file by
`./tools/setup-repo.sh --sync`.

`ar0x-meta` is intentionally **last** in `BUILD_ORDER` and has no payload: it
is the single `pacman -S ar0x-meta` entry point for a stock Arch install.

### 1.2 Repository policy (canonical, tracked)

| File | Role |
|---|---|
| `config/repo/repo-options.conf` | **CANONICAL** plain `KEY="value"` policy (12 options, §4). SOURCED by `setup-repo.sh`; no shebang/strict mode. |
| `config/repo/pacman.conf.ar0x-entry` | The 3 data lines shipped to users: `[ar0x]`, `SigLevel = Required`, `Server = https://repo.ar0x.dev/$arch`. Byte-policy-identical to `config/pacman.conf.installed`. |
| `config/repo/RELEASE_KEY_FINGERPRINT` | `PENDING-KEYGEN`. One 40-hex fingerprint after `--keygen`. **Tracked**, published out of band. |
| `config/repo/README.md` | Canonical-source table. |
| `config/versions.env` | 14 Phase 9 policy keys (parity asserted against `repo-options.conf`). |

### 1.3 Tooling + CI

| File | Role |
|---|---|
| `tools/setup-repo.sh` | Driver: `--check`, `--sync`, `--self-test`, `--verify DIR`, `--keygen`, `--build`, `--sign`, `--publish`. |
| `tools/lib/ar0x_repo.py` | Pure-stdlib validator: mock signed repo + negative tests, `repo_problems()`, `build_manifest()`, policy/entry/keyring/build-order/31-mirror/workflow/secret gates. |
| `tools/lib/ar0x_pkgbuild.py` | Extended to all 8 PKGBUILDs; `ADR-024: 0/8 PKGBUILDs touch overlay-owned paths`. |
| `ci/workflows/validate-packages.yml` | PR-safe, **ZERO secrets**, the whole read-only validator chain + private-key scan. |
| `ci/workflows/build-packages.yml` | `archlinux:base-devel`, non-root `builder`, `makepkg --nodeps` ×8, `namcap`, `shellcheck`, **unsigned** local db smoke test. |
| `ci/workflows/release.yml` | `workflow_dispatch` / `v*` tag only. `gpg --batch` detached signatures, `repo-add -s -v --include-sigs`, `SHA256SUMS.sig`, GitHub Release. |
| `docs/REPO_GUIDE.md` | This document. |

### 1.4 ADR-024 — ONE OWNER PER PATH (resolves ADR-023)

The Phase 6/7 `airootfs` overlay already owns **92 files** under
`archiso/airootfs/etc/skel/**` and `archiso/airootfs/usr/share/**`. A package
that installed into those same paths would make `pacman` abort Calamares with
`error: failed to commit transaction (conflicting files)`.

| Owner | Paths it owns | Never touched by |
|---|---|---|
| **airootfs overlay (ISO)** | `/etc/skel/.config/{gtk-3.0,gtk-4.0,hypr,kitty,...}`, `/usr/share/{backgrounds/ar0x,grub/themes/ar0x,plymouth/themes/ar0x,sddm/themes/ar0x,icons/ar0x-cursors,ar0x/branding,ar0x/logo}` | any `ar0x-*` PKGBUILD |
| **ar0x-theme** | `/usr/share/ar0x/theme/**`, `/usr/bin/ar0x-apply-theme` | overlay |
| **ar0x-wallpapers** | `/usr/share/ar0x/wallpapers/**`, `/usr/bin/ar0x-apply-wallpapers` | overlay |
| **ar0x-hypr-config** | `/usr/share/ar0x/hypr-config/**`, `/usr/bin/ar0x-apply-hypr-config` | overlay |
| **ar0x-keyring** | `/usr/share/pacman/keyrings/ar0x*` | overlay |
| **ar0x-meta** | `/usr/share/doc/ar0x-meta/**` | overlay |

`ar0x-apply-{theme,hypr-config,wallpapers}` are the bridge for **stock Arch
installs that only run `pacman -S ar0x-meta`**: they copy the package-private
reference tree into **one user's** `$XDG_CONFIG_HOME` / `$XDG_PICTURES_DIR`,
creating timestamped backups under `<DEST>/ar0x-backups/` before overwriting
anything. They never write to `/etc/skel` or any system path, never need root,
never use the network. Hyprland config is **Lua-only** (RISK-002).

`tools/lib/ar0x_pkgbuild.py::OVERLAY_OWNED` lists the forbidden `$pkgdir/...`
prefixes; `validate_ownership()` runs on every PKGBUILD. The check is
**structural**, so it works without pacman.

---

## 2. Exact commands (offline, copy-pasteable)

```bash
cd /home/user/ar0xOS

# 1. READ-ONLY structural validation (default). No root, no writes, no network.
./tools/setup-repo.sh --check

# 2. Regenerate 31 canonical -> package mirrors, derive ar0x-trusted from the
#    fingerprint, refresh ALL 8 PKGBUILD SHA-256 sums, stage a test prefix.
./tools/setup-repo.sh --sync

# 3. Offline self-test: mock signed repo (+ negative cases) + REAL runs of the
#    3 ar0x-apply-* helpers into a temp HOME + the 3 Phase 8 tools' self-tests.
./tools/setup-repo.sh --self-test

# 4. Verify an ACTUAL built repo tree (after §3).
./tools/setup-repo.sh --verify /opt/ar0x-build/repo/x86_64

# 5. Whole-repo gates (run all of them; each is read-only except --sync).
python3 tools/lib/ar0x_pkgbuild.py /home/user/ar0xOS
python3 tools/lib/ar0x_repo.py  /home/user/ar0xOS
python3 tools/lib/ar0x_repo.py  /home/user/ar0xOS --self-test
./tools/validate-versions.sh
./tools/bootstrap.sh --check
./tools/configure-tools.sh --check
./tools/configure-system.sh --check
./tools/configure-desktop.sh --check
./tools/configure-branding.sh --check

# 6. Stage a publish bundle. NEVER uploads (prints the MANUAL commands).
./tools/setup-repo.sh --publish
```

`--sync` also calls `./tools/configure-tools.sh --sync`, so the Phase 8 mirrors
and sums stay in lockstep. It is **idempotent** and writes only into
`build/` (gitignored) plus the tracked PKGBUILD sums.

---

## 3. ⚠️ MANUAL / AIR-GAPPED procedure (do NOT run in this sandbox)

These are the steps that **cannot** be validated offline. Each requires an
explicit `AR0X_CONFIRM_*=yes` acknowledgement; `--build` refuses root because
`makepkg` does.

### 3.1 Generate the offline release key (ONCE, air-gapped host)

```bash
# On an AIR-GAPPED machine with gpg + pinentry. Back up the private key OFFLINE.
sudo AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen
```

What it does:

1. `GNUPGHOME=/opt/ar0x-build/keys/gnupg` (`0700`), refuses to overwrite an
   existing key for `AR0X_REPO_KEY_UID`.
2. `gpg --quick-generate-key "<UID>" ed25519 sign 2y` — **no `--batch`, no
   `--passphrase`**: gpg-agent asks for a strong passphrase via pinentry. An
   unprotected offline master key would be a critical bug.
3. Writes the 40-hex fingerprint to `config/repo/RELEASE_KEY_FINGERPRINT`.
4. Exports `packages/ar0x-keyring/ar0x-public-key.asc` (gitignored `*.asc`).

Then **review and COMMIT** the fingerprint, publish it **out of band** (README,
website, keyserver), and run:

```bash
./tools/setup-repo.sh --sync     # writes FPR:6: into ar0x-trusted, replaces SKIP
./tools/setup-repo.sh --check
```

> ⚠️ `pacman-key --populate ar0x` requires a **40-hex** fingerprint in
> `ar0x-trusted` (`FPR:6:` = ultimate ownertrust). Until it exists,
> `SigLevel = Required` correctly **refuses** the repository. Never fabricate
> a fingerprint to make validation pass.

### 3.2 Build all 8 packages (real Arch host / CI container)

```bash
AR0X_CONFIRM_BUILD=yes ./tools/setup-repo.sh --build
```

`makepkg --nodeps --noconfirm --force` in `BUILD_ORDER` (meta last).
`--nodeps` is **deliberate**: `ar0x-welcome` depends on `ar0x-info` and
`ar0x-update`, and `ar0x-meta` depends on all seven others — none of which
exist in any repository until this job has built them. All 8 are
`arch=('any')` data/CLI packages with no compile step. `namcap` advisories are
printed, not fatal. Output is **unsigned**.

In CI, `ci/workflows/build-packages.yml` does this in
`archlinux:base-devel` as a **non-root** `builder` account (`useradd`,
`chown`, `sudo -u builder makepkg`). **Never run `makepkg` as root.**

### 3.3 Sign packages + database

```bash
sudo AR0X_CONFIRM_SIGN=yes ./tools/setup-repo.sh --sign
./tools/setup-repo.sh --verify /opt/ar0x-build/repo/x86_64
```

```bash
# What --sign actually runs (for review):
gpg --yes --local-user "$FPR" --output "$pkg.sig" --detach-sign "$pkg"
GPGKEY="$FPR" repo-add -s -v --include-sigs \
    ar0x.db.tar.zst ./*.pkg.tar.zst
sha256sum -- ./* > SHA256SUMS
gpg --yes --local-user "$FPR" --output SHA256SUMS.sig --detach-sign SHA256SUMS
```

* `-s` signs **both** `ar0x.db.tar.zst` and `ar0x.files.tar.zst`.
* `-v` verifies the **existing** db signature before rewriting it (prevents
  silently replacing a good db with a bad one).
* `--include-sigs` embeds the per-package `.sig` files in the db.
* `repo-add -s` **does not** create package signatures — the explicit
  `gpg --detach-sign` loop (or `makepkg --sign`) is required, otherwise
  `SigLevel = Required` rejects every package.

Resulting publish tree:

```
/opt/ar0x-build/repo/x86_64/
├── ar0x.db.tar.zst           (+ ar0x.db.tar.zst.sig)
├── ar0x.files.tar.zst        (+ ar0x.files.tar.zst.sig)
├── ar0x-info-0.1.0-1-any.pkg.tar.zst            (+ .sig)   × 8
├── SHA256SUMS                (+ SHA256SUMS.sig)
└── ...
```

### 3.4 Publish (Phase 12 MANUAL — setup-repo.sh NEVER uploads)

```bash
./tools/setup-repo.sh --publish
# then, by a human, after DNS + TLS for repo.ar0x.dev are live:
rsync -av --delete build/repo-publish/x86_64/ user@mirror:/srv/repo/x86_64/
gh release create v0.1.0 build/repo-publish/x86_64/* --generate-notes
```

`--publish` stages `build/repo-publish/x86_64/` (gitignored), calls
`repo_problems()` on it, and writes a `PUBLISH-MANIFEST.md` of real SHA-256
digests. **No network call, no upload, no release is created by the script.**

### 3.5 Trust bootstrap on an installed system

```bash
sudo pacman-key --init                  # local master key (once)
sudo pacman -U ar0x-keyring-0.1.0-1-any.pkg.tar.zst
# ar0x-keyring.install runs `pacman-key --populate ar0x` in
# post_install()/post_upgrade(): imports ar0x.gpg, lsigns + trusts the FPR
# from ar0x-trusted, then disables any key in ar0x-revoked.
sudo pacman -S ar0x-meta
```

`config/pacman.conf.installed` declares `[ar0x] SigLevel = Required` **before**
`[core]` (ADR-017). `Required` covers packages **and** databases; `TrustedOnly`
is inherited from the `[options]` default. The build-only
`config/pacman.conf.build` uses `SigLevel = Optional TrustAll` with
`Server = file://@AR0X_REPO_DIR@` and is **never** installed (RISK-006).

---

## 4. Configuration tradeoffs (every option explained)

`config/repo/repo-options.conf` is the canonical policy; `config/versions.env`
mirrors the 9 shared keys and `tools/lib/ar0x_repo.py` asserts parity.

| Option | Value | Tradeoff |
|---|---|---|
| `AR0X_REPO_NAME` | `ar0x` | Must match `[ar0x]` in all pacman configs. |
| `AR0X_REPO_ARCH` | `x86_64` | Single-arch v0.1; `$arch` stays a literal pacman placeholder in `Server`. |
| `AR0X_REPO_DB` / `AR0X_REPO_FILES_DB` | `ar0x.db.tar.zst` / `ar0x.files.tar.zst` | `repo-add` creates BOTH; `.files` powers `pacman -F`. Zstd keeps the ~2 GB ISO budget realistic. |
| **`AR0X_REPO_SIGLEVEL`** | **`Required`** | Requires valid signatures on packages AND db; inherits `TrustedOnly`. **Never** `Optional`, `Never`, `TrustAll`, `DatabaseOptional`, or `PackageOptional`. Weakening it defeats the whole §9 threat model. |
| `AR0X_REPO_SIGN_PACKAGES` | `yes` | Per-package `.sig` files in addition to the db sig. Slightly more bytes; without them `Required` rejects installs. |
| `AR0X_REPO_INCLUDE_SIGS` | `yes` | `repo-add --include-sigs` embeds package sigs in the db so a mirror can be verified from the db alone. |
| `AR0X_REPO_VERIFY_EXISTING` | `yes` | `repo-add -v` verifies the previous db.sig before rewriting; protects against clobbering a good db. |
| **`AR0X_REPO_REMOVE_OLD`** | **`0`** | `repo-add -R` would delete superseded tarballs — that **breaks `ar0x-update --rollback`** (Phase 8). Keep them. |
| `AR0X_REPO_KEEP_OLD` | `3` | Keep 3 previous versions in the publish bundle; bounded mirror growth with a usable rollback window. |
| `AR0X_REPO_SERVER` | `https://repo.ar0x.dev/$arch` | Reserved endpoint (RISK-050/Phase 12). `https` is mandatory; a plain-HTTP mirror would allow db substitution. |
| `AR0X_REPO_PUBLIC_KEY` | `ar0x-public-key.asc` | Generated, gitignored. PKGBUILD uses `SKIP` **only** for this one file until `--keygen` provides a real sum. |
| `AR0X_REPO_KEY_FINGERPRINT_FILE` | `config/repo/RELEASE_KEY_FINGERPRINT` | Tracked so users can verify out of band. **Not** a secret. |
| `AR0X_REPO_CI_IMAGE` | `archlinux:base-devel` | Matches the host toolchain; no cross-distro `makepkg` surprises. |
| `AR0X_REPO_CI_BUILDER` | `builder` | `makepkg` refuses root — a non-root account is mandatory. |
| `AR0X_REPO_KEY_ALGO` / `_EXPIRE` (versions.env) | `ed25519` / `2y` | Short-lived, modern signing-only key. Rotation is a v0.2 decision; revocation goes in `ar0x-revoked`. |

`AR0X_REPO_SERVER` is written as `\$arch` in both sourced files **on
purpose**: a bare `$arch` would abort `source config/versions.env` under
`set -u` with `unbound variable`. The Python parsers normalise `\$` back to
`$` before comparing with `pacman.conf`.

---

## 5. CI security contract (RISK-051)

| Workflow | Triggers | Secrets | Signs? |
|---|---|---|---|
| `validate-packages.yml` | push, **pull_request (forks included)**, manual | **NONE** | No |
| `build-packages.yml` | push, **pull_request (forks included)**, manual | **NONE** | No — unsigned local db only |
| `release.yml` | `workflow_dispatch` on a protected ref, or `v*` tag | `AR0X_RELEASE_GPG_KEY`, `AR0X_GPG_PASSPHRASE`, `AR0X_RELEASE_FPR` | **Yes** |

* `release.yml` **has no `pull_request` trigger** and its job carries an
  explicit fork guard. A private key must never be reachable from a workflow
  that executes forked PR code — this is the single most important rule.
* `ar0x_repo.py::validate_workflows()` asserts this structurally in
  `--self-test`, so a future edit cannot accidentally re-enable secrets on PRs.
* Secrets live in a protected GitHub **Environment** (`release`), not plain
  repo secrets. The **offline master key is never in GitHub at all**; CI uses
  a dedicated signing subkey.
* `ar0x-keyring` is skipped in unsigned PR builds because
  `ar0x-public-key.asc` is a MANUAL keygen artifact — the workflow emits a
  `::warning::` rather than a failure.
* `validate_no_secrets()` scans 74 source files for real armored private-key
  blocks and for `SigLevel = Never`. `.gitignore` blocks `*.gpg`, `*.asc`,
  `*.key`, `/keys/`, `*.pkg.tar.zst*`, `*.db.tar.*`, `*.files.tar.*`.

---

## 6. Verification actually performed in this sandbox

| Gate | Result |
|---|---|
| `bash -n` on all 8 `PKGBUILD`, 2 `.install`, 8 bash executables, `setup-repo.sh`, all `tools/*.sh` | ✅ PASS |
| `python3 -m ast` on `ar0x_pkgbuild.py`, `ar0x_repo.py`, `ar0x-welcome.py` | ✅ PASS |
| `python3 tools/lib/ar0x_pkgbuild.py .` | ✅ `8` PKGBUILDs, `57/57` sums, `ADR-024: 0/8 overlay paths`, `packages.x86_64` Phase 11 gate; 1 MANUAL `[WARN]` |
| `python3 tools/lib/ar0x_repo.py .` | ✅ `31` byte-identical mirrors, repo options parity, `[ar0x]` entry parity, keyring, 3 workflows, no private-key material |
| `python3 tools/lib/ar0x_repo.py . --self-test` | ✅ mock signed repo + 3 negative cases + build order + manifest determinism |
| `./tools/setup-repo.sh --check / --sync / --self-test` | ✅ see §2 |
| `./tools/validate-versions.sh`, `bootstrap.sh --check`, 5 configure/build `--check` chains | ✅ PASS |
| `git diff --check` | ✅ PASS |

**NOT performed (never claim these):** `makepkg`, `namcap`, `shellcheck`,
`gpg --quick-generate-key`, `gpg --detach-sign`, `repo-add`, `repo-add -s`,
`pacman-key --populate`, `pacman -U/-S ar0x-meta`, `mkarchiso`, QEMU/UEFI+BIOS
boot, live Wayland/GTK4 render, DNS/TLS for `repo.ar0x.dev`, any upload or
GitHub Release creation. **No signed `[ar0x]` repository exists yet.**

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `arch: unbound variable` when sourcing `versions.env` | Someone removed the `\` in `\$arch`. Restore the escape (§4). |
| `[FAIL] ar0x-keyring: ar0x-public-key.asc absent` | Expected **warning** until `--keygen`. `[WARN]` is not a failure. |
| `SKIP` in a PKGBUILD other than `ar0x-keyring/ar0x-public-key.asc` | `ar0x_pkgbuild.py` rejects it. Run `--sync` to compute a real sum. |
| `error: failed to commit transaction (conflicting files)` | A PKGBUILD tried to own an airootfs path. Run `ar0x_pkgbuild.py` — `validate_ownership()` forbids it (ADR-024). |
| `pacman: signature from ... is unknown trust` | `ar0x-trusted` has no `FPR:6:` entry, or `pacman-key --init` was never run. Re-do §3.1/§3.5. |
| `repo-add: could not find package signature` | `repo-add -s` does NOT create `.sig` files. Sign packages first (§3.3). |
| CI `makepkg: Running makepkg as root is a BIG NO NO` | Build job must `useradd builder` and `sudo -u builder makepkg`. |
| `ar0x-meta` fails to resolve depends in CI | `--nodeps` is required for intra-repo dependencies (§3.2). |
| `--self-test` complains the prefix is missing | Run `--sync` first; it stages `build/repo-prefix/`. |
| `[ar0x] 404 / connection refused` | Reserved endpoint. DNS + mirror upload are Phase 12. |

---

## 8. Risks

| ID | Level | Description |
|---|---|---|
| `RISK-048` | HIGH | Signed `[ar0x]` db + 8 installed packages do not exist; ISO still carries zero `ar0x-*` packages. Phase 11 wires them in; Phase 12 publishes. |
| `RISK-049` | MEDIUM | No `makepkg`/`namcap`/`shellcheck` here; PKGBUILDs are structurally validated, not built. |
| `RISK-050` | LOW | `repo.ar0x.dev` and the five welcome links are RESERVED endpoints. |
| **`RISK-051`** | **CRITICAL** | Offline private release key + CI signing secrets: leakage or a bad signature published to users is a security incident. Mitigated by air-gapped keygen, `0700` GNUPGHOME, gitignore, PR-safe workflows with zero secrets, a protected release Environment, and the explicit fork guard. Key generation, rotation and revocation remain MANUAL. |

---

## 9. Companion documents

`PROJECT_PLAN.md` (§9 security, §10 Phase 9) ·
`docs/architecture/DECISIONS.md` (ADR-017, ADR-023, **ADR-024**) ·
`docs/architecture/RISK_REGISTER.md` (RISK-047…051) ·
`docs/architecture/BUILD_LAYOUT.md` ·
`docs/architecture/DEPENDENCY_GRAPH.md` (GATE-9) ·
`docs/architecture/COMPONENT_VERSIONS.md` ·
`docs/TOOLS_GUIDE.md` (Phase 8 tools + ADR-023) ·
`packages/README.md` · `config/repo/README.md` · `ci/workflows/README.md`.
