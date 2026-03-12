# Contributing

Iron is a CLI-first Nim repo with most logic living under `src/lib/` and a thin interface split under `src/interfaces/`.

## Inner Workings

### Command flow
- The CLI follows the repo convention flow: perceive -> truth state -> act.
- Perception lives in small parsers such as command input readers, repo scanners, diff readers, and pipeline parsers.
- Truth builders assemble those raw signals into explicit objects that the actors can consume.
- Actors handle prompts, file writes, git commands, and terminal rendering.
- The main command dispatch lives in `src/lib/level1/core.nim`.

### Layout
- `src/lib/level0/` contains low-level shared types, config parsing, prompt helpers, and git/repo utilities.
- `src/lib/level1/` contains the command catalog and the repo workflow modules.
- `src/interfaces/frontend/cli/` contains the CLI entrypoint.
- `src/interfaces/backend/` contains the backend-facing coordinator surface.
- `tests/` contains smoke coverage for command parsing, repo scanning, coordinator behavior, and pipeline parsing.

### Metadata and config
- Repo metadata lives in `.iron/`.
- Global Iron config is persisted next to the active binary as `iron.config.toml`.
- Repo-local overrides still live in `.iron/repo_coordinator.toml`.
- Runtime-only files such as `.iron/progress.md` and `.iron/.local*.toml` should not be treated as canonical sync sources.

### Sync commands
- `iron sync-conventions` is the fixed-path convenience command for the canonical conventions file.
- `iron sync-iron-file` is the generic metadata sync command.
- The generic sync command locates the canonical template `.iron/` directory, lists syncable files in a numbered menu, asks for confirmation, and then writes the selected file into each discovered repo's `.iron/` directory.
- Generated docs under `.iron/docs/`, local runtime files, and local override files are intentionally excluded from the sync list.

### Commit summaries
- `pushall`, `autopush`, and `expand` use the diff-aware commit message builder.
- The builder parses git status and diff output, builds a truth state, extracts touched Nim declarations and their metapragmas, prints that truth in the CLI, and then emits a short commit headline such as `- Function change` or `- Big rename`.

### Pipeline viewer
- `iron show` now uses `.iron/pipeline.toml` by default.
- Pipeline files use top-level keys like `name`, `description`, `interval_ms`, and `root_id`, plus repeated `[[nodes]]` entries with `id`, `label`, `status`, `details`, and `parent`.
- The viewer reparses the file on every frame, so editing the TOML while `iron show` is running updates the rendered tree immediately.

## Contribution Rules
- Keep to the repo conventions in `.iron/conventions.md`.
- Prefer small parser/truth-builder/actor functions over nested logic.
- Use the metapragmas from `.iron/metaPragmas.nim` on new procs and fit the tags to the actual behavior.
- When touching user-facing flows, update the matching smoke tests.
- When changing scaffolded `.iron` files or CLI behavior, update `README.md` and `.iron/progress.md`.

## Verification
- Run `nimble test`.
- Run `nimble buildCli`.
- If you changed docs scaffolding or the pipeline viewer, verify `iron docs-init --repo .` and `iron show --once` behavior in a test repo.
