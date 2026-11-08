# ar0x Release Guide — Phase 12 (COMPLETE)

**Target:** tag `v0.1.0` on `ar0x1/ar0xOS`, 6 signed artifacts, primary host
GitHub Releases, secondary mirror via `rsync`, DistroWatch submission draft,
announcement + roadmap.
**Status:** ✅ release configuration, `README.md`, `CHANGELOG.md`, all 4 release
documents, `tools/prepare-release.sh`, `tools/lib/ar0x_release.py`, ADR-028 and
RISK-054 COMPLETE. ⚠️ **NOTHING was tagged, uploaded, announced or submitted.**

> ⚠️ **RISK-054 (HIGH):** no tag, GitHub Release, mirror upload, announcement
> or DistroWatch email exists. The release key is `PENDING-KEYGEN`
> (`config/repo/RELEASE_KEY_FINGERPRINT`), the signed `[ar0x]` db does not
> exist, and `docs/TESTING_CHECKLIST.md` is **0/40**. `--publish` is
> **print-only** and NEVER uploads.
>
> ⚠️ **RISK-053 / RISK-048 / RISK-051 (CRITICAL):** no ISO was built, booted,
> hashed or signed; `calamares` + `ar0x-meta` are still absent from
> `config/packages.x86_64`. Do NOT tag until Phase 11's MANUAL chain completes.
>
> ⚠️ **RISK-050:** `repo.ar0x.dev` and all 5 `AR0X_URL_*` endpoints are
> RESERVED. Provision DNS + TLS and verify with `curl -IL` before announcing.
>
> ⚠️ **RISK-015 / RISK-051:** never sign before the final ISO is written, never
> commit `*.gpg`/`*.asc`/`*.sig`/`SHA256SUMS`, never publish a fingerprint only
> in the release notes — publish it OUT OF BAND in `README.md`.

---

## 1. Deliverables

| Canonical source | Role |
|---|---|
| `config/release/release-options.conf` | 21 sourced pins: tag, title, exact 6-member artifact set, hosts, FPR path, EOL |
| `README.md` | project front page, status, verification commands, FPR placeholder, docs index |
| `CHANGELOG.md` | `0.1.0` release-notes TEMPLATE (explicit UNRELEASED banner) |
| `docs/ANNOUNCEMENT.md` | announcement template with `{{PLACEHOLDER}}` fields |
| `docs/DISTROWATCH.md` | submission email draft with the **4 required fields** |
| `docs/ROADMAP.md` | v0.1.x / v0.2 / v1.0 roadmap template |
| `docs/RELEASE_GUIDE.md` | this document |
| `tools/prepare-release.sh` | `--check/--sync/--self-test/--preflight/--publish` (print-only) |
| `tools/lib/ar0x_release.py` | pure-stdlib validator + 8 negative mutation tests + REAL artifact-set assembly |

`--sync` stages a disposable `build/release-prefix/` (gitignored). Derived
artifacts (`*.iso`, `SHA256SUMS*`, `*.sig`, `packages.lock`, `*.gpg`) stay in
`/opt/ar0x-build/out/` and are **never** committed (ADR-027/028).

---

## 2. ⚠️ MANUAL pre-publication gates (in this exact order)

1. **Phase 9 keygen** on an AIR-GAPPED host:
   `sudo AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen`; commit the
   40-hex FPR, publish it out of band, then `--sync` → `--build` → `--sign`
   → `--verify`. (RISK-051)
2. **Publish the signed `[ar0x]` db**; provision DNS + TLS for
   `repo.ar0x.dev`; `pacman-key --init` + `--populate ar0x` on a test host.
3. **Add `calamares` + `ar0x-meta`** to `config/packages.x86_64` and re-run
   `bootstrap.sh --sync` (Phase 11 gate).
4. **Build the ISO** on a real Arch host:
   `sudo AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build` (≤ `2362232012`
   bytes, `SOURCE_DATE_EPOCH` from `2026/11/01`). (RISK-053)
5. **Checksums + signatures**:
   `./tools/checksum.sh --create` → `AR0X_CONFIRM_SIGN=yes ./tools/checksum.sh --sign`
   → `./tools/checksum.sh --verify`. (RISK-015)
6. **QA:** all **40** items of `docs/TESTING_CHECKLIST.md` PASS (**100%**),
   QEMU BIOS + UEFI, disposable-qcow2 install → reboot → `ar0x-welcome`,
   real-hardware WiFi/BT/audio/GPU, VBox/VMware. (RISK-004/052/053)
7. **`curl -IL`** all 5 `AR0X_URL_*` endpoints + the reserved mirror host.
8. **Verify a FRESH download**:
   `gpg --verify SHA256SUMS.sig SHA256SUMS` → `sha256sum -c SHA256SUMS` →
   `gpg --verify <iso>.sig <iso>`.
9. Replace EVERY `{{PLACEHOLDER}}` in `docs/ANNOUNCEMENT.md` and
   `docs/DISTROWATCH.md`; remove their DRAFT banners; move the `CHANGELOG.md`
   `UNRELEASED` entry to a dated release.

---

## 3. Exact artifact set (6 files, `PROJECT_PLAN.md §11`)

```
ar0x-0.1.0-x86_64.iso
SHA256SUMS
SHA256SUMS.sig
ar0x-0.1.0-x86_64.iso.sig
CHANGELOG.md
README.md
```

`ar0x_release.check_artifact_set()` asserts this EXACT set; a missing signature
or an extra untracked file FAILS. `packages.lock` is an extra build record in
`out/`, not part of the published six.

---

## 4. Publishing (MANUAL — `--publish` only PRINTS these)

```bash
# 4.1 Create and push an ANNOTATED tag FIRST (--verify-tag then checks it).
git tag -s v0.1.0 -m 'ar0x 0.1.0 (ar0x root)' -u <RELEASE_FINGERPRINT_40HEX>
git push origin v0.1.0

# 4.2 GitHub Releases (primary host). --verify-tag aborts if the tag is absent.
gh release create v0.1.0 \
    --repo ar0x1/ar0xOS --title 'ar0x 0.1.0 (ar0x root)' \
    --verify-tag --notes-file out/CHANGELOG.md \
    out/ar0x-0.1.0-x86_64.iso \
    out/SHA256SUMS out/SHA256SUMS.sig \
    out/ar0x-0.1.0-x86_64.iso.sig \
    out/CHANGELOG.md out/README.md

# 4.3 Secondary mirror (own server), then SourceForge / OSDN.
rsync -av --checksum --partial out/ \
    user@mirror:/srv/ar0x/releases/0.1.0/

# 4.4 Publish the signed [ar0x] repo (see docs/REPO_GUIDE.md §3.4).
rsync -av --delete build/repo-publish/x86_64/ \
    user@mirror:/srv/repo/x86_64/
```

`--verify-tag`, `--notes-file`, `--title` and an explicit asset list are
deliberate: `--generate-notes` alone would silently create a tag from the
default branch. Source: `gh-release-create(1)`.

After upload, re-download from the public URL and repeat §2 step 8.

---

## 5. Distribution & communication

| Channel | Deliverable | Gate |
|---|---|---|
| GitHub Releases `v0.1.0` | 6 artifacts | `--verify-tag`, fresh-download verification |
| `rsync` mirror | same 6 + signed `[ar0x]` db | DNS + TLS for `repo.ar0x.dev` |
| SourceForge / OSDN | same 6 | external accounts, MANUAL |
| DistroWatch | `docs/DISTROWATCH.md` email: **name, website, description incl. Arch base, direct ISO URL** | waiting list; mentioned in DistroWatch Weekly; no reply expected |
| Announcement | `docs/ANNOUNCEMENT.md` | all `{{PLACEHOLDER}}` replaced |
| Roadmap | `docs/ROADMAP.md` | post-release planning only |

DistroWatch source: <https://distrowatch.com/dwres.php?resource=submit>
(re-check the live policy and recipient before sending).

---

## 6. EOL, rollback & key compromise

- **EOL:** `stable` ISO supported until the next stable release + 1 month;
  cadence quarterly stable ISOs with continuous `testing` packages.
- **Bad ISO:** delete the release assets (do NOT delete the tag), rebuild,
  re-sign and re-upload; NEVER edit `SHA256SUMS` in place.
- **Key compromise (RISK-051):** add the FPR to `ar0x-revoked`, revoke the
  subkey, re-sign EVERY package + db + ISO with a new key, republish the FPR
  out of band, and publish a security notice. `ar0x-keyring` ships `ar0x-revoked`.

---

## 7. Tradeoffs (ADR-028)

| Decision | Alternative rejected | Why |
|---|---|---|
| `--publish` is PRINT-ONLY | real `gh release create`/`rsync` in the driver | no sandbox has accounts, a signed ISO or a tag; an accidental upload would be irreversible |
| Exact 6-artifact set + `--verify-tag` | `--generate-notes` + glob upload | globs can silently omit a `.sig`; auto-tagging bypasses review |
| Templates with `{{PLACEHOLDER}}` + DRAFT banners | finished prose with invented SHA256/FPR | no fake claims; RISK-054 |
| FPR published out of band in `README.md` | FPR only in release notes | an attacker controlling the release could substitute both |
| `config/release/` canonical + gitignored prefix | a second copy in `archiso/airootfs` | ADR-024 one owner per path |

---

## 8. Verification actually performed here

| Gate | Result |
|---|---|
| `./tools/prepare-release.sh --check/--sync/--self-test/--preflight` | ✅ PASS |
| `python3 tools/lib/ar0x_release.py . --self-test` | ✅ 8 negative mutations + REAL artifact-set assembly |
| `./tools/validate-versions.sh` (incl. §7m), full Phase 1–11 gate chain | ✅ PASS |
| `bash -n`, Python AST, `git diff --check`, `--sync` idempotency | ✅ PASS |

⚠️ NOT performed: `git tag`, `gh release create`, `rsync`, `gpg --detach-sign`
on real artifacts, `curl -IL`, DistroWatch email, announcement, any ISO build.

---

## 9. Companion documents

`PROJECT_PLAN.md §11/§15/§16` · `docs/ISO_BUILD_GUIDE.md` ·
`docs/TESTING_CHECKLIST.md` · `docs/REPO_GUIDE.md §3` ·
`docs/INSTALLER_FLOW.md` · `docs/architecture/DECISIONS.md` (ADR-028) ·
`docs/architecture/RISK_REGISTER.md` (RISK-050/051/053/**054**).
