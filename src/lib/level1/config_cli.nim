# ==================================================
# | iron Repo Coordinator Config CLI          |
# |------------------------------------------------|
# | View and edit the persisted iron config file.  |
# ==================================================

import std/[strutils, terminal]
import ../level0/types
import ../level0/repo_utils
include ../level0/metaPragmas


type
  CoordinatorConfigReport* = object
    ok*: bool
    path*: string
    lines*: seq[string]

  CoordinatorConfigTruthState = object
    path: string
    current: CoordinatorConfig
    next: CoordinatorConfig
    hasMutation: bool
    action: string


proc addLine(L: var seq[string], t: string) {.role(helper).} =
  ## L: report line buffer.
  ## t: line to append.
  L.add(t)

proc buildConfigLines(c: CoordinatorConfig, p: string): seq[string] {.role(truthBuilder).} =
  ## c: config state to display.
  ## p: config file path.
  var
    ownersText: string
    excludedReposText: string
  ownersText = c.owners.join(", ")
  if ownersText.len == 0:
    ownersText = "(none)"
  excludedReposText = c.excludedRepos.join(", ")
  if excludedReposText.len == 0:
    excludedReposText = "(none)"
  result = @[
    "iron config",
    "",
    "Path: " & p,
    "Owners: " & ownersText,
    "Excluded repos: " & excludedReposText,
    "Foreign mode: " & normalizeForeignMode(c.foreignMode)
  ]

proc removeOwner(A: seq[string], o: string): seq[string] {.role(actor).} =
  ## A: owner list to filter.
  ## o: owner to remove.
  var
    i: int
    t: string
  t = o.strip().toLowerAscii()
  i = 0
  while i < A.len:
    if A[i] != t:
      result.add(A[i])
    inc i

proc removeExcludedRepo(A: seq[string], r: string): seq[string] {.role(actor).} =
  ## A: excluded repo selector list to filter.
  ## r: repo selector to remove.
  var
    i: int
    t: string
  t = normalizeExcludedRepo(r)
  i = 0
  while i < A.len:
    if A[i] != t:
      result.add(A[i])
    inc i

proc applyOptionEdits(S: var CoordinatorConfigTruthState, o: ToolingOptions) {.role(actor).} =
  ## S: config truth state to mutate.
  ## o: CLI options carrying config edits.
  if o.configOwners.len > 0:
    S.next.owners = normalizeOwnerList(splitOwners(o.configOwners))
    S.hasMutation = true
    S.action = "Updated owners."
  if o.configAddOwner.len > 0:
    S.next.owners.add(o.configAddOwner.strip().toLowerAscii())
    S.next.owners = normalizeOwnerList(S.next.owners)
    S.hasMutation = true
    S.action = "Added owner."
  if o.configRemoveOwner.len > 0:
    S.next.owners = removeOwner(S.next.owners, o.configRemoveOwner)
    S.next.owners = normalizeOwnerList(S.next.owners)
    S.hasMutation = true
    S.action = "Removed owner."
  if o.configExcludedRepos.len > 0:
    S.next.excludedRepos = normalizeExcludedRepoList(splitListValue(o.configExcludedRepos))
    S.hasMutation = true
    S.action = "Updated excluded repos."
  if o.configAddExcludedRepo.len > 0:
    S.next.excludedRepos.add(o.configAddExcludedRepo)
    S.next.excludedRepos = normalizeExcludedRepoList(S.next.excludedRepos)
    S.hasMutation = true
    S.action = "Added excluded repo."
  if o.configRemoveExcludedRepo.len > 0:
    S.next.excludedRepos = removeExcludedRepo(S.next.excludedRepos, o.configRemoveExcludedRepo)
    S.next.excludedRepos = normalizeExcludedRepoList(S.next.excludedRepos)
    S.hasMutation = true
    S.action = "Removed excluded repo."
  if o.configForeignMode.len > 0:
    S.next.foreignMode = normalizeForeignMode(o.configForeignMode)
    S.hasMutation = true
    S.action = "Updated foreign mode."

proc promptConfigMenu(S: var CoordinatorConfigTruthState): bool {.role(actor).} =
  ## S: config truth state to mutate interactively.
  var
    idx: int
    t: string
    options: seq[string]
  options = @[
    "Show current config",
    "Set owners",
    "Add owner",
    "Remove owner",
    "Set excluded repos",
    "Add excluded repo",
    "Remove excluded repo",
    "Set foreign mode"
  ]
  idx = promptOptionsDefault("Select config action:", options, 0)
  if idx < 0:
    return false
  case idx
  of 0:
    return true
  of 1:
    t = promptText("Enter owners (comma-separated): ")
    if t.len == 0:
      return false
    S.next.owners = normalizeOwnerList(splitOwners(t))
    S.hasMutation = true
    S.action = "Updated owners."
  of 2:
    t = promptText("Enter owner to add: ")
    if t.len == 0:
      return false
    S.next.owners.add(t.strip().toLowerAscii())
    S.next.owners = normalizeOwnerList(S.next.owners)
    S.hasMutation = true
    S.action = "Added owner."
  of 3:
    t = promptText("Enter owner to remove: ")
    if t.len == 0:
      return false
    S.next.owners = removeOwner(S.next.owners, t)
    S.next.owners = normalizeOwnerList(S.next.owners)
    S.hasMutation = true
    S.action = "Removed owner."
  of 4:
    t = promptText("Enter excluded repos (comma-separated repo names or paths): ")
    if t.len == 0:
      return false
    S.next.excludedRepos = normalizeExcludedRepoList(splitListValue(t))
    S.hasMutation = true
    S.action = "Updated excluded repos."
  of 5:
    t = promptText("Enter repo name or path to exclude: ")
    if t.len == 0:
      return false
    S.next.excludedRepos.add(t)
    S.next.excludedRepos = normalizeExcludedRepoList(S.next.excludedRepos)
    S.hasMutation = true
    S.action = "Added excluded repo."
  of 6:
    t = promptText("Enter repo name or path to remove from excludes: ")
    if t.len == 0:
      return false
    S.next.excludedRepos = removeExcludedRepo(S.next.excludedRepos, t)
    S.next.excludedRepos = normalizeExcludedRepoList(S.next.excludedRepos)
    S.hasMutation = true
    S.action = "Removed excluded repo."
  else:
    idx = promptOptionsDefault("Select foreign mode:", @["update", "skip"], 0)
    if idx < 0:
      return false
    if idx == 0:
      S.next.foreignMode = "update"
    else:
      S.next.foreignMode = "skip"
    S.hasMutation = true
    S.action = "Updated foreign mode."
  result = true

proc buildConfigTruthState(o: ToolingOptions): CoordinatorConfigTruthState {.role(truthBuilder).} =
  ## o: CLI options that may request config edits.
  result.path = ensureGlobalCoordinatorConfig()
  result.current = readCoordinatorConfig("")
  result.next = result.current
  result.hasMutation = false
  result.action = ""
  applyOptionEdits(result, o)

proc runCoordinatorConfigCommand*(o: ToolingOptions): CoordinatorConfigReport {.role(orchestrator).} =
  ## o: CLI options carrying config mutations.
  var
    S: CoordinatorConfigTruthState
  result.ok = true
  S = buildConfigTruthState(o)
  result.path = S.path
  if not S.hasMutation and isatty(stdin):
    if not promptConfigMenu(S):
      result.ok = false
      addLine(result.lines, "Config command cancelled.")
      return
  if S.hasMutation:
    S.next.owners = normalizeOwnerList(S.next.owners)
    S.next.excludedRepos = normalizeExcludedRepoList(S.next.excludedRepos)
    S.next.foreignMode = normalizeForeignMode(S.next.foreignMode)
    result.path = writeGlobalCoordinatorConfig(S.next)
    if S.action.len > 0:
      addLine(result.lines, S.action)
  result.lines.add(buildConfigLines(
    if S.hasMutation: S.next else: S.current,
    result.path
  ))
