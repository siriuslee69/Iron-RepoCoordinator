# ==================================================
# | iron Tooling Core Command Logic            |
# |------------------------------------------------|
# | Command wrappers and action dispatch.          |
# ==================================================

import std/[os, strutils]
import ../level0/types
import command_actor
import command_catalog
import command_options
import command_perception
import command_truth
import repo_scan
import library_docs
import pipeline_show
import ../level0/repo_utils
import autopull
import autopush
import branch_mode
import config_cli
import conventions_sync
import expand
import find_local_submodules
import pushall
import repo_bootstrap
import repo_conflicts
import repo_health
import submodule_externalize
import submodule_extract
import submodule_links
import submodule_refresh
import test_picker
include ../level0/metaPragmas


const
  ToolingVersion* = "iron-Tooling v0.5.0"


proc defaultOptions*(): ToolingOptions {.role(helper).} =
  ## returns default command options.
  result = command_options.defaultOptions()

proc buildHelp*(): string {.role(actor).} =
  ## returns CLI help text.
  result = command_catalog.buildHelp()

proc buildCommandTruthState*(A: seq[string]): ToolingCommandTruth {.role(truthBuilder).} =
  ## A: raw CLI arguments.
  var
    I: ToolingCommandInput
  I = readCommandInput(A)
  result = buildCommandTruth(I)

proc parseCommand*(A: seq[string]): ToolingCommand {.role(parser).} =
  ## A: raw CLI arguments.
  var
    T: ToolingCommandTruth
  T = buildCommandTruthState(A)
  if T.recognized:
    return T.command
  result = tcHelp

proc parseOptions*(A: seq[string]): ToolingOptions {.role(parser).} =
  ## A: raw CLI arguments.
  result = command_options.parseOptions(A)

proc resolveCliCommand*(A: seq[string]): ToolingCommandTruth {.role(orchestrator).} =
  ## A: raw CLI arguments.
  var
    T: ToolingCommandTruth
  T = buildCommandTruthState(A)
  result = resolveCommandTruth(T)

proc renderReportText(L: seq[string], ok: bool, okMsg: string, failMsg: string): string {.role(helper).} =
  ## L: report lines.
  ## ok: operation status.
  ## okMsg: message for success without report lines.
  ## failMsg: message for failure without report lines.
  if L.len == 0:
    if ok:
      return okMsg
    return failMsg
  result = L.join("\n")

proc readPaths(R: seq[RepoInfo]): seq[string] {.role(parser).} =
  ## R: repository metadata list.
  var
    i: int
  i = 0
  while i < R.len:
    result.add(R[i].path)
    inc i

proc readBranchMode(o: ToolingOptions): string {.role(actor).} =
  ## o: command options.
  var
    t: string
    options: seq[string]
    idx: int
  t = o.mode.strip().toLowerAscii()
  if t in ["main", "nightly", "promote"]:
    return t
  options = @[
    "Switch to main",
    "Switch to nightly",
    "Promote nightly to main"
  ]
  idx = promptOptions("Select branch action:", options)
  if idx < 0:
    return ""
  case idx
  of 0:
    result = "main"
  of 1:
    result = "nightly"
  else:
    result = "promote"

proc runCommand*(c: ToolingCommand, s: ToolingConfig, o: ToolingOptions): string {.role(metaOrchestrator).} =
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
    ironCount: int
    repo: RepoInfo
    i: int
    eReport: ExpandReport
    xReport: SubmoduleExtractReport
    gxReport: SubmoduleExtractGlobalReport
    sxReport: SubmoduleExternalizeReport
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
    initReport: RepoInitReport
    cloneReport: CloneRepoReport
    conflictReport: ConflictSessionReport
    syncReport: ConventionsSyncReport
    ironSyncReport: IronFileSyncReport
    configReport: CoordinatorConfigReport
    mode: string
    targetRepo: string
    ec: int
  case c
  of tcHelp:
    t = buildHelp()
  of tcInit:
    targetRepo = o.repo
    if o.cloneUrl.len > 0 and targetRepo == getCurrentDir():
      targetRepo = o.cloneUrl
    initReport = initRepoLayout(targetRepo, o.overwrite)
    t = renderReportText(initReport.lines, initReport.ok, "Init completed.", "Init failed.")
  of tcClone:
    cloneReport = cloneRepoWithiron(o.cloneUrl, o.root, o.overwrite, s.verbose)
    t = renderReportText(cloneReport.lines, cloneReport.ok, "Clone completed.", "Clone failed.")
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
      if repo.hasiron:
        ironCount = ironCount + 1
      inc i
    lines = @[
      "iron Tooling Status",
      "",
      buildRootsText(roots),
      "",
      "Repo count: " & $repos.len,
      "Repos with submodules: " & $subCount,
      "Repos with iron folder: " & $ironCount
    ]
    t = lines.join("\n")
  of tcScan:
    roots = resolveRoots(s)
    repos = discoverRepos(roots)
    lines = @[
      "iron Scan",
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
  of tcExternalize:
    if isGitRepo(normalizePathValue(o.repo)):
      sxReport = externalizeSubmodulesInRepo(o.repo, o.root, s.verbose)
    else:
      sxReport = externalizeSubmodulesFromRoots(o.root, s.verbose)
    t = renderReportText(sxReport.lines, sxReport.ok, "Externalize completed.", "Externalize failed.")
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
  of tcConflicts:
    conflictReport = runConflictsExplorer(o.root)
    t = renderReportText(conflictReport.lines, conflictReport.ok, "Conflicts command completed.", "Conflicts command failed.")
  of tcSyncConventions:
    syncReport = syncConventionsFromRoots(o.root)
    t = renderReportText(syncReport.lines, syncReport.ok, "Convention sync completed.", "Convention sync failed.")
  of tcSyncIronFile:
    ironSyncReport = syncIronFileFromRoots(o.root)
    t = renderReportText(ironSyncReport.lines, ironSyncReport.ok, "Iron file sync completed.", "Iron file sync failed.")
  of tcConfig:
    configReport = runCoordinatorConfigCommand(o)
    t = renderReportText(configReport.lines, configReport.ok, "Config completed.", "Config failed.")
  of tcVersion:
    t = ToolingVersion
  result = t
