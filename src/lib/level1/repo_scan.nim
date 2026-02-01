# Valkyrie Tooling | repo scanning
# Root discovery and repository listing helpers.

import std/[os, sets, strutils]
import ../level0/types

proc parseRoots*(r: string): seq[string] =
  ## r: raw roots value (env or config)
  var
    t: seq[string]
    tSep: char
    tParts: seq[string]
    tPart: string
    tClean: string
    i: int
  if r.len == 0:
    result = @[]
    return
  if r.contains(';'):
    tSep = ';'
    tParts = r.split(tSep)
  elif r.contains(":\\") or r.contains(":/"):
    tParts = @[r]
  else:
    tSep = ':'
    tParts = r.split(tSep)
  i = 0
  while i < tParts.len:
    tPart = tParts[i]
    tClean = tPart.strip()
    if tClean.len > 0:
      t.add(tClean)
    inc i
  result = t

proc normalizeRoots*(rs: seq[string]): seq[string] =
  ## rs: raw root directories
  var
    t: seq[string]
    tSeen: HashSet[string]
    tRoot: string
    tAbs: string
    i: int
  tSeen = initHashSet[string]()
  i = 0
  while i < rs.len:
    tRoot = rs[i]
    tAbs = tRoot.strip()
    if tAbs.len == 0:
      inc i
      continue
    tAbs = absolutePath(tAbs)
    if not dirExists(tAbs):
      inc i
      continue
    if not tSeen.contains(tAbs):
      tSeen.incl(tAbs)
      t.add(tAbs)
    inc i
  result = t

proc defaultRoots*(r: string): seq[string] =
  ## r: base directory used to derive defaults
  var
    t: seq[string]
    tParent: string
    tBase: string
    tSibling: string
  tParent = parentDir(r)
  if dirExists(tParent):
    t.add(tParent)
  tBase = parentDir(tParent)
  tSibling = joinPath(tBase, "Coding")
  if dirExists(tSibling):
    t.add(tSibling)
  result = t

proc loadEnvRoots*(e: string): seq[string] =
  ## e: environment variable to read
  var
    tVal: string
  if existsEnv(e):
    tVal = getEnv(e)
    result = parseRoots(tVal)
  else:
    result = @[]

proc resolveRoots*(s: ToolingConfig): seq[string] =
  ## s: tooling configuration
  var
    tRoots: seq[string]
    tEnv: seq[string]
  tEnv = loadEnvRoots("VALKYRIE_ROOTS")
  if tEnv.len == 0:
    tEnv = loadEnvRoots("JRC_ROOTS")
  if tEnv.len == 0:
    tRoots = defaultRoots(s.rootDir)
  else:
    tRoots = tEnv
  tRoots = normalizeRoots(tRoots)
  result = tRoots

proc hasGitDir(p: string): bool =
  ## p: repo path to inspect
  var
    tGit: string
  tGit = joinPath(p, ".git")
  result = dirExists(tGit) or fileExists(tGit)

proc hasSubmodulesFile(p: string): bool =
  ## p: repo path to inspect
  var
    tPath: string
  tPath = joinPath(p, ".gitmodules")
  result = fileExists(tPath)

proc hasValkyrieFolder(p: string): bool =
  ## p: repo path to inspect
  var
    tPath: string
  tPath = joinPath(p, "valkyrie")
  result = dirExists(tPath)

proc collectReposInRoot*(r: string): seq[RepoInfo] =
  ## r: root directory to scan
  var
    tRepos: seq[RepoInfo]
    tSplit: tuple[head: string, tail: string]
    tInfo: RepoInfo
  if not dirExists(r):
    result = @[]
    return
  for tKind, tPath in walkDir(r):
    if tKind != pcDir:
      continue
    tSplit = splitPath(tPath)
    if tSplit.head != r:
      continue
    if not hasGitDir(tPath):
      continue
    tInfo = RepoInfo()
    tInfo.name = tSplit.tail
    tInfo.path = tPath
    tInfo.hasGit = true
    tInfo.hasSubmodules = hasSubmodulesFile(tPath)
    tInfo.hasValkyrie = hasValkyrieFolder(tPath)
    tRepos.add(tInfo)
  result = tRepos

proc discoverRepos*(rs: seq[string]): seq[RepoInfo] =
  ## rs: root directories to scan
  var
    tRepos: seq[RepoInfo]
    tSeen: HashSet[string]
    tRoot: string
    tRootRepos: seq[RepoInfo]
    tRepo: RepoInfo
    i: int
    j: int
  tSeen = initHashSet[string]()
  i = 0
  while i < rs.len:
    tRoot = rs[i]
    tRootRepos = collectReposInRoot(tRoot)
    j = 0
    while j < tRootRepos.len:
      tRepo = tRootRepos[j]
      if not tSeen.contains(tRepo.path):
        tSeen.incl(tRepo.path)
        tRepos.add(tRepo)
      inc j
    inc i
  result = tRepos

proc repoLine*(r: RepoInfo, v: bool): string =
  ## r: repository info
  ## v: verbose output toggle
  var
    tLine: string
    tFlags: seq[string]
  tLine = r.name
  if v:
    tLine = tLine & " | " & r.path
  if r.hasSubmodules:
    tFlags.add("submodules")
  if r.hasValkyrie:
    tFlags.add("valkyrie")
  if tFlags.len > 0:
    tLine = tLine & " [" & tFlags.join(", ") & "]"
  result = tLine

proc buildRootsText*(rs: seq[string]): string =
  ## rs: root directories
  var
    tLines: seq[string]
    r: string
    i: int
  tLines = @["Roots:"]
  if rs.len == 0:
    tLines.add(" (none)")
  else:
    i = 0
    while i < rs.len:
      r = rs[i]
      tLines.add(" - " & r)
      inc i
  result = tLines.join("\n")

proc buildReposText*(rs: seq[RepoInfo], v: bool): string =
  ## rs: repository list
  ## v: verbose output toggle
  var
    tLines: seq[string]
    r: RepoInfo
    i: int
  if rs.len == 0:
    result = "Repos: (none)"
    return
  tLines = @["Repos:"]
  i = 0
  while i < rs.len:
    r = rs[i]
    tLines.add(" - " & repoLine(r, v))
    inc i
  result = tLines.join("\n")
