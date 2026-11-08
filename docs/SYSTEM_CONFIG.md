# ar0x — Phase 5: Core System Configuration

> Companion to [`tools/configure-system.sh`](../tools/configure-system.sh).
> Verified on 2026-11-07 against systemd 262.1, NetworkManager, PipeWire 1.6.10,
> WirePlumber 0.5+, nftables, AppArmor and the frozen `linux-lts 6.18.59-1`.

---

## ⚠️ Warnings repeated at the start of Phase 5

| ID | Warning |
|---|---|
| **RISK-008** | AppArmor v0.1 runs in **COMPLAIN** mode. Enforcing profiles break xdg-desktop-portal, PipeWire and GPU drivers before tuning. |
| **RISK-014** | Sysctls are **HOST-KERNEL GLOBALS**. Never run `sysctl --system` inside a build chroot. |
| **RISK-033** | The **LIVE ISO has passwordless `root` + `ar0x`**. Never copy that `/etc/shadow` to an installed system. |
| **RISK-001** | Still zero kernel patches — Phase 4 policy unchanged. |
| **RISK-007** | Secure Boot / MOK enrollment remains manual. |

---

## 1. What Phase 5 delivers

`config/system/**` maps **1:1 to `/etc/**`** (`BUILD_LAYOUT.md` §4). `tools/bootstrap.sh`
already overlays it into the disposable staged profile at build time;
`tools/configure-system.sh --sync` additionally materialises the files under
`archiso/airootfs/etc/**` so every target path exists as a complete, inspectable file.

| Source (full path) | Target (full path) | What it does |
|---|---|---|
| `/home/user/ar0xOS/config/system/hostname` | `/etc/hostname` | `ar0x-live` |
| `…/config/system/hosts` | `/etc/hosts` | localhost + `127.0.1.1` |
| `…/config/system/locale.conf` | `/etc/locale.conf` | `LANG=en_US.UTF-8` + all `LC_*` |
| `…/config/system/locale.gen` | `/etc/locale.gen` | only `en_US.UTF-8 UTF-8` |
| `…/config/system/vconsole.conf` | `/etc/vconsole.conf` | `KEYMAP=us` (VT only) |
| `…/config/system/localtime` | `/etc/localtime` | **symlink** → `/usr/share/zoneinfo/UTC` |
| `…/config/system/passwd` | `/etc/passwd` | root + `ar0x` (UID 1000, zsh) |
| `…/config/system/shadow` | `/etc/shadow` | ⚠️ empty passwords, **LIVE ONLY** |
| `…/config/system/sysusers.d/ar0x-live.conf` | `/etc/sysusers.d/ar0x-live.conf` | `m` lines → wheel/audio/video/render/input/storage/users |
| `…/config/system/sudoers.d/10-ar0x-wheel` | `/etc/sudoers.d/10-ar0x-wheel` | `%wheel ALL=(ALL:ALL) ALL`, mode **0440** |
| `…/config/system/security/limits.d/90-ar0x-audio.conf` | `/etc/security/limits.d/90-ar0x-audio.conf` | low-latency audio opt-in |
| `…/config/system/polkit-1/rules.d/10-ar0x.rules` | `/etc/polkit-1/rules.d/10-ar0x.rules` | wheel may manage NM / mount media |
| `…/config/system/NetworkManager/conf.d/10-ar0x.conf` | `/etc/NetworkManager/conf.d/10-ar0x.conf` | keyfile, internal DHCP, connectivity probe OFF, MAC randomisation |
| `…/config/system/pipewire/pipewire.conf.d/10-ar0x.conf` | `/etc/pipewire/pipewire.conf.d/10-ar0x.conf` | 48 kHz, quantum 1024, resample quality 4 |
| `…/config/system/pipewire/wireplumber.conf.d/10-ar0x.conf` | `/etc/pipewire/wireplumber.conf.d/10-ar0x.conf` | ⚠️ **WP 0.5+ path** — Bluetooth codecs |
| `…/config/system/environment.d/10-ar0x-wayland.conf` | `/etc/environment.d/10-ar0x-wayland.conf` | Wayland env for systemd user manager |
| `…/config/system/profile.d/ar0x-wayland.sh` | `/etc/profile.d/ar0x-wayland.sh` | POSIX login-shell fallback |
| `…/config/system/nftables.conf` | `/etc/nftables.conf` | `inet` table, default-drop inbound |
| `…/config/system/sysctl.d/50-ar0x-security.conf` | `/etc/sysctl.d/50-ar0x-security.conf` | balanced kernel hardening |
| `…/config/system/sysctl.d/60-ar0x-network.conf` | `/etc/sysctl.d/60-ar0x-network.conf` | IPv4/IPv6 network hardening |
| `…/config/system/systemd/journald.conf.d/10-ar0x.conf` | `/etc/systemd/journald.conf.d/10-ar0x.conf` | persistent, 512 MiB cap, 1 month |
| `…/config/system/systemd/logind.conf.d/10-ar0x.conf` | `/etc/systemd/logind.conf.d/10-ar0x.conf` | power keys, `IdleAction=ignore` |
| `…/config/system/systemd/system-preset/50-ar0x.preset` | `/etc/systemd/system-preset/50-ar0x.preset` | single owner of enabled/disabled units |
| `…/config/system/systemd/system/apparmor.service.d/10-ar0x-complain.conf` | `/etc/systemd/system/apparmor.service.d/10-ar0x-complain.conf` | forces complain mode after profile load |
| `/home/user/ar0xOS/config/pacman.conf.installed` | `/etc/pacman.conf` | **ROLLING** installed config + signed `[ar0x]` |
| `/home/user/ar0xOS/config/repo/pacman.conf.ar0x-entry` | *(Phase 9 snippet)* | byte-identical `[ar0x]` block |
| `/home/user/ar0xOS/tools/configure-system.sh` | — | `--check / --sync / --apply` |
| `/home/user/ar0xOS/docs/SYSTEM_CONFIG.md` | — | this guide |

Also updated: `config/packages.x86_64` (**+`tzdata`, +`rtkit`** — `apparmor`,
`nftables`, `sudo` and `polkit` were already in the Phase 3 base set; both
validators now fail on duplicate package lines), `config/default/grub`,
`archiso/profiledef.sh`, `archiso/grub/grub.cfg`, `archiso/syslinux/syslinux.cfg`
(all gain `apparmor=1 security=apparmor`), and `archiso/profiledef.sh`
`file_permissions` (sudoers drop-in `0:0:440`). The empty Phase 1
`config/system/apparmor/` skeleton was removed: ar0x v0.1 ships **no** custom
AppArmor profiles, using upstream profiles in complain mode instead.

---

## 2. Exact commands

```bash
cd ~/ar0xOS

# --- Read-only validation (NO root; runs in this sandbox) ---------------------
./tools/configure-system.sh --check

# --- Materialise config/system/** in the archiso profile (NO root) ------------
./tools/configure-system.sh --sync
./tools/bootstrap.sh --sync          # keeps packages.x86_64 in sync

# --- Apply inside the airootfs (⚠️ MANUAL, ROOT) -----------------------------
sudo ./tools/bootstrap.sh --iso-only          # creates work/x86_64/airootfs
sudo ./tools/configure-system.sh --apply

# --- Host-side syntax checks (⚠️ MANUAL, on a real Arch host) -----------------
nft -c -f config/system/nftables.conf
visudo -cf config/system/sudoers.d/10-ar0x-wheel
```

`--apply` expands to (all executed inside `arch-chroot /opt/ar0x-build/work/x86_64/airootfs`):

```bash
locale-gen
systemctl preset-all                        # offline symlink operations only
nft -c -f /etc/nftables.conf                # SYNTAX CHECK ONLY
visudo -cf /etc/sudoers.d/10-ar0x-wheel     # SYNTAX CHECK ONLY
```

### ⚠️ HOST-KERNEL SAFETY — the single most important operational rule

`sysctl --system` and `nft -f /etc/nftables.conf` must **never** be run inside a
chroot. Sysctls and nftables rulesets are globals of the **running host kernel**,
not the chroot's filesystem; running them during a build would silently
reconfigure (or firewall off) the build machine. `--apply` uses only the
`-c` (check) forms. The real settings are applied by `systemd-sysctl.service`
and `nftables.service` on the **first boot of the installed system**.

---

## 3. Key configs reproduced in full

### 3.1 `/etc/nftables.conf`

```nft
#!/usr/bin/nft -f
table inet ar0x {
    chain input {
        type filter hook input priority filter; policy drop;

        iif "lo" accept comment "loopback"
        ct state established,related accept comment "reply traffic"
        ct state invalid drop

        udp sport 67 udp dport 68 accept comment "DHCPv4 client"
        udp dport 546 ip6 saddr fe80::/10 accept comment "DHCPv6 client"

        icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } accept
        icmpv6 type { echo-request, destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, nd-router-solicit } accept

        # udp dport { 5353, 5355 } accept comment "mDNS / LLMNR"
        # tcp dport 22 ct state new limit rate 10/minute burst 5 packets accept

        counter comment "count of dropped inbound packets"
    }
    chain forward { type filter hook forward priority filter; policy drop; }
    chain output  { type filter hook output  priority filter; policy accept; }
}
```

**Default-deny inbound**, allow-all outbound. SSH is **closed** by default —
`openssh` is installed for outbound use. Uncomment the rate-limited rule to open
port 22. `policy drop` on `forward` because containers/VMs are a v0.2 feature.

### 3.2 `/etc/sysctl.d/50-ar0x-security.conf` (decisions, not just values)

```ini
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 2          # 3 would break perf/bpftrace for devs
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
vm.unprivileged_userfaultfd = 0
kernel.yama.ptrace_scope = 1            # 2 would break gdb/strace
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
kernel.unprivileged_userns_clone = 1    # ⚠️ KEPT ENABLED — see below
```

**`kernel.unprivileged_userns_clone = 1` is deliberate.** Phase 4 found that
Arch's `6.18.59-1` packaging tag carries patch `0001-add-sysctl-to-allow-disabling-unprivileged-CLONE_NEW.patch`,
which *adds* this sysctl (default `1`). Setting it to `0` would harden the kernel
but break Flatpak, rootless Podman/Docker/BuildKit, Chromium's non-root renderer
sandbox and bubblewrap — all core developer tools. ar0x pins it to `1` and lists
the rejected paranoid values as comments in the file.

### 3.3 `/etc/pacman.conf` (installed system — ROLLING)

```ini
[options]
Architecture = x86_64
HoldPkg      = pacman glibc
SigLevel     = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5
Color
CheckSpace
VerbosePkgLists

[ar0x]
SigLevel = Required
Server = https://repo.ar0x.dev/$arch

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
```

⚠️ **RISK-006:** this file must **never** contain `archive.archlinux.org`. That
belongs only in `config/pacman.conf.build` (the frozen build config `mkarchiso`
uses). Both `validate-versions.sh` and `configure-system.sh --check` assert the
separation. `/etc/pacman.d/mirrorlist` is generated by `reflector` during the
Phase 10 install.

⚠️ **MANUAL (Phase 9/12):** `repo.ar0x.dev` is the reserved release endpoint.
`tools/setup-repo.sh` builds the signed db with `repo-add -s`; Phase 12 publishes
it. Until then `pacman -Syu` will report one failed sync — **do not disable
signature checking to work around it**.

### 3.4 `/etc/shadow` — LIVE ISO ONLY

```
root::14871::::::
ar0x::14871::::::
```

Empty password fields = passwordless login. This is exactly the archiso releng
pattern (`root::14871::::::`), which is why the live installer can run without a
password. **It is never installed on a target disk**; Calamares (Phase 10) creates
a real user with a hashed password. Mode **0400**, asserted by
`archiso/profiledef.sh` `file_permissions`.

### 3.5 `/etc/systemd/system-preset/50-ar0x.preset` (excerpt)

```
enable NetworkManager.service
enable nftables.service
enable apparmor.service
enable bluetooth.service
enable systemd-timesyncd.service
disable systemd-networkd.service
disable systemd-networkd-wait-online.service
disable dhcpcd.service
```

**NetworkManager vs systemd-networkd:** the user asked for one of them. Phase 1
chose NetworkManager (best WiFi/roaming + GUI integration + Calamares support).
`systemd-networkd` and `dhcpcd` are explicitly **disabled** — two DHCP clients
fighting over one link is a classic broken-network bug.

### 3.6 AppArmor

Boot params added to **four** places (live `profiledef.sh`, installed
`config/default/grub`, and both GRUB and syslinux FAILSAFE/text entries):

```
apparmor=1 security=apparmor
```

`apparmor.service` is enabled in the preset. The drop-in
`/etc/systemd/system/apparmor.service.d/10-ar0x-complain.conf` runs
`aa-complain /etc/apparmor.d/*` (falling back to `apparmor_parser -C -r`) with a
`-` prefix so a missing tool is non-fatal. `CONFIG_AUDIT=y` and
`CONFIG_SECURITY_APPARMOR` are already asserted in Phase 4's kernel audit
fragment. Graduating to enforce mode is a **v0.2 ADR**.

### 3.7 WirePlumber path correction

⚠️ **Phase 5 correction:** WirePlumber **0.5+** reads its fragments from the
**PipeWire** config directory: `/etc/pipewire/wireplumber.conf.d/*.conf`. The
0.4 path `/etc/wireplumber/wireplumber.conf.d/` is legacy and silently ignored on
our 2026/11/01 snapshot. The Phase 1 skeleton dir `config/system/wireplumber/`
was therefore **removed**; the real fragment is at
`config/system/pipewire/wireplumber.conf.d/10-ar0x.conf`.
`configure-system.sh --check` fails if the legacy dir reappears.

---

## 4. Tradeoffs

| Decision | Alternatives | Tradeoff accepted |
|---|---|---|
| NetworkManager | systemd-networkd, dhcpcd | NM wins on WiFi/roaming + GUI; must explicitly disable the other two |
| Connectivity probe OFF | ON (captive-portal detection) | Privacy; laptops may need to re-enable manually |
| PipeWire fragments | copy whole upstream config | Fragments survive package upgrades |
| WirePlumber 0.5+ path | legacy `/etc/wireplumber/` | New path is correct for frozen snapshot |
| Wayland env without `GDK_BACKEND` | force `GDK_BACKEND=wayland` | Forcing breaks GTK apps under XWayland |
| Default-drop inbound nftables | default-accept | Developer services need explicit rules; SSH closed by default |
| Balanced sysctl | paranoid hardening | `perf`, `gdb`, Flatpak and rootless containers keep working |
| `unprivileged_userns_clone=1` | `0` (hardened) | Developer toolchain compatibility over kernel attack-surface reduction |
| AppArmor **complain** | enforce | No broken portals/GPU drivers in v0.1; logs instead of blocks |
| `journald` persistent, 512 MiB | volatile / unlimited | Bounded disk use, still debuggable |
| Passwordless live user | hashed live password | Matches archiso releng; installer runs without auth |
| `PRESETS=('default')` (Phase 4) | + fallback initramfs | ISO size; FAILSAFE entries are the recovery path |

---

## 5. Manual-intervention register (Phase 5)

| # | Action | Why manual |
|---|---|---|
| 1 | `sudo ./tools/configure-system.sh --apply` | Needs root + an existing airootfs |
| 2 | `nft -c -f` and `visudo -cf` on a real Arch host | Tools absent in this sandbox |
| 3 | Publish `repo.ar0x.dev` (Phase 9 signs, Phase 12 uploads) | DNS/mirror decision; do not weaken `SigLevel` |
| 4 | Choose `LANG`/`KEYMAP`/`TZ` if not `en_US` / `us` / `UTC` | User preference |
| 5 | Uncomment the SSH nftables rule if inbound SSH is wanted | Exposes a port |
| 6 | Graduate AppArmor to enforce (v0.2 ADR) | Needs profile tuning + QA |
| 7 | Visual Wayland/WiFi/audio QA (Phase 11) | Needs KVM/real hardware |

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No IP address after boot | two DHCP clients | Verify `systemd-networkd.service` and `dhcpcd.service` are disabled via `systemctl preset-all` |
| `pacman -Syu` fails only on `[ar0x]` | `repo.ar0x.dev` not published yet | Phase 9/12; **never** set `SigLevel = Optional TrustAll` on the installed repo |
| `pacman` pinned to 2026-11-01 | RISK-006: frozen config shipped | Ensure `archiso/airootfs/etc/pacman.conf` is `config/pacman.conf.installed`; build uses `archiso/pacman.conf` |
| `locale: Cannot set LC_ALL` | `locale-gen` not run | `sudo ./tools/configure-system.sh --apply` |
| `sudo: /etc/sudoers.d/10-ar0x-wheel is world writable` | wrong mode | `file_permissions` asserts `0:0:440`; `--sync` chmods it |
| No audio device | WirePlumber fragment in legacy 0.4 dir | Use `/etc/pipewire/wireplumber.conf.d/`; `--check` fails on the legacy dir |
| GTK apps blank under XWayland | `GDK_BACKEND` forced globally | Removed; Hyprland sets session env in Phase 6 |
| Flatpak / rootless Podman fails | `unprivileged_userns_clone=0` | ar0x pins it to `1` |
| AppArmor breaks portals | enforce mode | ar0x v0.1 uses complain; `aa-status` to verify |
| Build machine firewalled off | `nft -f` or `sysctl --system` run inside a chroot | Never do this; use `nft -c -f` |
| `nft -c -f` syntax error | bad ruleset | Fix `config/system/nftables.conf`, re-run `--check` |

---

## 7. Phase 5 risks

| ID | Severity | Risk | Mitigation |
|---|---|---|---|
| **RISK-032** | **HIGH** | Frozen `pacman.conf.build` accidentally shipped as `/etc/pacman.conf` | RISK-006: two configs, two validators assert the split |
| **RISK-033** | ⚠️ **HIGH** | Passwordless `root`/`ar0x` on live ISO | Warned; never copied to target; Calamares creates hashed passwords |
| **RISK-034** | **HIGH** | `sysctl --system` / `nft -f` in chroot reconfigures the HOST kernel | `--apply` uses only `-c`/`-cf` checks; documented prominently |
| **RISK-035** | **MEDIUM** | Two DHCP clients (NM + networkd/dhcpcd) | Explicit `disable` lines in `50-ar0x.preset` |
| **RISK-036** | **MEDIUM** | `repo.ar0x.dev` not live → `[ar0x]` sync failure | Reserved endpoint documented; signature checking never weakened |
| **RISK-037** | **LOW** | WirePlumber 0.4 legacy path → silent config loss | Path corrected; `--check` fails if legacy dir reappears |
| **RISK-008** | **MEDIUM** | AppArmor enforce breaks portals | complain mode + service drop-in |
| **RISK-014** | **MEDIUM** | Over-aggressive sysctl breaks developer tools | Balanced values + documented rejected paranoid options |

---

## 8. Verification actually performed in the sandbox

```bash
bash -n tools/*.sh tools/lib/*.sh                 # 10 scripts
./tools/configure-system.sh --check               # ✅ PASSED (read-only)
./tools/configure-system.sh --sync                # byte-idempotent sync
./tools/bootstrap.sh --sync && ./tools/bootstrap.sh --check
./tools/build-kernel.sh --check && --self-test
./tools/validate-versions.sh                     # ✅ PASSED, no warnings
./tools/setup-build-env.sh --check
```

`locale-gen`, `systemctl preset-all`, `nft -c -f`, `visudo -cf`, `mkinitcpio -P`
and QEMU boot **cannot run here** (no root / no Arch userspace / no KVM). They
are the manual host steps in §2 and §5.
