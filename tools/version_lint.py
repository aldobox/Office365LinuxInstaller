#!/usr/bin/env python3
"""Version lint: no hand-written version literals outside the allowlist.

The git tag is the single source of truth for the version. This lint scans
tracked files for version-shaped literals and fails if any appear outside
the per-repo allowlist below.
"""

import re
import subprocess
import sys

# Version-shaped literals: X.Y.Z with all-numeric components.
VERSION_RE = re.compile(r"(?<![\w.])\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?(?![\w.])")

# Allowlist: path substring -> reason the literal is permitted there.
ALLOWLIST = {
    "tools/version_lint.py": "the linter itself matches version shapes",
    "CHANGELOG.md": "generated release notes",
    "docs/ESTATE-STANDARDS.md": "standard examples",
    "changelog.d/": "fragment examples may cite releases",
    "MANIFEST": "release manifest may reference artefact versions",
}


def tracked_files():
    out = subprocess.run(
        ["git", "ls-files"], check=True, capture_output=True, text=True
    ).stdout
    return [line for line in out.splitlines() if line.strip()]


def is_allowed(path: str) -> bool:
    return any(key in path for key in ALLOWLIST)


def main() -> int:
    failures = []
    for path in tracked_files():
        if is_allowed(path):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                for lineno, line in enumerate(fh, 1):
                    for match in VERSION_RE.finditer(line):
                        failures.append(
                            f"{path}:{lineno}: version literal "
                            f"'{match.group(0)}'"
                        )
        except OSError:
            continue
    if failures:
        print("Version lint FAILED — hardcoded version literals found:")
        for failure in failures:
            print(f"  {failure}")
        print(
            "\nVersions come from the git tag. Remove the literal or add a "
            "justified allowlist entry."
        )
        return 1
    print("Version lint passed: no hardcoded version literals.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
