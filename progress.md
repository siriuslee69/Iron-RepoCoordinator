Commit Message: Wire Jormungandr expand into Valkyrie

Features (Total):
1. CLI command parsing and dispatch
2. Repo coordination via Jormungandr integration
3. Package manager integration via Eitri
4. ASCII tree previews via Yggdrasil
5. Encryption and hashing helpers via Tyr
6. Sigma bench/eval integration
7. Config loading and defaults
8. Repo scanning/listing
9. Jormungandr expand integration
10. Tests for core commands
11. Repo health checks (dirty/ahead/behind)

Features (Implemented):
1. Base project structure and conventions
2. CLI entrypoint stub + val alias entrypoint
3. Core command parsing
4. Repo scanning/listing with root discovery
5. Jormungandr expand integration
6. Sigma submodule added
7. Repo health checks via Jormungandr scan
8. Foreign repo railguards (owners + update-only mode)

Features (Working On):
1. Config loading and submodule wiring
2. Jormungandr-driven syncing beyond expand
3. Add a `valkyrie/` folder per repo (planned, not created yet)

Last Big Change or Problem:
1. Added Jormungandr expand wiring and repo utils path integration

Fix Attempt and Result:
1. Not applicable yet
