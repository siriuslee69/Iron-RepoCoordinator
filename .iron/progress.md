Commit Message: Refactor CLI command flow and add persisted iron config menus

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
13. Added `src/lib/level1/library_docs.nim` for autonomous API docs + JSON bridge output
14. Added `src/lib/level1/pipeline_show.nim` for JSON tree parsing + live ASCII rendering loop
15. Added `.iron/pipeline.json`, `.iron/pipeline.library.json`, and `.iron/docs_instructionset.md` templates
16. Added `.iron/illwill_pipeline_example.nim` for terminal animation reference
17. Refactored the library package tree under `src/lib/`
18. Removed the legacy `val` entrypoint and `VALKYRIE_*` env fallbacks
19. Added `IRON_ASSUME_YES` support for non-interactive push/confirm flows
20. Fixed Windows root scanning for `iron repos` and related root-based commands
21. Split CLI command handling into command catalog/perception/truth/actor modules
22. Added interactive unknown-command suggestions and command selection menus
23. Added global `iron.config.toml` persistence next to the active binary
24. Added `iron config` for viewing and editing persisted owners/foreign mode
25. Refactored `pushall` around repo perception, truth-state assembly, and push actors
26. Collapsed the duplicate coordinator trees into one `src/lib/level0|level1` layout
27. Moved backend and CLI entrypoints into `src/interfaces/backend` and `src/interfaces/frontend/cli`

Features (Working On):
1. Follow-up cleanup for remaining write-command flows that still surface legacy local-config wording

Last Big Change or Problem:
1. The CLI parser/dispatcher and pushall flow had grown into mixed parse-state-action code that no longer matched the updated workspace conventions

Fix Attempt and Result:
1. Split command handling into smaller parser/truth/actor modules, moved persisted config handling next to the binary, and rebuilt pushall around an explicit truth state with interactive owner setup; the smoke tests pass after the refactor

Features (Planned):
- Add optional Illwill-backed renderer mode directly inside `iron show` when dependency is installed
