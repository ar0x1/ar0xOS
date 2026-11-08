# /home/user/ar0xOS/ci/workflows/ — Phase 9 CI

| Workflow | Triggers | Secrets | Purpose |
|---|---|---|---|
| `validate-packages.yml` | push, **pull_request (fork-safe)**, manual | **NONE** | the whole read-only validator chain + `ar0x_repo.py --self-test` + private-key scan |
| `build-packages.yml` | push, **pull_request (fork-safe)**, manual | **NONE** | `archlinux:base-devel` container, non-root `builder`, `makepkg --nodeps` ×8, `namcap`, `shellcheck`, UNSIGNED local db smoke test, artifact upload |
| `release.yml` | `workflow_dispatch` on a protected ref, or a `v*` tag | `AR0X_RELEASE_GPG_KEY`, `AR0X_GPG_PASSPHRASE`, `AR0X_RELEASE_FPR` | detached-sign every package, `repo-add -s -v --include-sigs`, `SHA256SUMS.sig`, GitHub Release |
| `build-iso.yml` | **`workflow_dispatch` only** (post-merge) | same 3 signing secrets | privileged Arch container → signed `[ar0x]` repo → `build-release.sh --run` → **real ISO** + 6 artifacts as a workflow artifact; **NEVER** a GitHub Release |

⚠️ **GitHub Actions reads ONLY `.github/workflows/`**. Every YAML in this
directory is a validated canonical template; the **live dispatchable** copy of
the ISO workflow is `.github/workflows/build-iso.yml`, kept byte-identical by
`tools/validate-versions.sh` and `tools/lib/ar0x_build_release.py`.
⚠️ **Post-plan ISO build:** `build-iso.yml` is `workflow_dispatch`-only and has an
explicit fork guard. After the live copy is on `main`, the workflow can be
dispatched (once the 3 secrets are configured). Standard `ubuntu-latest` has only
~14 GB SSD — the ISO build needs >= 40 GiB free, so dispatch with the `runner`
input set to a self-hosted or larger runner. It builds the ISO on GitHub's Ubuntu
runner inside the same privileged `archlinux:base-devel` container as
`docker/Dockerfile` (`mkarchiso` needs `--privileged`, RISK-016). It NEVER tags,
releases, mirrors or announces — that stays in `docs/RELEASE_GUIDE.md §4`.
QEMU boots, the 40/40 checklist and real-hardware QA remain MANUAL
(RISK-004/052/053/054). Full recipes: `docs/BUILD_RELEASE_ISO.md`.

⚠️ **RISK-051:** `release.yml` is NEVER triggered by `pull_request` and has an
explicit fork guard in its job `if:`. A private key must never be available to a
workflow that runs forked PR code. The offline master release key is generated
by NON-ROOT `AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen` and never
enters Git. ⚠️ Using the CI path does put that private key into a GitHub Secret,
which is NOT air-gapped — for a real public release, keep the master key offline
and build on an air-gapped Arch host instead.

⚠️ `makepkg --nodeps` is deliberate: `ar0x-welcome` depends on `ar0x-info` and
`ar0x-update`, and `ar0x-meta` depends on all seven others, none of which exist
in any repository until this job has built them. All eight packages are
`arch=('any')` data/CLI packages with no compile step.

⚠️ `ar0x-keyring` is SKIPPED in unsigned PR builds because
`packages/ar0x-keyring/ar0x-public-key.asc` is a MANUAL keygen artifact.

Full procedure: `/home/user/ar0xOS/docs/REPO_GUIDE.md`.
