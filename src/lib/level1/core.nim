# ==================================================
# | Valkyrie Tooling Core Command Logic            |
# |------------------------------------------------|
# | Parsing and dispatch for CLI + library users.  |
# ==================================================

import std/[strutils, os]
import ../level0/types
import repo_scan
import valkyrie_repo_coordination/level0/repo_utils
import valkyrie_repo_coordination/level1/autopull
import valkyrie_repo_coordination/level1/autopush
import valkyrie_repo_coordination/level1/branch_mode
import valkyrie_repo_coordination/level1/expand
import valkyrie_repo_coordination/level1/find_local_submodules
import valkyrie_repo_coordination/level1/pushall
import valkyrie_repo_coordination/level1/repo_health
import valkyrie_repo_coordination/level1/submodule_extract
import valkyrie_repo_coordination/level1/submodule_refresh
import valkyrie_repo_coordination/level1/test_picker


proc defaultOptions*(): ToolingOptions =
  ## returns default command options
  var
    t: ToolingOptions
  t.repo = getCurrentDir()
  t.root = ""
  t.mode = ""
  t.replace = false
  t.dryRun = false
  result = t

proc buildHelp*(): string =
  ## returns CLI help text
  var
    ls: seq[string]
  ls = @[
    "Valkyrie Tooling CLI",
    "",
    "Usage:",
    "  val <command> [flags]",
    "  valkyrie_cli <command> [flags]",
    "",
    "Commands:",
    "  help      Show this help",
    "  health    Show repo health checks",
    "  status    Show repo status summary",
    "  scan      Scan local repos",
    "  repos     List known repos",
    "  test      Pick and run a test task (nimble + eitri)",
    "  find      Build local submodule overrides under roots",
    "  autopull  Pull all repos under discovered roots",
    "  autopush  Commit/push current repo",
    "  expand    Propagate updated submodule across repos",
    "  extract   Clone submodules to sibling repos",
    "  extract-all Extract submodules for all repos under roots",
    "  pushall   Add/commit/push repos under the selected root",
    "  refresh   Stash/pull submodule repos (main branch)",
    "  branch    Switch between main/nightly or promote nightly",
    "  version   Show version",
    "",
    "Flags:",
    "  --verbose  Show extra repo details",
    "  --repo <path> or --repo=<path>  Target repo for repo commands",
    "  --root <path> or --root=<path>  Override root for extract commands",
    "  --mode <main|nightly|promote>   Branch mode action",
    "  --replace                       Replace clone targets when extracting",
    "  --dry-run                       Do not modify repositories",
    "",
    "Environment:",
    "  VALKYRIE_ROOTS  Roots (Windows ';' or POSIX ':')",
    "  VALKYRIE_OWNERS  Allowed owners for write actions",
    "  VALKYRIE_FOREIGN_MODE  Foreign repo handling (update/skip)",
    "  VALKYRIE_VERBOSE=1  Enable verbose output"
  ]
  result = ls.join("\n")

proc parseCommand*(cs: seq[string]): ToolingCommand =
  ## cs: command-line arguments
  var
    t: string
  if cs.len == 0:
    result = tcHelp
    return
  t = cs[0].toLowerAscii()
  case t
  of "help", "-h", "--help":
    result = tcHelp
  of "health":
    result = tcHealth
  of "status":
    result = tcStatus
  of "scan":
    result = tcScan
  of "repos":
    result = tcRepos
  of "test":
    result = tcTest
  of "find":
    result = tcFind
  of "autopull":
    result = tcAutoPull
  of "autopush":
    result = tcAutoPush
  of "expand":
    result = tcExpand
  of "extract", "extract_submodules":
    result = tcExtract
  of "extract-all", "extract_all", "extract_submodules_global":
    result = tcExtractAll
  of "refresh", "submodrefresh":
    result = tcRefresh
  of "pushall", "autopushall":
    result = tcPushAll
  of "branch", "branch-mode", "branch_mode":
    result = tcBranchMode
  of "version", "-v", "--version":
    result = tcVersion
  else:
    result = tcHelp

proc parseOptions*(cs: seq[string]): ToolingOptions =
  ## cs: command-line arguments
  var
    t: ToolingOptions
    i: int
    a: string
  t = defaultOptions()
  i = 0
  while i < cs.len:
    a = cs[i]
    if i == 0 and not a.startsWith("-"):
      inc i
      continue
    if a == "--repo" and i + 1 < cs.len:
      t.repo = cs[i + 1]
      i = i + 2
      continue
    if a.startsWith("--repo="):
      t.repo = a["--repo=".len .. ^1]
      inc i
      continue
    if a == "--root" and i + 1 < cs.len:
      t.root = cs[i + 1]
      i = i + 2
      continue
    if a.startsWith("--root="):
      t.root = a["--root=".len .. ^1]
      inc i
      continue
    if a == "--mode" and i + 1 < cs.len:
      t.mode = cs[i + 1]
      i = i + 2
      continue
    if a.startsWith("--mode="):
      t.mode = a["--mode=".len .. ^1]
      inc i
      continue
    if a == "--replace":
      t.replace = true
      inc i
      continue
    if a == "--dry-run" or a == "--dryrun":
      t.dryRun = true
      inc i
      continue
    inc i
  result = t

proc renderReportText(ls: seq[string], ok: bool, okMsg: string, failMsg: string): string =
  ## ls: report lines.
  ## ok: operation status.
  ## okMsg: message for success without report lines.
  ## failMsg: message for failure without report lines.
  if ls.len == 0:
    if ok:
      result = okMsg
    else:
      result = failMsg
    return
  result = ls.join("\n")

proc readPaths(rs: seq[RepoInfo]): seq[string] =
  ## rs: repository metadata list.
  var
    t: seq[string]
    i: int
  i = 0
  while i < rs.len:
    t.add(rs[i].path)
    inc i
  result = t

proc readBranchMode(o: ToolingOptions): string =
  ## o: command options.
  var
    t: string
    opts: seq[string]
    idx: int
  t = o.mode.strip().toLowerAscii()
  if t in ["main", "nightly", "promote"]:
    result = t
    return
  opts = @[
    "Switch to main",
    "Switch to nightly",
    "Promote nightly to main"
  ]
  idx = promptOptions("Select branch action:", opts)
  if idx < 0:
    result = ""
    return
  case idx
  of 0:
    result = "main"
  of 1:
    result = "nightly"
  else:
    result = "promote"

proc runCommand*(c: ToolingCommand, s: ToolingConfig, o: ToolingOptions): string =
  ## c: command to run.
  ## s: tooling configuration.
  ## o: command-specific options.
  var
    t: string
    roots: seq[string]
    repos: seq[RepoInfo]
    lines: seq[string]
    paths: seq[string]
    subCount: int
    valkCount: int
    repo: RepoInfo
    i: int
    eReport: ExpandReport
    xReport: SubmoduleExtractReport
    gxReport: SubmoduleExtractGlobalReport
    fReport: FindLocalSubmodulesReport
    apReport: AutoPullReport
    apsReport: AutoPushReport
    rReport: SubmoduleRefreshReport
    pReport: PushAllReport
    bReport: BranchModeReport
    hReport: RepoHealthReport
    mode: string
    ec: int
  case c
  of tcHelp:
    t = buildHelp()
  of tcHealth:
    roots = resolveRoots(s)
    repos = discoverRepos(roots)
    paths = readPaths(repos)
    hReport = buildRepoHealthReport(paths)
    lines = formatRepoHealthReport(hReport, s.verbose)
    t = lines.join("\n")
  of tcStatus:
    roots = resolveRoots(s)
    repos = discoverRepos(roots)
    i = 0
    while i < repos.len:
      repo = repos[i]
      if repo.hasSubmodules:
        subCount = subCount + 1
      if repo.hasValkyrie:
        valkCount = valkCount + 1
      inc i
    lines = @[
      "Valkyrie Tooling Status",
      "",
      buildRootsText(roots),
      "",
      "Repo count: " & $repos.len,
      "Repos with submodules: " & $subCount,
      "Repos with valkyrie folder: " & $valkCount
    ]
    t = lines.join("\n")
  of tcScan:
    roots = resolveRoots(s)
    repos = discoverRepos(roots)
    lines = @[
      "Valkyrie Scan",
      "",
      buildRootsText(roots),
      "",
      buildReposText(repos, s.verbose)
    ]
    t = lines.join("\n")
  of tcRepos:
    roots = resolveRoots(s)
    repos = discoverRepos(roots)
    t = buildReposText(repos, s.verbose)
  of tcTest:
    ec = runTestPicker()
    if ec == 0:
      t = ""
    else:
      t = "Test picker failed."
  of tcFind:
    fReport = findLocalSubmodulesFromRoots(o.dryRun)
    t = renderReportText(fReport.lines, fReport.ok, "Find completed.", "Find failed.")
  of tcAutoPull:
    apReport = autoPullFromRoots(o.dryRun)
    t = renderReportText(apReport.lines, apReport.ok, "Autopull completed.", "Autopull failed.")
  of tcAutoPush:
    apsReport = autoPushRepo(o.repo)
    t = renderReportText(apsReport.lines, apsReport.ok, "Autopush completed.", "Autopush failed.")
  of tcExpand:
    eReport = expandSubmodule(o.repo, s.verbose)
    t = renderReportText(eReport.lines, eReport.ok, "Expand completed.", "Expand failed.")
  of tcExtract:
    xReport = extractSubmodules(o.repo, o.root, o.replace, s.verbose)
    t = renderReportText(xReport.lines, xReport.ok, "Extract completed.", "Extract failed.")
  of tcExtractAll:
    gxReport = extractSubmodulesGlobal(o.root, o.replace, s.verbose)
    t = renderReportText(gxReport.lines, gxReport.ok, "Extract-all completed.", "Extract-all failed.")
  of tcRefresh:
    rReport = refreshSubmodules()
    t = renderReportText(rReport.lines, rReport.ok, "Refresh completed.", "Refresh failed.")
  of tcPushAll:
    pReport = pushAllFromParent(s.verbose)
    t = renderReportText(pReport.lines, pReport.ok, "Pushall completed.", "Pushall failed.")
  of tcBranchMode:
    mode = readBranchMode(o)
    if mode.len == 0:
      t = "Branch mode cancelled."
    else:
      bReport = switchBranchMode(o.repo, mode)
      t = renderReportText(bReport.lines, bReport.ok, "Branch mode completed.", "Branch mode failed.")
  of tcVersion:
    t = "Valkyrie-Tooling v0.2.0"
  result = t
