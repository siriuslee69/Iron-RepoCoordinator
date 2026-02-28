# ==================================================
# | Valkyrie Tooling Core Command Logic            |
# |------------------------------------------------|
# | Parsing and dispatch for CLI + library users.  |
# ==================================================

import std/[strutils, os]
import ../level0/types
import repo_scan
import library_docs
import pipeline_show
import valkyrie_repo_coordinator/level0/repo_utils
import valkyrie_repo_coordinator/level1/autopull
import valkyrie_repo_coordinator/level1/autopush
import valkyrie_repo_coordinator/level1/branch_mode
import valkyrie_repo_coordinator/level1/expand
import valkyrie_repo_coordinator/level1/find_local_submodules
import valkyrie_repo_coordinator/level1/pushall
import valkyrie_repo_coordinator/level1/repo_health
import valkyrie_repo_coordinator/level1/submodule_extract
import valkyrie_repo_coordinator/level1/submodule_refresh
import valkyrie_repo_coordinator/level1/test_picker


proc defaultOptions*(): ToolingOptions =
  ## returns default command options
  var
    t: ToolingOptions
  t.repo = getCurrentDir()
  t.root = ""
  t.mode = ""
  t.srcPath = ""
  t.docsOut = ""
  t.pipelinePath = ""
  t.replace = false
  t.dryRun = false
  t.once = false
  t.loops = 0
  t.intervalMs = 700
  t.overwrite = false
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
    "  docs-init Create docs + pipeline scaffold files in valk/",
    "  docs      Generate autonomous library docs (md + json bridge)",
    "  show      Render valk/pipeline.json as live ASCII dependency tree",
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
    "  --src <path> or --src=<path>    Source path for docs generation",
    "  --docs-out <path> or --docs-out=<path>  Markdown output for docs",
    "  --pipeline <path> or --pipeline=<path>  Pipeline JSON for show",
    "  --replace                       Replace clone targets when extracting",
    "  --dry-run                       Do not modify repositories",
    "  --once                          Render one show frame and exit",
    "  --loops <int>                   Max show frames (0 = unbounded)",
    "  --interval-ms <int>             Show refresh interval in ms",
    "  --overwrite                     Overwrite docs-init scaffold files",
    "",
    "Environment:",
    "  VALKYRIE_ROOTS  Roots (Windows ';' or POSIX ':')",
    "  VALKYRIE_VERBOSE=1  Enable verbose output"
  ]
  result = ls.join("\n")

proc parseCommand*(cs: seq[string]): ToolingCommand =
  ## cs: command-line arguments
  var
    t: string
    i: int
  if cs.len == 0:
    result = tcHelp
    return
  i = 0
  if cs[0] == "--":
    i = 1
  if i >= cs.len:
    result = tcHelp
    return
  t = cs[i].toLowerAscii()
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
  of "test", "repotest":
    result = tcTest
  of "docs-init", "docsinit", "init-docs", "initdocs":
    result = tcDocsInit
  of "docs", "doc", "gendocs", "generate-docs":
    result = tcDocs
  of "show", "pipeline", "pipeline-show":
    result = tcShow
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

proc parseIntWithFallback(s: string, d: int): int =
  ## s: input string to parse as integer.
  ## d: fallback value when parsing fails.
  try:
    result = parseInt(s)
  except ValueError:
    result = d

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
    if a == "--src" and i + 1 < cs.len:
      t.srcPath = cs[i + 1]
      i = i + 2
      continue
    if a.startsWith("--src="):
      t.srcPath = a["--src=".len .. ^1]
      inc i
      continue
    if a == "--docs-out" and i + 1 < cs.len:
      t.docsOut = cs[i + 1]
      i = i + 2
      continue
    if a.startsWith("--docs-out="):
      t.docsOut = a["--docs-out=".len .. ^1]
      inc i
      continue
    if a == "--pipeline" and i + 1 < cs.len:
      t.pipelinePath = cs[i + 1]
      i = i + 2
      continue
    if a.startsWith("--pipeline="):
      t.pipelinePath = a["--pipeline=".len .. ^1]
      inc i
      continue
    if a == "--dry-run" or a == "--dryrun":
      t.dryRun = true
      inc i
      continue
    if a == "--once":
      t.once = true
      inc i
      continue
    if a == "--loops" and i + 1 < cs.len:
      t.loops = parseIntWithFallback(cs[i + 1], t.loops)
      i = i + 2
      continue
    if a.startsWith("--loops="):
      t.loops = parseIntWithFallback(a["--loops=".len .. ^1], t.loops)
      inc i
      continue
    if a == "--interval-ms" and i + 1 < cs.len:
      t.intervalMs = parseIntWithFallback(cs[i + 1], t.intervalMs)
      i = i + 2
      continue
    if a.startsWith("--interval-ms="):
      t.intervalMs = parseIntWithFallback(a["--interval-ms=".len .. ^1], t.intervalMs)
      inc i
      continue
    if a == "--overwrite":
      t.overwrite = true
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
    dReport: LibraryDocsReport
    diReport: DocsInitReport
    shReport: PipelineShowReport
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
  of tcDocsInit:
    diReport = initDocsScaffold(o.repo, o.overwrite)
    t = renderReportText(diReport.lines, diReport.ok, "Docs init completed.", "Docs init failed.")
  of tcDocs:
    dReport = generateLibraryDocs(o.repo, o.srcPath, o.docsOut)
    t = renderReportText(dReport.lines, dReport.ok, "Docs completed.", "Docs failed.")
  of tcShow:
    shReport = showPipeline(o.repo, o.pipelinePath, o.once, o.loops, o.intervalMs)
    t = renderReportText(shReport.lines, shReport.ok, "Show completed.", "Show failed.")
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
    t = "Valkyrie-Tooling v0.3.0"
  result = t
