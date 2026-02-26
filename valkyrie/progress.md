# Progress

Commit Message: Complete Valkyrie coordinator naming cleanup

Features (Planned):
- Add config bridge JSON for downstream consumers

Features (Done):
- Embedded coordinator source modules in `src`
- Added CLI commands for test/find/autopull/autopush
- Added command flags for repo/root/mode/replace/dry-run
- Removed legacy coordinator submodule dependency from build path
- Added embedded coordinator smoke tests

Features (In Progress):
- Broader command regression pass on live multi-repo workflows

Notes:
- Last change/problem: Valkyrie depended on a legacy coordinator submodule path and acted as a thin wrapper
- Fix attempts: Vendored modules + rewired command dispatch to local code (worked in tests)
