# iron-Tooling

iron is a CLI-first multi-repo tooling project in Nim. Repo-coordinator functionality is embedded directly in this repository, so iron is no longer only a wrapper around an external coordinator submodule.

## Goals
- Keep one practical CLI surface for multi-repo workflows.
- Keep core repo coordination logic local to this repo.
- Keep optional ecosystem integrations (Eitri, Yggdrasil, Tyr, Sigma) modular.

## Structure
- `src/lib/level0/` base types, config, and repo utilities
- `src/lib/level1/` command catalog/perception/truth/actor flow plus repo-coordination modules
- `src/interfaces/backend/` backend-facing coordinator surface
- `src/interfaces/frontend/cli/` CLI entrypoint and runner
- `src/*.nim` thin root modules and package exports
- `tests/` smoke tests for iron + embedded coordinator behavior
- `submodules/` optional external tooling dependencies
  - uses `Proto-RepoTemplate` as the shared conventions source

## Quick Start
- Build CLI: `nimble buildCli`
- Run CLI: `nimble runCli`
- Run tests: `nimble test`

Common commands:
- `iron help`
- `iron status`
- `iron health`
- `iron test`
- `iron docs-init --repo .`
- `iron docs --repo .`
- `iron show --repo . --pipeline .iron/pipeline.json`
- `iron find`
- `iron autopull`
- `iron autopush`
- `iron expand --repo <path>`
- `iron extract --repo <path> --root <path> --replace`
- `iron extract-all --root <path>`
- `iron branch --mode main|nightly|promote`
- `iron pushall`
- `iron config`
- `iron clone <url>`
- `iron init --repo <path>`
- `iron conflicts --root <path>`

Extended docs/pipeline flags:
- `--src <path>` source directory for docs scan (`docs` command)
- `--docs-out <path>` markdown output path for generated docs
- `--pipeline <path>` pipeline JSON to render in `show`
- `--once` render one frame and exit
- `--loops <int>` max frames for `show` (`0` keeps running)
- `--interval-ms <int>` refresh interval for `show`
- `--overwrite` allow `docs-init` to overwrite scaffold files

## Autonomous Library Docs
- Run `iron docs-init --repo .` once to scaffold:
  - `.iron/pipeline.json`
  - `.iron/pipeline.library.json`
  - `.iron/docs_instructionset.md`
  - `.iron/illwill_pipeline_example.nim`
- Run `iron docs --repo .` to generate:
  - `.iron/docs/library_api.md` (human-readable overview)
  - `.iron/docs/library_api.json` (AI-friendly bridge)

The generated docs include:
- module index
- import hints
- exported symbol map
- missing-doc coverage counts

## Pipeline Viewer (`iron show`)
`iron show` reads `.iron/pipeline.json` (or `pipeline.library.json`) as a JSON tree, then draws an updating ASCII dependency view in a loop. It re-reads the file every frame, so an agent can edit the pipeline while the viewer is running.

Example:
- `iron show --repo . --pipeline .iron/pipeline.json --interval-ms 600`
- `iron show --repo . --once`

Pipeline JSON shape:

```json
{
  "name": "Library Maintenance Pipeline",
  "description": "Track current work and dependencies.",
  "intervalMs": 700,
  "root": {
    "id": "plan",
    "label": "Plan changes",
    "status": "done",
    "details": "Outline touched modules.",
    "children": [
      {
        "id": "edit",
        "label": "Implement edits",
        "status": "active",
        "children": []
      }
    ]
  }
}
```

Status values:
- `todo`
- `active`
- `done`
- `blocked`
- `failed`

## Configuration
- Roots are discovered from `IRON_ROOTS`.
  - Windows separator: `;`
  - POSIX separator: `:`
- Verbose output:
  - CLI flag: `--verbose`
  - Env flag: `IRON_VERBOSE=1`
- Scripted confirmations:
  - Env flag: `IRON_ASSUME_YES=1`
- iron now persists its main config next to the active binary as `iron.config.toml`.
- Edit it with `iron config` or flags such as:
  - `iron config --owners siriuslee69`
  - `iron config --add-owner siriuslee69`
  - `iron config --remove-owner siriuslee69`
  - `iron config --exclude-repos RepoA,RepoB`
  - `iron config --add-exclude RepoC`
  - `iron config --remove-exclude RepoC`
  - `iron config --foreign-mode skip`
- Optional repo-local overrides are still read from `.iron/repo_coordinator.toml`:

```toml
owners = "siriuslee69"
excluded_repos = "RepoA,RepoB"
foreign_mode = "update" # update or skip
```

Write actions use configured owners from the global iron config first, then repo-local overrides, then env overrides.

## Safety Policy
- Write operations prompt for explicit ENTER confirmation.
- Interactive options use numbered choice menus and require ENTER once more to confirm the selected item.
- Unknown commands show a suggestion menu instead of dumping the full help text.
- Non-interactive sessions abort for write operations.

## Command Flow
- The CLI now follows the workspace convention split:
  - perceive: raw args are parsed into command/input state
  - truth: command truth state resolves aliases and suggestions
  - act: interactive menus resolve the final command before dispatch
- `pushall` now follows the same pattern:
  - perceive repo/git/owner state
  - build a push truth state
  - act by selecting/configuring the owner and running one push pass over the eligible repos

## Issue Playbook
- Problem: write actions are blocked with `No owners configured`.
  - Workaround: run `iron config` or let `iron pushall` save a detected owner into `iron.config.toml`.
- Problem: `find` or `expand` does not link a submodule.
  - Workaround: ensure matching local clone name/path and check `.gitmodules` entries.
- Problem: branch switching fails on dirty repo state.
  - Workaround: commit or stash changes before `iron branch`.

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
- Update `.iron/PROGRESS.md` and this README for major changes.
- Keep `.iron/pipeline.json` current during active development.
- Regenerate `.iron/docs/library_api.md` and `.iron/docs/library_api.json` after meaningful API changes.
