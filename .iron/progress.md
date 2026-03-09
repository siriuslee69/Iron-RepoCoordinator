Commit Message: Add autonomous library docs generation and live pipeline viewer commands

Features (Total):
1. CLI command parsing and dispatch
2. Embedded repo coordination
3. Package manager integration hooks (Eitri)
4. Repo scanning/listing and health checks
5. Submodule override flows (find/expand/extract)
6. Multi-repo git operations (autopull/autopush/pushall/branch)
7. Test discovery picker
8. Unit and smoke tests
9. Autonomous library docs generation (markdown + JSON bridge)
10. Live ASCII pipeline visualization for active development status
11. Docs/pipeline scaffolding templates for AI-agent workflows

Features (Implemented):
1. Local coordinator source vendored under `src/iron_repo_coordinator/`
2. CLI commands added: `test`, `find`, `autopull`, `autopush`
3. CLI flags added: `--repo`, `--root`, `--mode`, `--replace`, `--dry-run`
4. Coordinator submodule path removed from `config.nims`
5. Coordinator submodule removed from `.gitmodules`
6. Nimble tasks aligned with embedded CLI commands
7. New embedded repo coordinator smoke test file
8. README updated with CLI-first architecture and issue playbook
9. Embedded source namespace moved to `iron_repo_coordinator`
10. Removed remaining legacy compatibility alias module
11. New commands: `docs-init`, `docs`, `show`
12. New flags: `--src`, `--docs-out`, `--pipeline`, `--once`, `--loops`, `--interval-ms`, `--overwrite`
13. Added `src/iron_repo_coordinator/lib/level1/library_docs.nim` for autonomous API docs + JSON bridge output
14. Added `src/iron_repo_coordinator/lib/level1/pipeline_show.nim` for JSON tree parsing + live ASCII rendering loop
15. Added `.iron/pipeline.json`, `.iron/pipeline.library.json`, and `.iron/docs_instructionset.md` templates
16. Added `.iron/illwill_pipeline_example.nim` for terminal animation reference
17. Extended smoke tests for docs generation and pipeline parsing/rendering

Features (Working On):
1. Additional validation and regression checks after merge

Last Big Change or Problem:
1. Needed a maintainable docs pipeline usable by both humans and AI agents, plus live progress visualization

Fix Attempt and Result:
1. Added dedicated docs/pipeline modules, wired new CLI commands/options, and scaffolded reusable templates; smoke tests updated to guard behavior

Features (Planned):
- Add optional Illwill-backed renderer mode directly inside `iron show` when dependency is installed
