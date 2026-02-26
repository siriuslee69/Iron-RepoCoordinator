Commit Message: Rename embedded repo coordination modules to Valkyrie naming

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
1. Local repo coordination source lives under `src/valkyrie_repo_coordination/`
2. CLI commands added: `test`, `find`, `autopull`, `autopush`
3. CLI flags added: `--repo`, `--root`, `--mode`, `--replace`, `--dry-run`
4. Old JRC env/config naming removed from the embedded modules
5. Nimble tasks aligned with embedded CLI commands
6. Repo coordination smoke test renamed and kept in Valkyrie namespace
7. README updated with CLI-first architecture and issue playbook

Features (Working On):
1. Additional validation and regression checks after merge

Last Big Change or Problem:
1. Valkyrie still exposed old imported module and config names after the merge

Fix Attempt and Result:
1. Renamed the embedded module tree to Valkyrie-owned paths and config names; validation pending

Features (Planned):
- Add JSON bridge config for external dependency consumers
