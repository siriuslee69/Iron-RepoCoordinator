# iron Tooling | smoke tests
# Basic checks for core command routing and repo scanning.

import std/[os, random, strutils, times, unittest]
import iron_tooling
include ../src/lib/level0/metaPragmas

proc newTempRoot(p: string): string {.role(helper).} =
  ## p: test prefix
  var
    tBase: string
    tStamp: string
    tRand: int
    tPath: string
  randomize()
  tBase = getTempDir()
  tStamp = $getTime().toUnix()
  tRand = rand(1_000_000)
  tPath = joinPath(tBase, p & "_" & tStamp & "_" & $tRand)
  createDir(tPath)
  result = tPath

proc removeTree(p: string) {.role(actor).} =
  ## p: root path to remove
  var
    tEntries: seq[(PathComponent, string)]
    tKind: PathComponent
    tPath: string
    i: int
  if not dirExists(p):
    return
  for tKind, tPath in walkDir(p):
    tEntries.add((tKind, tPath))
  i = tEntries.len - 1
  while i >= 0:
    tKind = tEntries[i][0]
    tPath = tEntries[i][1]
    case tKind
    of pcFile, pcLinkToFile:
      removeFile(tPath)
    of pcDir:
      removeDir(tPath)
    else:
      discard
    dec i
  if dirExists(p):
    removeDir(p)

suite "iron tooling":
  test "parseCommand help":
    var
      cs: seq[string]
      c: ToolingCommand
    cs = @[]
    c = parseCommand(cs)
    check c == tcHelp

  test "runCommand version":
    var
      s: ToolingConfig
      o: ToolingOptions
      t: string
    s = defaultConfig()
    o = defaultOptions()
    t = runCommand(tcVersion, s, o)
    check t.contains("iron-Tooling")

  test "parseCommand expand":
    var
      cs: seq[string]
      c: ToolingCommand
    cs = @["expand"]
    c = parseCommand(cs)
    check c == tcExpand

  test "parseCommand docs and show":
    var
      c: ToolingCommand
    c = parseCommand(@["docs"])
    check c == tcDocs
    c = parseCommand(@["docs-init"])
    check c == tcDocsInit
    c = parseCommand(@["show"])
    check c == tcShow
    c = parseCommand(@["--", "show"])
    check c == tcShow
    c = parseCommand(@["sync-iron-file"])
    check c == tcSyncIronFile
    c = parseCommand(@["config"])
    check c == tcConfig

  test "command truth suggests likely command":
    var
      t: ToolingCommandTruth
      i: int
      hasPushAll: bool
    t = buildCommandTruthState(@["pushal"])
    check not t.recognized
    check t.suggestions.len > 0
    i = 0
    while i < t.suggestions.len:
      if t.suggestions[i].command == tcPushAll:
        hasPushAll = true
      inc i
    check hasPushAll

  test "parseOptions for extract":
    var
      cs: seq[string]
      o: ToolingOptions
    cs = @[
      "extract",
      "--repo=F:/CodingMain/RepoA",
      "--root",
      "F:/CodingMain",
      "--replace",
      "--dry-run"
    ]
    o = parseOptions(cs)
    check o.repo == "F:/CodingMain/RepoA"
    check o.root == "F:/CodingMain"
    check o.replace
    check o.dryRun

  test "parseOptions docs/show flags":
    var
      cs: seq[string]
      o: ToolingOptions
    cs = @[
      "show",
      "--repo=F:/CodingMain/RepoA",
      "--pipeline=.iron/pipeline.toml",
      "--interval-ms=333",
      "--loops=4",
      "--once",
      "--overwrite",
      "--src=src",
      "--docs-out=.iron/docs/library_api.md"
    ]
    o = parseOptions(cs)
    check o.repo == "F:/CodingMain/RepoA"
    check o.pipelinePath == ".iron/pipeline.toml"
    check o.intervalMs == 333
    check o.loops == 4
    check o.once
    check o.overwrite
    check o.srcPath == "src"
    check o.docsOut == ".iron/docs/library_api.md"

  test "parseOptions config flags":
    var
      cs: seq[string]
      o: ToolingOptions
    cs = @[
      "config",
      "--owners=siriuslee69,alpha",
      "--add-owner",
      "beta",
      "--remove-owner=gamma",
      "--exclude-repos",
      "RepoA,F:/CodingMain/RepoB",
      "--add-exclude=RepoC",
      "--remove-exclude",
      "RepoD",
      "--foreign-mode",
      "skip"
    ]
    o = parseOptions(cs)
    check o.configOwners == "siriuslee69,alpha"
    check o.configAddOwner == "beta"
    check o.configRemoveOwner == "gamma"
    check o.configExcludedRepos == "RepoA,F:/CodingMain/RepoB"
    check o.configAddExcludedRepo == "RepoC"
    check o.configRemoveExcludedRepo == "RepoD"
    check o.configForeignMode == "skip"

  test "parseRoots windows drive":
    var
      r: seq[string]
    r = parseRoots("F:\\CodingMain")
    check r.len == 1
    check r[0] == "F:\\CodingMain"

  test "discoverRepos finds git dirs and files":
    var
      tRoot: string
      tRepoA: string
      tRepoB: string
      tRepos: seq[RepoInfo]
      tHasA: bool
      tHasB: bool
      tHasSub: bool
      tHasIron: bool
      tRepo: RepoInfo
      i: int
    tRoot = newTempRoot("iron_scan")
    try:
      tRepoA = joinPath(tRoot, "RepoA")
      tRepoB = joinPath(tRoot, "RepoB")
      createDir(tRepoA)
      createDir(tRepoB)
      createDir(joinPath(tRepoA, ".git"))
      writeFile(joinPath(tRepoB, ".git"), "gitdir: ../.git/modules/RepoB")
      writeFile(joinPath(tRepoB, ".gitmodules"), "[submodule \"x\"]")
      createDir(joinPath(tRepoA, ".iron"))
      tRepos = discoverRepos(@[tRoot])
      i = 0
      while i < tRepos.len:
        tRepo = tRepos[i]
        if tRepo.name == "RepoA":
          tHasA = true
          tHasIron = tRepo.hasiron
        if tRepo.name == "RepoB":
          tHasB = true
          tHasSub = tRepo.hasSubmodules
        inc i
      check tHasA
      check tHasB
      check tHasSub
      check tHasIron
    finally:
      removeTree(tRoot)

  test "collectRepos skips nested repo markers inside repos":
    var
      tRoot: string
      tOwnerRepo: string
      tNestedRepo: string
      tRepos: seq[string]
    tRoot = newTempRoot("iron_nested")
    try:
      tOwnerRepo = joinPath(tRoot, "OwnerRepo")
      tNestedRepo = joinPath(tOwnerRepo, "submodules", "NestedRepo")
      createDir(tOwnerRepo)
      createDir(tNestedRepo)
      createDir(joinPath(tOwnerRepo, ".git"))
      createDir(joinPath(tNestedRepo, ".git"))
      tRepos = collectRepos(@[tRoot])
      check tRepos.len == 1
      check normalizePathValue(tRepos[0]) == normalizePathValue(tOwnerRepo)
    finally:
      removeTree(tRoot)

  test "docs-init scaffold and docs generation":
    var
      tRoot: string
      tSrc: string
      tModule: string
      initReport: DocsInitReport
      docsReport: LibraryDocsReport
      mdText: string
      jsonText: string
    tRoot = newTempRoot("iron_docs")
    try:
      createDir(joinPath(tRoot, ".iron"))
      tSrc = joinPath(tRoot, "src")
      createDir(tSrc)
      tModule = joinPath(tSrc, "sample_lib.nim")
      writeFile(tModule, """
# Sample module
import std/strutils

proc greet*(name: string): string =
  ## name: caller name.
  result = "Hello, " & name.strip()

proc helper(x: int): int =
  result = x + 1
""")
      initReport = initDocsScaffold(tRoot, false)
      check initReport.ok
      check fileExists(joinPath(tRoot, ".iron", "pipeline.toml"))
      check fileExists(joinPath(tRoot, ".iron", "docs_instructionset.md"))
      docsReport = generateLibraryDocs(tRoot, "", "")
      check docsReport.ok
      check fileExists(docsReport.markdownPath)
      check fileExists(docsReport.jsonPath)
      mdText = readFile(docsReport.markdownPath)
      jsonText = readFile(docsReport.jsonPath)
      check mdText.contains("sample_lib.nim")
      check mdText.contains("greet*")
      check jsonText.contains("\"name\": \"greet\"")
    finally:
      removeTree(tRoot)

  test "pipeline parse and render":
    var
      tRoot: string
      tIronDir: string
      tPipeline: string
      parseResult: PipelineParseResult
      frameText: string
      resolved: string
    tRoot = newTempRoot("iron_pipeline")
    try:
      tIronDir = joinPath(tRoot, ".iron")
      createDir(tIronDir)
      tPipeline = joinPath(tIronDir, "pipeline.toml")
      writeFile(tPipeline, """
name = "Test Pipeline"
interval_ms = 250
root_id = "root"

[[nodes]]
id = "root"
label = "Root Step"
status = "active"
details = ""
parent = ""

[[nodes]]
id = "child_a"
label = "Child A"
status = "todo"
details = ""
parent = "root"
""")
      resolved = resolvePipelinePath(tRoot, "")
      check resolved == tPipeline
      parseResult = readPipelineSpec(tPipeline)
      check parseResult.ok
      check parseResult.spec.name == "Test Pipeline"
      frameText = renderPipelineFrame(parseResult.spec, 2, tPipeline)
      check frameText.contains("Root Step")
      check frameText.contains("Child A")
      check frameText.contains("RUN")
    finally:
      removeTree(tRoot)
