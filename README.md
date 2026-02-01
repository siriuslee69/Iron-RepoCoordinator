# Valkyrie-Tooling

Valkyrie is a Nim tooling library with a CLI, designed to integrate with Eitri (package manager), Jormungandr (repo coordinator), Yggdrasil (ASCII trees), Tyr (crypto utilities), and Sigma (bench/eval utilities).

## Goals
- Clean, modular tooling primitives with a thin CLI wrapper
- Straightforward integration points for related tooling repos
- Simple, testable command routing

## Structure
- `src/lib/level0/` base types and small helpers
- `src/lib/level1/` core command parsing and dispatch
- `src/cli/level1/` CLI runner
- `src/valkyrie_tooling.nim` public API re-exports
- `src/valkyrie_cli.nim` CLI entrypoint
- `src/val.nim` CLI alias entrypoint
- `tests/` unit tests
- `submodules/` external tooling dependencies

## Quick Start
- Build CLI: `nimble buildCli`
- Run CLI: `nimble runCli`
- Run short CLI: `nimble runVal`
- Tests: `nimble test`
- Expand submodules: `val expand` (wraps Jormungandr expand)

## Configuration
- Roots are discovered from `VALKYRIE_ROOTS` (preferred) or `JRC_ROOTS` (fallback).
  - Windows: separate with `;` (avoid splitting drive letters)
  - POSIX: separate with `:`
- Default roots: the parent of the current repo, plus a sibling `../Coding` if it exists.
- Verbose repo output: `--verbose` or set `VALKYRIE_VERBOSE=1`.

## Status
Repo scan/listing and Jormungandr expand are live. Integrations are still in progress.

## Roadmap Notes
- Each repo in the ecosystem will eventually have a `valkyrie/` folder for local tooling metadata (not created yet).

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
