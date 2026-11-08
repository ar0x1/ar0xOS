# How to actually build the ar0x ISO — post-plan completion guide

**Status:** ✅ the entire automatable build chain is now ONE command on a real
Arch host. ⚠️ **An ISO was NOT built, booted, hashed or signed in the Arena
sandbox** (RISK-053), and **nothing was released** (RISK-054).

---

## 0. Why the ISO cannot be produced in this sandbox (verified, not assumed)

This was checked on 2026-11-03 in the Arena workspace:

| Requirement | State here |
|---|---|
| root / Linux capabilities | `uid=1001(user)`, `CapEff: 0000000000000000`, no `sudo` passwordless |
| `mkarchiso`, `pacstrap`, `pacman`, `arch-chroot`, `mkinitcpio` | **all MISSING** |
| `xorriso`, `grub-mkrescue`, `syslinux`, `mksquashfs`, `losetup` | **all MISSING** |
| `gpg`, `repo-add`, `makepkg`, `namcap` | **all MISSING** |
| `qemu-system-x86_64`, `qemu-img`, OVMF | **all MISSING** |
| `docker`, `podman` | **all MISSING** |
| Arch package mirrors | `archive.archlinux.org` / `geo.mirror.pkgbuild.com` → connection blocked; outbound allowlist is GitHub + npm + PyPI only |
| Offline release key | `RELEASE_KEY_FINGERPRINT = PENDING-KEYGEN` |

`mkarchiso` needs a root Arch userspace, `pacman` against the frozen
`2026/11/01` snapshot, mount/mknod/chroot, loop devices and ~40 GiB of scratch.
**None of that exists here.** Any `.iso` produced in this sandbox would be a
fake, non-bootable file. The driver therefore **fails closed** instead of
fabricating one. This is deliberate (ADR-027/028).

---

## 0. Can this machine build the ISO? (READ THIS FIRST)

`setup-build-env.sh --check` is **read-only** and deliberately downgrades
hardware shortfalls to warnings — it also runs on lint/CI machines. A green
`--check` does **not** mean the host can build. `--yes` (full mode) refuses a
non-Arch host by design, because this toolchain installs with `pacman`:

| Requirement | Minimum | If missing |
|---|---|---|
| OS | **Arch Linux** or a privileged `archlinux:base-devel` container | `Host is not Arch-based`; `pacman`/`makepkg`/`mkarchiso` do not exist. Zorin/Ubuntu/Mint/Debian **cannot** run `setup-build-env.sh --yes` |
| RAM | **8 GiB** (16 recommended) | `Only 5.7 GiB RAM` → hard failure in full mode |
| Free disk at `/opt` | **40 GiB** (64 recommended) | `Not enough free space at /opt: 2.1 GiB` → `mkarchiso` fails with `ENOSPC` |
| Root | `sudo` | `mkarchiso` needs mount/mknod/chroot/loop |
| Not a Live USB | a real installed filesystem | an overlayfs on `filesystem.squashfs` + `/cow` is RAM-backed and only a few GiB |

Example of an **ineligible** host (Zorin 18 Live USB, 5.7 GiB RAM, 2.1 GiB free):

```
[FAIL] Host is not Arch-based (ID=zorin). mkarchiso requires an Arch host or an Arch container.
[FAIL] Only 5.7 GiB RAM; 8 GiB minimum (16 GiB recommended).
[FAIL] Not enough free space at /opt: 2.1 GiB < required 40.0 GiB.
[FAIL] Required command not found: makepkg (run tools/setup-build-env.sh).
[FAIL] Required command not found: mkarchiso (run tools/setup-build-env.sh).
```

The scripts are **working correctly**: they fail closed instead of producing a
broken ISO. No sequence of commands will make this machine build it. Pick ONE:

1. **Install Arch Linux** on real hardware with >= 8 GiB RAM and >= 40 GiB free
   (or move the build root: `sudo ./tools/setup-build-env.sh --yes --build-root /mnt/big/ar0x`).
2. **Use a bigger machine + Docker**: `docker compose -f docker/compose.yaml build`,
   then run `setup-build-env.sh --yes --allow-non-arch` **inside** the Arch
   container. Needs >= 40 GiB free on the Docker host and `--privileged`.
3. **Rent a cloud VPS** (4 vCPU / 16 GiB / 80 GiB), install Arch or Docker there.
4. **GitHub Actions** — see §3D. The workflow is now mirrored into
   `.github/workflows/build-iso.yml` so it is actually dispatchable. Standard
   `ubuntu-latest` has **~14 GB SSD**, below this build's requirement — dispatch
   with the `runner` input set to a self-hosted or larger runner with >= 40 GiB
   free, or the build will run out of space.

⚠️ A GitHub-hosted runner receives the offline private key as a repository
secret. That is **not** air-gapped (RISK-051). For a real public release,
generate the master key on an air-gapped machine and build there instead.

---

## 0.5 Get the SOURCE first (PR #1 is MERGED — plain clone is enough)

There is **no ISO to download anywhere**. What you download is the ~3.8 MB
source repository (about 560 files); the ISO is generated locally by `--run`.
**PR #1 is MERGED**: `main` now holds the entire tree (merge commit `4b1f7e3`),
so a plain `git clone` is correct — no branch flag needed. The working branch
`arena/638da8d7-ar0xos` was cut from that same `main` commit.

```bash
git clone https://github.com/ar0x1/ar0xOS.git
cd ar0xOS
git log -1 --oneline          # expect 4b1f7e3 Merge ar0xOS Phases 1-12 ...
git branch --show-current     # main
./tools/build-release.sh --check
./tools/build-release.sh --preflight
```

ZIP alternative: `https://github.com/ar0x1/ar0xOS/archive/refs/heads/main.zip`.
If `tools/build-release.sh` is missing you have an old checkout:
`git fetch origin && git checkout main && git pull --ff-only`.
Run every command **inside the cloned folder**; build output goes to
`/opt/ar0x-build/out/`, never into the checkout. Windows/macOS users should use
an Arch VM or a cloud VPS with Docker (WSL2 privileged/loop support is
unreliable). Full Hinglish walkthrough: `docs/QUICKSTART_HINDI.md`.

## 1. The one command (after the human key step)

```bash
sudo AR0X_CONFIRM_RELEASE_CHAIN=yes AR0X_CONFIRM_SIGNED_REPO=yes \
     AR0X_CONFIRM_BUILD=yes AR0X_CONFIRM_SIGN=yes \
     ./tools/build-release.sh --run
```

It runs 7 steps in order and writes **only** into `/opt/ar0x-build/`:

1. `./tools/validate-versions.sh` — all offline structure/version gates.
2. `./tools/setup-repo.sh --verify "$AR0X_REPO_DIR"` — signed `[ar0x]` db.
3. `./tools/bootstrap.sh --sync` — regenerate the 3 tracked archiso mirrors.
4. `./tools/build-iso.sh --build` — **stage the real disposable profile**,
   inject `calamares` + `ar0x-keyring` + `ar0x-meta` there (ADR-029), run
   `mkarchiso -m iso`, enforce the `2362232012`-byte (2.2 GiB) gate, write
   `SHA256SUMS`.
5. `./tools/checksum.sh --sign` — detached `SHA256SUMS.sig` + `<iso>.sig`.
6. `./tools/checksum.sh --verify` — `sha256sum -c` + `gpg --verify`.
7. `./tools/prepare-release.sh --check` — release contract.

It **NEVER tags, NEVER uploads, NEVER announces**. It also never partitions a
disk (RISK-004).

Read-only helpers, safe anywhere:

```bash
./tools/build-release.sh --check        # structural validator
./tools/build-release.sh --plan         # exact command chain
./tools/build-release.sh --preflight    # host capability + key/repo report
./tools/build-release.sh --self-test    # REAL disposable --stage in /tmp
```

`--self-test` really stages a complete mkarchiso profile into a temp build root
(no root, no Arch tools), proves the `[ar0x]` block is kept, proves the three
signed packages land in the **staged** profile while the tracked
`config/packages.x86_64` and `archiso/packages.x86_64` stay clean, and proves
`PENDING-KEYGEN` refuses injection. A stub `gpg` is used **only** in that
offline plumbing test; `--run` uses the real `gpg`.

---

## 2. Step 0 — the ONE thing only a human can do

An offline release key cannot be generated in CI or in this sandbox (RISK-051).
On an **air-gapped** machine with `gnupg` installed:

```bash
sudo mkdir -p /opt/ar0x-build/{work,out,repo/x86_64,keys,logs,cache/pacman/pkg,src}
sudo chown -R "$USER":"$USER" /opt/ar0x-build

AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen   # NON-ROOT, air-gapped
# commit ONLY the resulting 40-hex fingerprint in
#   config/repo/RELEASE_KEY_FINGERPRINT
# publish that fingerprint OUT OF BAND (README.md + website + keyserver)
./tools/setup-repo.sh --sync
AR0X_CONFIRM_BUILD=yes ./tools/setup-repo.sh --build    # makepkg REFUSES root
AR0X_CONFIRM_SIGN=yes  ./tools/setup-repo.sh --sign
./tools/setup-repo.sh --verify /opt/ar0x-build/repo/x86_64
```

`--keygen`, `--build` and `--sign` must run as the SAME normal user that owns
`/opt/ar0x-build/keys/gnupg`; otherwise `gpg` cannot read the offline key. If
you did run `--keygen` with `sudo`, `chown -R` the keys directory back first.
Only `--run` below needs root (`mkarchiso`).

Then place the signed `ar0x.db.tar.zst` + `.sig` (and all signed packages) at
`${AR0X_REPO_DIR}` (default `/opt/ar0x-build/repo/x86_64`), and make the
offline private key available at `${AR0X_KEYS_DIR}/gnupg`. Full detail:
`docs/REPO_GUIDE.md §3`.

Without a 40-hex FPR and a `gpg --verify`-passing db, `--run` **refuses**.

---

## 3. Three ways to get a real Arch build host

### A. Docker (any Linux/macOS host with Docker) — recommended

```bash
docker compose -f docker/compose.yaml build
docker compose -f docker/compose.yaml run --rm ar0x-builder \
  ./tools/setup-build-env.sh --check
# then, inside the privileged Arch container:
sudo AR0X_CONFIRM_RELEASE_CHAIN=yes AR0X_CONFIRM_SIGNED_REPO=yes \
     AR0X_CONFIRM_BUILD=yes AR0X_CONFIRM_SIGN=yes \
     ./tools/build-release.sh --run
```

`docker/Dockerfile` is `archlinux:base-devel` + archiso 92-1, arch-install-scripts,
`squashfs-tools`, `libisoburn`, `syslinux`, `grub`, `gnupg`, `qemu-desktop`,
`edk2-ovmf`. `docker/compose.yaml` sets `privileged: true`, `SYS_ADMIN`, `MKNOD`
and passes `/dev/loop-control` — **required** by `mkarchiso` (RISK-016). The
final ISO lands on the host at `/opt/ar0x-build/out/`.

### B. Vagrant (non-Arch host, nested KVM for QEMU QA)

```bash
vagrant plugin install vagrant-libvirt
vagrant up --provider=libvirt
vagrant ssh
cd /ar0xOS && ./tools/setup-build-env.sh --check
sudo AR0X_CONFIRM_RELEASE_CHAIN=yes AR0X_CONFIRM_SIGNED_REPO=yes \
     AR0X_CONFIRM_BUILD=yes AR0X_CONFIRM_SIGN=yes ./tools/build-release.sh --run
```

### C. Native Arch host

```bash
sudo ./tools/setup-build-env.sh
sudo AR0X_CONFIRM_RELEASE_CHAIN=yes AR0X_CONFIRM_SIGNED_REPO=yes \
     AR0X_CONFIRM_BUILD=yes AR0X_CONFIRM_SIGN=yes ./tools/build-release.sh --run
```

### D. GitHub Actions (already on `main` — PR #1 MERGED)

The **dispatchable** copy is `.github/workflows/build-iso.yml` (GitHub Actions
reads only that directory); `ci/workflows/build-iso.yml` is its validated
canonical mirror and the two are byte-identical. Once that file is on `main`,
**Actions → "Build ar0x ISO" → Run workflow** appears. It needs the 3 repository
secrets for the offline key, runs the same privileged Arch container, and
uploads the 6 artifacts as a workflow artifact — **never** a GitHub Release.
Set the `runner` input to a self-hosted/larger runner with >= 40 GiB free;
standard `ubuntu-latest` has only ~14 GB SSD. See `ci/workflows/README.md`.

---

## 4. What changed to make the chain actually runnable

| Previously manual / broken | Now |
|---|---|
| `build-iso.sh --build` called `bootstrap.sh --sync`, which only regenerates 3 tracked files and **never creates** `$AR0X_PROFILE_STAGE`; `mkarchiso` would get a missing/stale profile | new `bootstrap.sh --stage` really builds the disposable profile offline; `--build` calls it |
| A human had to edit `config/packages.x86_64` to add `calamares` + `ar0x-meta`, which would break every offline validator (RISK-048) | `--stage --with-signed-packages` injects `calamares` + `ar0x-keyring` + `ar0x-meta` into the **staged** profile only, after `gpg --verify` of the signed db (ADR-029) |
| `validate-versions.sh §7m` required the literal `PENDING-KEYGEN`, so a real published FPR would FAIL validation | accepts `PENDING-KEYGEN` **or** a published 40-hex FPR |
| 9 publication gates scattered across 3 guides | `tools/build-release.sh --run` chains all automatable ones; `--plan` prints the rest |

---

## 5. After the build — still MANUAL (do not skip)

```bash
sha256sum -c /opt/ar0x-build/out/SHA256SUMS
gpg --verify /opt/ar0x-build/out/SHA256SUMS.sig /opt/ar0x-build/out/SHA256SUMS
gpg --verify /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso.sig \
             /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso

./tools/build-iso.sh --qemu-bios  /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
./tools/build-iso.sh --qemu-uefi  /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
# ⚠️ RISK-004: lsblk -o NAME,SIZE,MODEL,TRAN + TYPED target + disposable qcow2
./tools/build-iso.sh --qemu-install /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
```

- Walk **all 40 items** of `docs/TESTING_CHECKLIST.md` to **100% / 40/40**.
- Real hardware: WiFi, Bluetooth, PipeWire, GPU acceleration, screen capture.
- Provision DNS + TLS for `repo.ar0x.dev`; `curl -IL` all 5 `AR0X_URL_*` links.
- Then, and only then: `docs/RELEASE_GUIDE.md §4` — annotated signed tag
  `v0.1.0`, `gh release create --verify-tag`, `rsync` mirrors, announcement,
  DistroWatch submission. Replace every `{{PLACEHOLDER}}`.

---

## 6. Honest final status

| | |
|---|---|
| Source/toolchain | ✅ All 12 phases + this completion driver, offline-validated |
| `mkarchiso` profile staging | ✅ Really exercised offline (`--self-test`) |
| Signed-repo package injection | ✅ Really exercised offline, staged-only (ADR-029) |
| Real ISO + signatures | ❌ **NOT produced here** — impossible in this sandbox (RISK-053) |
| QEMU / hardware QA | ❌ **0/40** — MANUAL (RISK-004/052) |
| Tag / publication | ❌ **NOT done** — MANUAL (RISK-054) |

Run the two commands in §2 and §1 on a real Arch host and you will have the
ISO. Nobody can do it from this sandbox.

---

Companions: `docs/ISO_BUILD_GUIDE.md`, `docs/TESTING_CHECKLIST.md`,
`docs/REPO_GUIDE.md §3`, `docs/RELEASE_GUIDE.md`,
`docs/architecture/DECISIONS.md` (ADR-029).
