# Valkyrie-Tooling

Valkyrie is a Nim tooling library with a CLI, designed to integrate with Eitri (package manager), Jormungandr (repo coordinator), Yggdrasil (ASCII trees), and Tyr (crypto utilities).

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
- `tests/` unit tests
- `submodules/` external tooling dependencies

## Quick Start
- Build CLI: `nimble buildCli`
- Run CLI: `nimble runCli`
- Tests: `nimble test`

## Status
Scaffolded. Command handlers are placeholders while integrations are implemented.

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
