Commit Message: Embed Jormungandr modules into Valkyrie CLI and remove submodule dependency

Features (Total):
1. CLI command parsing and dispatch
2. Embedded Jormungandr repo coordination
3. Package manager integration hooks (Eitri)
4. Repo scanning/listing and health checks
5. Submodule override flows (find/expand/extract)
6. Multi-repo git operations (autopull/autopush/pushall/branch)
7. Test discovery picker
8. Unit and smoke tests

Features (Implemented):
1. Local Jormungandr source vendored under `src/jormungandr_repo_coordinator/`
2. CLI commands added: `test`, `find`, `autopull`, `autopush`
3. CLI flags added: `--repo`, `--root`, `--mode`, `--replace`, `--dry-run`
4. Jormungandr submodule path removed from `config.nims`
5. Jormungandr submodule removed from `.gitmodules`
6. Nimble tasks aligned with embedded CLI commands
7. New embedded Jorm smoke test file
8. README updated with CLI-first architecture and issue playbook

Features (Working On):
1. Additional validation and regression checks after merge

Last Big Change or Problem:
1. Valkyrie depended on Jormungandr via submodule path and behaved like a thin wrapper

Fix Attempt and Result:
1. Moved Jorm modules into Valkyrie source and rewired command dispatch to local modules; integration compiled after follow-up fixes

Features (Planned):
- Add JSON bridge config for external dependency consumers
