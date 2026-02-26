Commit Message: Remove remaining legacy naming and use Valkyrie coordinator namespace only

Features (Total):
1. CLI command parsing and dispatch
2. Embedded repo coordination
3. Package manager integration hooks (Eitri)
4. Repo scanning/listing and health checks
5. Submodule override flows (find/expand/extract)
6. Multi-repo git operations (autopull/autopush/pushall/branch)
7. Test discovery picker
8. Unit and smoke tests

Features (Implemented):
1. Local coordinator source vendored under `src/valkyrie_repo_coordinator/`
2. CLI commands added: `test`, `find`, `autopull`, `autopush`
3. CLI flags added: `--repo`, `--root`, `--mode`, `--replace`, `--dry-run`
4. Coordinator submodule path removed from `config.nims`
5. Coordinator submodule removed from `.gitmodules`
6. Nimble tasks aligned with embedded CLI commands
7. New embedded repo coordinator smoke test file
8. README updated with CLI-first architecture and issue playbook
9. Embedded source namespace moved to `valkyrie_repo_coordinator`
10. Removed remaining legacy compatibility alias module

Features (Working On):
1. Additional validation and regression checks after merge

Last Big Change or Problem:
1. Valkyrie depended on a separately named coordinator path and behaved like a thin wrapper

Fix Attempt and Result:
1. Moved coordinator modules into Valkyrie source and rewired command dispatch to local modules; integration compiled after follow-up fixes

Features (Planned):
- Add JSON bridge config for external dependency consumers
