# Iron Repo Conventions

Canonical shared conventions live in:
- `submodules/proto-conventions/.iron/CONVENTIONS.md`

This local file is intentionally minimal and only documents Iron-specific behavior:

## Iron-specific notes
- Use `iron` as the primary CLI command surface.
- Keep bootstrap metadata in `.iron/` and local machine data in `.iron/.local*`.
- Keep `.iron/.local*` ignored by git, except `.template` files.
- When initializing repos, prefer templates from `submodules/proto-conventions/.iron/`.

## Sync rule
- If shared conventions change, update them in `proto-conventions` first.
- Only keep repo-specific overrides in this file.
