# ar0x ISO banana aur use karna — Quickstart (Hinglish)

> ⚠️ **Sach pehle:** is repo me **koi ISO file nahi hai**. Ye sandbox (Arena) me
> ISO banana **namumkin** hai — yahan root nahi, `mkarchiso`/`pacman`/`gpg`
> nahi, aur Arch mirror blocked hai. Neeche wale steps **aapki apni machine**
> par chalane hain. `docs/BUILD_RELEASE_ISO.md` = pura English guide.

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
