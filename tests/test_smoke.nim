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
