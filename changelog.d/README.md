# changelog.d — change fragments

`CHANGELOG.md` is generated at release time and is never edited by hand.
Every change enters the changelog exclusively as a fragment in this directory.

## Convention

File name: `<pr>.<type>.md`

- `<pr>` — the pull request number
- `<type>` — one of: `feat` | `fix` | `perf` | `refactor` | `docs` | `chore` | `hotfix`

Example: `changelog.d/42.fix.md`

## Content

One or two lines describing the user-visible change, written in plain prose.
No headings, no signatures.

A code change without a fragment fails CI (Gate A). The owner-only `hotfix`
label is the escape hatch.
