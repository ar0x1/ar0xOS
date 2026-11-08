# ar0x ISO banana aur use karna — Quickstart (Hinglish)

> ⚠️ **Sach pehle:** is repo me **koi ISO file nahi hai**. Ye sandbox (Arena) me
> ISO banana **namumkin** hai — yahan root nahi, `mkarchiso`/`pacman`/`gpg`
> nahi, aur Arch mirror blocked hai. Neeche wale steps **aapki apni machine**
> par chalane hain. `docs/BUILD_RELEASE_ISO.md` = pura English guide.

---

## 0. Shuruat — "ISO ka code" kahan se aayega? (ISO download NAHI karni)

### Seedha jawab
**Aapko ISO download nahi karni — SOURCE CODE download karni hai.** Koi `.iso`
file kahin bhi **maujood hi nahi hai** (na GitHub par, na is workspace me). Jo
maine likha hai wo ~**560 files / ~3.8 MB** ka repository hai: build scripts,
archiso profile, Calamares config, docs. `build-release.sh --run` **aapki apni
machine par** ISO *generate* karega. Isliye "ISO ka code" = ye repo.

### ✅ Ab branch ki jhanjhat khatam
**PR #1 MERGE ho chuka hai.** `main` par ab poora code hai (merge commit
`4b1f7e3`, 560 files). Isliye **plain `git clone` ab bilkul sahi hai** — kisi
branch ka naam batane ki zarurat nahi. (Is session ka working branch
`arena/638da8d7-ar0xos` bhi `main` se hi nikla hai, same content.)

### Poora safar — 6 kadam ek nazar me

| # | Kadam | Kahan |
|---|---|---|
| 1 | Code download + verify | §0 Option A |
| 2 | Machine / Docker taiyar | §2 |
| 3 | Offline GPG key + signed `[ar0x]` repo (**sirf aap**) | §3 |
| 4 | **ISO banao — ek command** | §4 |
| 5 | Hash/signature verify + QEMU/USB test + 40/40 checklist | §5–6 |
| 6 | (optional) tag / release | §8 |

### Option A — `git` se (recommended)

```bash
git clone https://github.com/ar0x1/ar0xOS.git
cd ar0xOS
git log -1 --oneline      # "4b1f7e3 Merge ar0xOS Phases 1-12..." dikhna chahiye
git branch --show-current # main
ls                        # archiso/ assets/ ci/ config/ docker/ docs/ packages/ tools/ ...
./tools/build-release.sh --check
./tools/build-release.sh --preflight
```

Agar `tools/build-release.sh` na mile, to purana checkout hai:
`git fetch origin && git checkout main && git pull --ff-only`.

### Option B — ZIP (git install kiye bina)

```
https://github.com/ar0x1/ar0xOS/archive/refs/heads/main.zip
```
Browser me: GitHub → **Code → Download ZIP** → extract → `cd ar0xOS-main`.

### Option C — PR / merged history dekhna

```
https://github.com/ar0x1/ar0xOS/pull/1
```
Ab `MERGED` hai; "Files changed" me saari 560 files dikh ti hain. Build ke liye
Option A/B behtar hai.

### Option D — Arena workspace

Jo files is chat ke viewer me hain (`docs/QUICKSTART_HINDI.md`,
`docs/BUILD_RELEASE_ISO.md`, `tools/build-release.sh`, …) wahi repo ki files
hain (working branch `arena/638da8d7-ar0xos`). Par build ke liye poora folder
chahiye, isliye `git clone` sabse aasan hai.

### Code me kya kya hai (jo aap download kar rahe ho)

| Path | Kaam |
|---|---|
| `tools/build-release.sh` | **ek command** me poora ISO chain (`--run`) |
| `tools/setup-repo.sh` | offline keygen → 8 packages → sign → verify |
| `tools/bootstrap.sh` | archiso profile stage karta hai (`--stage`) |
| `tools/build-iso.sh` | `mkarchiso`, 2.2 GiB gate, QEMU launchers |
| `tools/checksum.sh` | `SHA256SUMS` + detached GPG signatures |
| `tools/lib/*.py` | offline validators (negative tests ke saath) |
| `config/**`, `archiso/**` | system, desktop, branding, Calamares, ISO pins |
| `packages/*/PKGBUILD` | 8 `ar0x-*` packages |
| `docker/Dockerfile`, `docker/compose.yaml` | privileged Arch build container |
| `docs/**` | yahi guide + 40-item testing checklist + release guide |

### Commands **kahan** type karne hain?

Clone jis folder me kiya (`~/ar0xOS`), **usi folder ke andar** terminal khol kar
sab commands chalao. `./tools/...` ka matlab yahi current folder hai. `sudo`
wali commands par aapka Linux password maangega. Build ka output **repo me
nahi**, `/opt/ar0x-build/out/` me jata hai (gitignored, isliye repo clean rahega).

### Apne OS ke hisaab se raasta chuno

| Aapke paas | Kya karein |
|---|---|
| **Linux + Docker** | §2 "Option A" — sabse aasan, Arch install karne ki zarurat nahi |
| **Arch Linux (native)** | §2 "Option B", `sudo ./tools/setup-build-env.sh --yes` |
| **Windows / macOS** | VirtualBox/VMware me **Arch Linux VM** banao (40–64 GB disk, 8–16 GB RAM), ya cloud VPS (Ubuntu + Docker). ⚠️ WSL2 me `--privileged` + loop devices unreliable hai, avoid karo |
| **Koi 40 GB machine nahi** | neeche "GitHub Actions" wala raasta — local build ki zarurat nahi |

### GitHub Actions — bina apni machine ke (ab MERGE ho chuka hai)

`ci/workflows/build-iso.yml` ab **`main` par hai**, isliye
`workflow_dispatch` seedha trigger ho sakta hai — koi PR merge karne ki zarurat
nahi. GitHub ke runner par hi privileged Arch container me ISO banta hai:

1. Repo → **Settings → Secrets and variables → Actions** me 3 secrets daalo:
   `AR0X_RELEASE_GPG_KEY` (offline private key ka base64),
   `AR0X_GPG_PASSPHRASE`, `AR0X_RELEASE_FPR` (40-hex).
2. **Actions → "Build ar0x ISO" → Run workflow** (`dry_run` pehle on karke
   preflight dekh sakte ho).
3. Workflow ke **Artifacts** se 6 files download karo.

⚠️ Ye bhi **tag/release nahi karta**; QEMU/hardware QA (40/40) aur publication
phir bhi manual hai. Forked PR ko kabhi signing secrets mat dena (RISK-051).

---

## 1. Aapko kya chahiye

| Cheez | Minimum | Recommended |
|---|---|---|
| Machine | x86_64, **Arch Linux** (ya kisi bhi Linux par Docker) | Arch host ya `archlinux:base-devel` container |
| Root | `sudo` / root (`mkarchiso` ko chahiye) | root |
| RAM | 8 GiB | 16 GiB (QEMU `copytoram` test ke liye) |
| Free disk | **40 GiB** `/opt/ar0x-build` me | 64 GiB |
| Internet | Arch mirrors (`archive.archlinux.org`) | haan |
| Tools | `archiso 92-1`, `arch-install-scripts`, `squashfs-tools`, `libisoburn`, `syslinux`, `grub`, `gnupg`, `qemu-desktop`, `edk2-ovmf` | `./tools/setup-build-env.sh` auto-install karta hai |
| USB (real install ke liye) | 8 GB | Ventoy ya empty USB |
| Time | ~1–2 ghanta build + QA | — |

⚠️ **Ek kaam sirf aap kar sakte ho:** offline GPG release key banana (air-gapped).
Ye CI/sandbox me generate nahi hoti (RISK-051). Private key kabhi Git mat daalna.

---

## 2. Build host taiyar karo (ek baar)

### Option A — Docker (non-Arch host par bhi chalega) ✅ recommended

```bash
git clone https://github.com/ar0x1/ar0xOS.git && cd ar0xOS
docker compose -f docker/compose.yaml build
docker compose -f docker/compose.yaml run --rm ar0x-builder \
    ./tools/setup-build-env.sh --check
```

`docker/compose.yaml` me `privileged: true` + `/dev/loop-control` pehle se hai —
`mkarchiso` ko `mount`/`mknod`/`chroot` chahiye (RISK-016). Container ke andar
aage wale steps chalao.

### Option B — Seedha Arch host

```bash
git clone https://github.com/ar0x1/ar0xOS.git && cd ar0xOS
./tools/setup-build-env.sh --check     # read-only, kuch bhi install nahi karta
sudo ./tools/setup-build-env.sh        # packages install karta hai
```

### Option C — Vagrant

```bash
vagrant plugin install vagrant-libvirt && vagrant up --provider=libvirt && vagrant ssh
cd /ar0xOS && ./tools/setup-build-env.sh --check
```

---

## 3. Step 0 — Release key + signed `[ar0x]` repo (HUMAN, air-gapped)

`makepkg` root se **chal hi nahi sakti**. Isliye `/opt/ar0x-build` ka owner apna
normal user rakho aur keygen/sign **bina sudo** chalao:

```bash
sudo mkdir -p /opt/ar0x-build/{work,out,repo/x86_64,keys,logs,cache/pacman/pkg,src}
sudo chown -R "$USER":"$USER" /opt/ar0x-build

# ⚠️ AIR-GAPPED machine par karo. Private key ka OFFLINE backup bana lo.
AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen
# ab config/repo/RELEASE_KEY_FINGERPRINT me 40-hex FPR likha gaya hai.
# Us FPR ko commit karo aur README/website/keyserver par OUT OF BAND publish karo.

./tools/setup-repo.sh --sync
AR0X_CONFIRM_BUILD=yes ./tools/setup-repo.sh --build     # 8 packages, NON-ROOT
AR0X_CONFIRM_SIGN=yes  ./tools/setup-repo.sh --sign
./tools/setup-repo.sh --verify /opt/ar0x-build/repo/x86_64
```

Agar aapne `--keygen` `sudo` se chalaya hai, to `--sign` se pehle
`sudo chown -R "$USER":"$USER" /opt/ar0x-build/keys` kar do, warna `gpg` key
nahi padh payega.

---

## 4. Step 1 — ISO banao (EK command)

```bash
sudo AR0X_CONFIRM_RELEASE_CHAIN=yes AR0X_CONFIRM_SIGNED_REPO=yes \
     AR0X_CONFIRM_BUILD=yes AR0X_CONFIRM_SIGN=yes \
     ./tools/build-release.sh --run
```

Ye automatically karta hai:

1. `validate-versions.sh` — saare offline gates
2. signed repo verify
3. `bootstrap.sh --sync`
4. **asli** mkarchiso profile stage + `calamares`/`ar0x-keyring`/`ar0x-meta`
   inject (sirf staged profile me, ADR-029) → `mkarchiso` → ≤ 2.2 GiB size gate
   → `SHA256SUMS`
5. detached GPG signatures
6. `sha256sum -c` + `gpg --verify`
7. release contract check

**Output:** `/opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso` + 5 aur artifacts
(`SHA256SUMS`, `SHA256SUMS.sig`, `<iso>.sig`, `CHANGELOG.md`, `README.md`).

Ye command **tag/upload/announcement nahi karta** — wo alag se manual hai.

Kabhi bhi "fake ISO" mat banaana; yahan `--run` jaan-bujhkar **fail closed** hota
hai agar root / key / signed db / Arch tools missing ho.

---

## 5. Step 2 — Verify karo (publish se pehle zaroori)

```bash
cd /opt/ar0x-build/out
sha256sum -c SHA256SUMS
gpg --verify SHA256SUMS.sig SHA256SUMS
gpg --verify ar0x-0.1.0-x86_64.iso.sig ar0x-0.1.0-x86_64.iso
```

---

## 6. Step 3 — Test karo (bina real install ke)

```bash
./tools/build-iso.sh --qemu-bios  /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
./tools/build-iso.sh --qemu-uefi  /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
# installer VM (disposable qcow2):
./tools/build-iso.sh --qemu-install /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
```

Phir **`docs/TESTING_CHECKLIST.md` ke 40/40 items** pass karo (100% gate) —
WiFi, Bluetooth, PipeWire audio, GPU, screen capture, real hardware, VBox/VMware.

> ⚠️ **RISK-004 (sabse khatarnak):** install se pehle guest me
> `lsblk -o NAME,SIZE,MODEL,TRAN` chalao, target device **TYPED** karo,
> disposable qcow2/VM disk use karo, aur real machine ka **backup** lo.
> Kabhi bhi auto-disk-select mat hone dena.

---

## 7. Step 4 — ISO ko "use" karna

### USB se (real hardware)

```bash
lsblk -o NAME,SIZE,MODEL,TRAN          # ⚠️ PEHLE ye karo, device confirm karo
sudo dd if=/opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso \
        of=/dev/sdX bs=4M status=progress oflag=sync
```

`/dev/sdX` ki jagah **apni sahi USB device** likho — galat device = pura data
delete. Aasan alternative: **Ventoy** USB banao aur `.iso` file copy kar do.

Boot karo → GRUB/syslinux menu → Plymouth → SDDM → **Hyprland Wayland** live
session. Phir desktop par Calamares installer → partitioning → user banao →
install → reboot → first boot par `ar0x-welcome` app.

### Ya VM me hi

QEMU/VirtualBox/VMware me ISO attach karo, UEFI ya BIOS boot chuno, aur andar
hi install karke dekho. Real disk ki zarurat nahi.

---

## 8. Step 5 — Release karna (optional, tabhi jab 40/40 PASS ho)

`docs/RELEASE_GUIDE.md §4`: annotated signed tag `v0.1.0` →
`gh release create --verify-tag --notes-file ...` (poore 6 artifacts) → `rsync`
mirrors → announcement → DistroWatch. `tools/prepare-release.sh --publish`
sirf **commands print** karta hai, upload nahi.

---

## 9. Agar atak gaye

| Problem | Fix |
|---|---|
| `PENDING-KEYGEN` / `--run` refuse | Step 0 dobara karo; FPR 40-hex hona chahiye |
| `makepkg refuses root` | `--build` normal user se chalao, `sudo` hatao |
| `gpg` key nahi mila | `GNUPGHOME=/opt/ar0x-build/keys/gnupg` owner check karo |
| `[ar0x] db missing` | `setup-repo.sh --sign` + `--verify` chalao |
| ISO > `2362232012` bytes | `PROJECT_PLAN.md §7` ke size lever order lagao |
| QEMU nahi chalta | `qemu-desktop` + `edk2-ovmf` install karo, `/dev/kvm` check karo |
| `pacman` signature error | `pacman -Syu archlinux-keyring && pacman-key --populate archlinux` |

---

## 10. Final honest status

| Kaam | Kaun karega |
|---|---|
| Source + tooling + validators | ✅ ho gaya (repo me, 40/40 offline gates PASS) |
| Offline release key + signed repo | ⚠️ **AAP** (air-gapped) |
| Real ISO + signatures | ⚠️ **AAP** (real Arch host / Docker / CI) |
| QEMU + hardware QA (40/40) | ⚠️ **AAP** |
| Tag / publish / announce | ⚠️ **AAP** (`docs/RELEASE_GUIDE.md`) |

Pura detail: `docs/BUILD_RELEASE_ISO.md`, `docs/ISO_BUILD_GUIDE.md`,
`docs/REPO_GUIDE.md §3`, `docs/RELEASE_GUIDE.md`, `docs/TESTING_CHECKLIST.md`.
