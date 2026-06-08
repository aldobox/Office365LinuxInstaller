# Contributing to Office365LinuxInstaller

Thank you for your interest in contributing! This project welcomes improvements, bug fixes, and documentation updates.

## How to Contribute

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally.
3. Create a **feature branch** (`git checkout -b feature/my-improvement`).
4. Make your changes with clear, atomic commits.
5. Ensure `bash -n` passes on any modified `.sh` files.
6. **Push** your branch and open a **Pull Request**.

## Code Style

- Use `#!/usr/bin/env bash` shebang.
- Enable `set -euo pipefail` in all scripts.
- Prefer `$HOME` and `$USER` over hardcoded paths.
- Comment sections with `---- Section Name ----` headers.
- Use descriptive function names (`phase_x_description`).

## Reporting Issues

- Use GitHub Issues.
- Include your distribution, Wine version, and Office version.
- Attach relevant terminal output (redact personal info).

## Legal Notice

By contributing, you agree that your contributions will be licensed under the MIT License.
You must not submit code that facilitates software piracy or circumvention of licensing.
