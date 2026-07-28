#!/usr/bin/env bash
# gates.sh — run the CI gates locally (shell-flavoured).
# Usage: scripts/gates.sh [--quick] [--base <branch>]
set -uo pipefail

BASE="${BASE_BRANCH:-main}"
QUICK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --base)  BASE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# --- Gate A: changelog fragment ---------------------------------------------
echo "== Gate A: changelog fragment =="
if git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  CHANGED=$(git diff --name-only "$BASE"...HEAD 2>/dev/null || true)
else
  CHANGED=$(git diff --name-only HEAD~1 2>/dev/null || git ls-files)
fi
if echo "$CHANGED" | grep -qv '^changelog.d/\|^docs/\|README.md\|CHANGELOG.md' \
   && ! echo "$CHANGED" | grep -q '^changelog.d/[^/]*\.\(feat\|fix\|perf\|refactor\|docs\|chore\|hotfix\)\.md$'; then
  fail "Gate A: code change without a changelog.d/<pr>.<type>.md fragment"
else
  echo "Gate A passed."
fi

# --- Gate B: version lint ----------------------------------------------------
echo "== Gate B: version lint =="
if ! python3 tools/version_lint.py; then
  fail "Gate B: version lint failed"
fi

# --- Gate C: referenced files exist ------------------------------------------
echo "== Gate C: referenced files exist =="
# bash -n syntax check on every shell script
SH_FAIL=0
while IFS= read -r -d '' sh; do
  bash -n "$sh" || { echo "  bash -n failed: $sh"; SH_FAIL=1; }
done < <(git ls-files -z '*.sh')
[[ $SH_FAIL -eq 0 ]] || fail "Gate C: bash -n syntax check failed"
[[ $SH_FAIL -eq 0 ]] && echo "Gate C bash -n check passed."
# shellcheck -x for sourced/referenced scripts
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x $(git ls-files '*.sh') || fail "Gate C: shellcheck -x failed"
else
  echo "Gate C (shellcheck -x): skipped — shellcheck not installed (enforced in CI)."
fi
# Markdown link check: relative links must resolve
MD_FAIL=0
while IFS= read -r -d '' md; do
  dir=$(dirname "$md")
  while IFS= read -r link; do
    target="$dir/$link"
    [[ -e "$target" ]] || { echo "  broken link in $md: $link"; MD_FAIL=1; }
  done < <(grep -oP '\]\(\K[^)#]+(?=[)#])' "$md" | grep -v '^[a-z]*://' | sed 's/#.*//' | grep -v '^$' || true)
done < <(git ls-files -z '*.md')
[[ $MD_FAIL -eq 0 ]] || fail "Gate C: broken markdown links"
[[ $MD_FAIL -eq 0 ]] && echo "Gate C markdown link check passed."

# --- Gate D: no local-machine artefacts --------------------------------------
echo "== Gate D: local-machine artefacts =="
D_FAIL=0
grep -rnE '/home/[a-z_]+/|/Users/|\b10\.[0-9]+\.[0-9]+\.[0-9]+\b|\b172\.(1[6-9]|2[0-9]|3[01])\.|\b192\.168\.' \
  --exclude-dir=.git --exclude=gates.sh . && D_FAIL=1
if git ls-files | grep -qE '\.env$|\.bak$|\.bak\.'; then
  echo "  tracked .env or .bak artefact found"; D_FAIL=1
fi
if [[ -n $(git ls-files -ci --exclude-standard) ]]; then
  echo "  tracked files matched by .gitignore:"; git ls-files -ci --exclude-standard; D_FAIL=1
fi
[[ $D_FAIL -eq 0 ]] || fail "Gate D: local-machine artefacts present"
[[ $D_FAIL -eq 0 ]] && echo "Gate D passed."

# --- summary -----------------------------------------------------------------
if [[ $FAILURES -gt 0 ]]; then
  echo ""
  echo "gates.sh: $FAILURES gate(s) failed."
  exit 1
fi
echo ""
echo "gates.sh: all gates passed."
