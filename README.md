# Valkyrie-Tooling

Valkyrie is a CLI-first multi-repo tooling project in Nim. Repo-coordinator functionality is embedded directly in this repository, so Valkyrie is no longer only a wrapper around an external coordinator submodule.

## Goals
- Keep one practical CLI surface for multi-repo workflows.
- Keep core repo coordination logic local to this repo.
- Keep optional ecosystem integrations (Eitri, Yggdrasil, Tyr, Sigma) modular.

## Structure
- `src/cli/level1/` CLI runner and entrypoints (`valkyrie_cli`, `val`)
- `src/lib/level0/` base types and config
- `src/lib/level1/` command parsing, dispatch, root scanning
- `src/valkyrie_repo_coordinator/` embedded repo-coordination modules
- `tests/` smoke tests for Valkyrie + embedded coordinator behavior
- `submodules/` optional external tooling dependencies

## Quick Start
- Build CLI: `nimble buildCli`
- Run CLI: `nimble runVal`
- Run tests: `nimble test`

Common commands:
- `val help`
- `val status`
- `val health`
- `val test`
- `val find`
- `val autopull`
- `val autopush`
- `val expand --repo <path>`
- `val extract --repo <path> --root <path> --replace`
- `val extract-all --root <path>`
- `val branch --mode main|nightly|promote`
- `val pushall`

## Configuration
- Roots are discovered from `VALKYRIE_ROOTS`.
  - Windows separator: `;`
  - POSIX separator: `:`
- Verbose output:
  - CLI flag: `--verbose`
  - Env flag: `VALKYRIE_VERBOSE=1`
- Ownership safety is configured via `valkyrie/repo_coordinator.toml`:

```toml
owners = "siriuslee69"
foreign_mode = "update" # update or skip
```

Write actions require `owners` to be configured.

## Safety Policy
- Write operations prompt for explicit ENTER confirmation.
- Interactive options use numbered choices and `x` to abort.
- Non-interactive sessions abort for write operations.

## Issue Playbook
- Problem: write actions are blocked with `No owners configured`.
  - Workaround: set `owners` in `valkyrie/repo_coordinator.toml`.
- Problem: `find` or `expand` does not link a submodule.
  - Workaround: ensure matching local clone name/path and check `.gitmodules` entries.
- Problem: branch switching fails on dirty repo state.
  - Workaround: commit or stash changes before `val branch`.

---

## Conventions Summary
- Prefer clarity and modularity over micro-optimizations.
- Avoid nested functions; use helper procs.
- Use dependency-aware folder levels (`level0`, `level1`, ...).
- Use parameter names based on the first letter of their meaning.
- Add `##` doc comments under every proc declaration to explain parameters.
- Use `s`/`s0`/`s1` for mutable state parameters.
- Declare `var`, `let`, `const`, and `type` blocks at the top of a proc.
- Use `i/j/k` for indices and `l/m/n` for lengths.
- Keep tests in `tests/` and run them after changes.
- Update `progress.md` and this README for major changes.
