# Valkyrie Tooling | smoke tests
# Basic checks for core command routing and repo scanning.

import std/[os, random, strutils, times, unittest]
import valkyrie_tooling

proc newTempRoot(p: string): string =
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

proc removeTree(p: string) =
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

suite "valkyrie tooling":
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
    check t.contains("Valkyrie-Tooling")

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
      "--pipeline=valk/pipeline.json",
      "--interval-ms=333",
      "--loops=4",
      "--once",
      "--overwrite",
      "--src=src",
      "--docs-out=valk/docs/library_api.md"
    ]
    o = parseOptions(cs)
    check o.repo == "F:/CodingMain/RepoA"
    check o.pipelinePath == "valk/pipeline.json"
    check o.intervalMs == 333
    check o.loops == 4
    check o.once
    check o.overwrite
    check o.srcPath == "src"
    check o.docsOut == "valk/docs/library_api.md"

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
      tHasValk: bool
      tRepo: RepoInfo
      i: int
    tRoot = newTempRoot("valkyrie_scan")
    try:
      tRepoA = joinPath(tRoot, "RepoA")
      tRepoB = joinPath(tRoot, "RepoB")
      createDir(tRepoA)
      createDir(tRepoB)
      createDir(joinPath(tRepoA, ".git"))
      writeFile(joinPath(tRepoB, ".git"), "gitdir: ../.git/modules/RepoB")
      writeFile(joinPath(tRepoB, ".gitmodules"), "[submodule \"x\"]")
      createDir(joinPath(tRepoA, "valkyrie"))
      tRepos = discoverRepos(@[tRoot])
      i = 0
      while i < tRepos.len:
        tRepo = tRepos[i]
        if tRepo.name == "RepoA":
          tHasA = true
          tHasValk = tRepo.hasValkyrie
        if tRepo.name == "RepoB":
          tHasB = true
          tHasSub = tRepo.hasSubmodules
        inc i
      check tHasA
      check tHasB
      check tHasSub
      check tHasValk
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
    tRoot = newTempRoot("valkyrie_docs")
    try:
      createDir(joinPath(tRoot, "valk"))
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
      check fileExists(joinPath(tRoot, "valk", "pipeline.json"))
      check fileExists(joinPath(tRoot, "valk", "docs_instructionset.md"))
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
      tValk: string
      tPipeline: string
      parseResult: PipelineParseResult
      frameText: string
      resolved: string
    tRoot = newTempRoot("valkyrie_pipeline")
    try:
      tValk = joinPath(tRoot, "valk")
      createDir(tValk)
      tPipeline = joinPath(tValk, "pipeline.json")
      writeFile(tPipeline, """
{
  "name": "Test Pipeline",
  "intervalMs": 250,
  "root": {
    "id": "root",
    "label": "Root Step",
    "status": "active",
    "children": [
      {
        "id": "child_a",
        "label": "Child A",
        "status": "todo",
        "children": []
      }
    ]
  }
}
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
