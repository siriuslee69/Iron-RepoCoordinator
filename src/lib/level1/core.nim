# Valkyrie Tooling | core command logic
# Parsing and dispatch for CLI and library consumers.

import std/[strutils, os]
import ../level0/types
import repo_scan
import jormungandr_repo_coordinator/level0/repo_utils
import jormungandr_repo_coordinator/level1/branch_mode
import jormungandr_repo_coordinator/level1/expand
import jormungandr_repo_coordinator/level1/pushall
import jormungandr_repo_coordinator/level1/submodule_refresh
import jormungandr_repo_coordinator/level1/submodule_extract

proc buildHelp*(): string =
  ## returns CLI help text
  var
    tLines: seq[string]
  tLines = @[
    "Valkyrie Tooling CLI",
    "",
    "Usage:",
    "  val <command>",
    "  valkyrie_cli <command>",
    "",
    "Commands:",
    "  help     Show this help",
    "  status   Show repo status summary",
    "  scan     Scan local repos",
    "  repos    List known repos",
    "  expand   Propagate updated submodule across repos",
    "  extract  Clone submodules to sibling repos",
    "  extract-all  Extract submodules for all repos under roots",
    "  pushall  Add/commit/push all repos under parent directory",
    "  refresh  Stash/pull submodule repos (main branch)",
    "  branch   Switch between main/nightly or promote nightly",
    "  version  Show version",
    "",
    "Flags:",
    "  --verbose  Show extra repo details",
    "",
    "Environment:",
    "  VALKYRIE_ROOTS  Roots (Windows ';' or POSIX ':')",
    "  JRC_ROOTS       Fallback roots (same format)",
    "  VALKYRIE_VERBOSE=1  Enable verbose output"
  ]
  result = tLines.join("\n")

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
  of "status":
    result = tcStatus
  of "scan":
    result = tcScan
  of "repos":
    result = tcRepos
  of "expand":
    result = tcExpand
  of "extract":
    result = tcExtract
  of "extract-all", "extract_all":
    result = tcExtractAll
  of "refresh":
    result = tcRefresh
  of "pushall":
    result = tcPushAll
  of "branch", "branch-mode", "branch_mode":
    result = tcBranchMode
  of "version", "-v", "--version":
    result = tcVersion
  else:
    result = tcHelp

proc runCommand*(c: ToolingCommand, s: ToolingConfig): string =
  ## c: command to run
  ## s: tooling configuration
  var
    t: string
    tRoots: seq[string]
    tRepos: seq[RepoInfo]
    tLines: seq[string]
    tSubCount: int
    tValkCount: int
    tRepo: RepoInfo
    i: int
    tReport: ExpandReport
  case c
  of tcHelp:
    t = buildHelp()
  of tcStatus:
    tRoots = resolveRoots(s)
    tRepos = discoverRepos(tRoots)
    i = 0
    while i < tRepos.len:
      tRepo = tRepos[i]
      if tRepo.hasSubmodules:
        inc tSubCount
      if tRepo.hasValkyrie:
        inc tValkCount
      inc i
    tLines = @[
      "Valkyrie Tooling Status",
      "",
      buildRootsText(tRoots),
      "",
      "Repo count: " & $tRepos.len,
      "Repos with submodules: " & $tSubCount,
      "Repos with valkyrie folder: " & $tValkCount
    ]
    t = tLines.join("\n")
  of tcScan:
    tRoots = resolveRoots(s)
    tRepos = discoverRepos(tRoots)
    tLines = @[
      "Valkyrie Scan",
      "",
      buildRootsText(tRoots),
      "",
      buildReposText(tRepos, s.verbose)
    ]
    t = tLines.join("\n")
  of tcRepos:
    tRoots = resolveRoots(s)
    tRepos = discoverRepos(tRoots)
    t = buildReposText(tRepos, s.verbose)
  of tcExpand:
    tReport = expandSubmodule(getCurrentDir(), s.verbose)
    if tReport.lines.len == 0:
      if tReport.ok:
        t = "Expand completed."
      else:
        t = "Expand failed."
    else:
      t = tReport.lines.join("\n")
  of tcExtract:
    var eReport: SubmoduleExtractReport = extractSubmodules(getCurrentDir(), "", false, s.verbose)
    if eReport.lines.len == 0:
      if eReport.ok:
        t = "Extract completed."
      else:
        t = "Extract failed."
    else:
      t = eReport.lines.join("\n")
  of tcExtractAll:
    var gReport: SubmoduleExtractGlobalReport = extractSubmodulesGlobal("", false, s.verbose)
    if gReport.lines.len == 0:
      if gReport.ok:
        t = "Extract-all completed."
      else:
        t = "Extract-all failed."
    else:
      t = gReport.lines.join("\n")
  of tcRefresh:
    var rReport: SubmoduleRefreshReport = refreshSubmodules()
    if rReport.lines.len == 0:
      if rReport.ok:
        t = "Refresh completed."
      else:
        t = "Refresh failed."
    else:
      t = rReport.lines.join("\n")
  of tcPushAll:
    var pReport: PushAllReport = pushAllFromParent(s.verbose)
    if pReport.lines.len == 0:
      if pReport.ok:
        t = "Pushall completed."
      else:
        t = "Pushall failed."
    else:
      t = pReport.lines.join("\n")
  of tcBranchMode:
    var opts: seq[string] = @[
      "Switch to main",
      "Switch to nightly",
      "Promote nightly to main"
    ]
    var idx: int = promptOptions("Select branch action:", opts)
    if idx < 0:
      t = "Branch mode cancelled."
    else:
      var mode: string
      case idx
      of 0:
        mode = "main"
      of 1:
        mode = "nightly"
      else:
        mode = "promote"
      var bReport: BranchModeReport = switchBranchMode(getCurrentDir(), mode)
      if bReport.lines.len == 0:
        if bReport.ok:
          t = "Branch mode completed."
        else:
          t = "Branch mode failed."
      else:
        t = bReport.lines.join("\n")
  of tcVersion:
    t = "Valkyrie-Tooling v0.1.0"
  result = t
