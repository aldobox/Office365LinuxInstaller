# CIRO Estate Standard

Single authoritative engineering standard for all CIRO estate repositories. Every clause is law. Clauses are numbered `EST-n` and cited by CI gates, reviews and audits.

---

## 1. Versioning

**EST-1:** The git tag is the single source of truth for the version of every component. No other version exists.

**EST-2:** No hand-written version literal may appear anywhere in any repository — not in source, config, docs, badges, installers or scripts. Violations are build failures (Gate B, EST-22).

**EST-3:** Per-stack version mechanics are fixed as follows:

- **Python** (CiroOS, ciro-ai-gateway): `setuptools-scm`; `pyproject.toml` declares `dynamic = ["version"]`; runtime code reads the version via `importlib.metadata.version(<dist>)`. No `__version__ = "..."` literals.
- **Android** (CiroDroid): the `com.palantir.git-version` plugin; `versionName = gitVersion()`; `versionCode` derives from the commit count (monotonic; an offset may be applied for Play-store continuity by owner decision only). APK artefacts are named `cirodroid-<version>.apk`.
- **Electron** (CiroDevTool): `package.json` carries `"version": "0.0.0-dev"` in-repo; CI stamps the tag version into the artefact at release time. `install.sh` must use `releases/latest/download/...` URLs only and must never contain a version string.
- **Shell** (Office365LinuxInstaller): `VERSION="$(git describe --tags --always || cat VERSION)"`. The `VERSION` file is a generated release asset, never committed by hand.

**EST-4:** Badges: shields `github/v/release` endpoint badges only. Static version badges are banned.

**EST-5:** `CHANGELOG.md` is generated (release-please), never hand-edited. Changes enter exclusively as fragments at `changelog.d/<pr>.<type>.md`, where `<type>` is one of: `feat | fix | perf | refactor | docs | chore | hotfix`.

---

## 2. Release flow

**EST-6:** Work happens on `develop`. PRs are squash-merged only. Every PR title must be a conventional commit matching:

```
^(feat|fix|perf|refactor|docs|chore|hotfix)(\([a-z0-9_-]+\))?!?: .+
```

**EST-7:** release-please opens a Release PR proposing the exact next version and the generated changelog. Merging the Release PR creates the tag.

**EST-8:** The tag triggers one CI workflow that: builds every artefact with the version injected at build time, generates the CHANGELOG, assembles the signed update-manifest, and publishes the GitHub Release.

**EST-9:** Each release carries one update-manifest (v1), stored in-repo at `releases/manifests/<tag>.yaml` (human audit) and attached to the release as `update-manifest.yaml` (machine source of truth). Schema summary:

```yaml
version: 1
tag: <tag>
components:          # changed components
  - name: <component>
    url: <artefact-url>
    sha256: <hex>
migrations:          # ordered, idempotent; executed in sequence
  - id: <slug>
    run: <command>
    verify: <command>     # must succeed or migration fails
docs:
  deltas:            # human-facing doc changes
    - <path-or-summary>
health_check: <command>   # must succeed post-apply
rollback:
  - <command>             # executed on health-check failure
signature: <ed25519-signature-over-canonical-manifest>
```

**EST-10:** Label rules: PRs that change runtime infrastructure must carry the matching label — `migration:redis`, `migration:env`, `migration:restart`, `migration:apk-reinstall`, `docs:delta`. A label without a corresponding migration/docs fragment fails the release; touching infra files (Redis, env, service units, APK packaging) without the label fails the PR.

---

## 3. CI gates — the four laws

**EST-21 (Gate A):** A code change without a `changelog.d/<pr>.<type>.md` fragment fails CI.

**EST-22 (Gate B):** A hardcoded version literal outside the per-repo allowlist fails CI (`tools/version_lint.py`).

**EST-23 (Gate C):** Every referenced file must exist: `shellcheck -x` for sourced scripts, `tsc` for TS projects, markdown link checking for docs. Failures fail CI.

**EST-24 (Gate D):** No local-machine artefacts in any diff. The grep list includes: `/home/<user>/`, `/Users/`, private IPs (10/8, 172.16/12, 192.168/16), `localhost` outside tests and examples, `.env`, `*.bak`, secret-shaped strings, `OPENCODE_*` leftovers. Additionally `git ls-files -ci --exclude-standard` must be empty.

**EST-25 (Escape hatch):** The owner-only `hotfix` label waives Gates A and B only — never C or D. Every bypass is audited into the CHANGELOG and a backfill issue is opened automatically.

---

## 4. Repository layout standard

**EST-31:** Every estate repository ships:

- `changelog.d/` — change fragments (EST-5)
- `.githooks/pre-push` — local gate run before push (defence-in-depth)
- `tools/version_lint.py` — Gate B enforcement
- `scripts/gates.sh` — runs Gates A–D locally and in CI
- `docs/ESTATE-STANDARDS.md` — this document
- `CONTRIBUTING.md` — points at this standard

**EST-32 (Branch doctrine):** `develop` → `main` via PR. Both branches are protected: PR-only merges, required gates, squash-only, no force-push. Bypass rights are owner-only; automation tokens must structurally lack bypass.

---

## 5. Scripts conventions

**EST-41:** Every service repository ships `scripts/status-check` performing health verification of the deployed service.

**EST-42:** Every service repository ships an update entry point — `install.sh --update` or `ciro-update` — which consumes the update-manifest (snapshot → migrate → health-check → auto-rollback).

**EST-43:** Installers and update scripts never hardcode versions or IP addresses. Artefacts are resolved via `releases/latest/download` or the manifest; hosts are configured via environment/config, not literals.

---

## 6. Per-repo adoption

| Repo | Branch | Adopts now (Stage 2) | Adopts later |
|---|---|---|---|
| CiroOS | develop | Standard doc, changelog.d, gates A–D, setuptools-scm versioning, status-check | release-please workflow, manifest generation (pending workflow-scope push) |
| ciro-ai-gateway | develop | Standard doc, changelog.d, gates A–D, setuptools-scm versioning, status-check | release-please workflow, `install.sh --update` manifest applier (pending workflow-scope push) |
| CiroDroid | develop | Standard doc, changelog.d, gates A–D, palantir git-version, commit-count versionCode | release-please workflow, WorkManager manifest updater (pending workflow-scope push) |
| CiroDevTool | develop | Standard doc, changelog.d, gates A–D, `0.0.0-dev` + CI stamping, latest/download install.sh | release-please workflow, electron-updater mirror (pending workflow-scope push) |
| Office365LinuxInstaller | main | Standard doc, changelog.d, gates A–D, git-describe versioning, status-check | release-please workflow, manifest applier (pending workflow-scope push) |

---

CIRO Estate Standard v1.0 — 2026-07-28. Applies to all estate repositories. Changes require owner decision recorded in CHANGELOG.
