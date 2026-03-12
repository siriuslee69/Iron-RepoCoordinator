# ==================================================
# | iron Repo Coordinator .iron Sync         |
# |------------------------------------------------|
# | Sync canonical .iron files from the template   |
# | repo across local repositories.                |
# ==================================================

import std/[algorithm, os, strutils, terminal]
import ../level0/repo_utils
include ../level0/metaPragmas


type
  IronFileSyncReport* = object
    ok*: bool
    repos*: int
    updated*: int
    skipped*: int
    lines*: seq[string]
    sourcePath*: string
    relativePath*: string

  ConventionsSyncReport* = IronFileSyncReport


const
  SyncableConventionsNames = ["conventions.md", "CONVENTIONS.md"]


proc addLine(ls: var seq[string], l: string) {.role(helper).} =
  ## ls: line buffer.
  ## l: line to append.
  ls.add(l)

proc resolveCanonicalIronDir*(rootOverride: string = ""): string {.role(parser).} =
  ## rootOverride: optional root directory to prefer when locating the canonical repo.
  var
    roots: seq[string]
    root: string
    cands: seq[string]
  if rootOverride.strip().len > 0:
    roots = @[normalizePathValue(rootOverride)]
  else:
    roots = getRoots()
  for r in roots:
    root = normalizePathValue(r)
    cands = @[
      joinPath(root, "Proto-RepoTemplate", ".iron"),
      joinPath(root, "Proto-TemplateRepo", ".iron"),
      joinPath(root, "proto-conventions", ".iron")
    ]
    for c in cands:
      if dirExists(c):
        return c
  result = ""

proc ironFileSyncAllowed(relPath: string): bool {.role(parser).} =
  ## relPath: source .iron-relative file path.
  var
    t: string
  t = relPath.replace('\\', '/').strip()
  if t.len == 0:
    return false
  if t.startsWith("docs/"):
    return false
  case t.toLowerAscii()
  of "progress.md", "repo_coordinator.toml", ".local.config.toml", ".local.gitmodules.toml":
    return false
  else:
    discard
  result = true

proc readSyncableIronFiles*(rootOverride: string = ""): seq[string] {.role(truthBuilder).} =
  ## rootOverride: optional root directory to prefer when locating the canonical repo.
  var
    metaDir: string
    relPath: string
  metaDir = resolveCanonicalIronDir(rootOverride)
  if metaDir.len == 0 or not dirExists(metaDir):
    return @[]
  for path in walkDirRec(metaDir):
    if not fileExists(path):
      continue
    relPath = relativePath(path, metaDir).replace('\\', '/')
    if ironFileSyncAllowed(relPath):
      result.add(relPath)
  result.sort(system.cmp[string])

proc resolveConventionsSource*(rootOverride: string = ""): string {.role(parser).} =
  ## rootOverride: optional root directory to prefer when locating the canonical repo.
  var
    metaDir: string
    i: int
  metaDir = resolveCanonicalIronDir(rootOverride)
  if metaDir.len == 0:
    return ""
  i = 0
  while i < SyncableConventionsNames.len:
    result = joinPath(metaDir, SyncableConventionsNames[i])
    if fileExists(result):
      return result
    inc i
  result = ""

proc selectIronFileForSync(rootOverride: string = ""): string {.role(actor).} =
  ## rootOverride: optional root directory to prefer when locating the canonical repo.
  let files = readSyncableIronFiles(rootOverride)
  let idx = promptOptionsDefault("Select .iron file to sync:", files, 0)
  if idx < 0:
    return ""
  result = files[idx]

proc resolveSourceRelativePath(relativePath: string, rootOverride: string = ""): string {.role(parser).} =
  ## relativePath: .iron-relative path to locate in the canonical source directory.
  ## rootOverride: optional root directory to prefer when locating the canonical repo.
  let metaDir = resolveCanonicalIronDir(rootOverride)
  if metaDir.len == 0:
    return ""
  result = joinPath(metaDir, relativePath.replace('/', DirSep).replace('\\', DirSep))
  if not fileExists(result):
    result = ""

proc resolveTargetIronPath(repo: string, relativePath: string): string {.role(helper).} =
  ## repo: target repository root.
  ## relativePath: .iron-relative file path to write.
  result = joinPath(repo, ironDir, relativePath.replace('/', DirSep).replace('\\', DirSep))

proc syncIronFileInRepo(repo: string, relativePath: string, sourcePath: string,
                        report: var IronFileSyncReport) {.role(helper).} =
  ## repo: target repository root.
  ## relativePath: .iron-relative file path to sync.
  ## sourcePath: canonical source file path.
  ## report: sync report accumulator.
  var
    meta: string
    target: string
    srcText: string
    dstText: string
  meta = joinPath(repo, ironDir)
  if not dirExists(meta):
    return
  inc report.repos
  target = resolveTargetIronPath(repo, relativePath)
  srcText = readFile(sourcePath)
  if fileExists(target):
    dstText = readFile(target)
    if dstText == srcText:
      inc report.skipped
      return
  ensureParentDir(target)
  writeFile(target, srcText)
  inc report.updated
  addLine(report.lines, "Updated .iron/" & relativePath & " in " & repo)

proc syncIronFileFromRoots*(rootOverride: string = "",
                            relativePath: string = ""): IronFileSyncReport {.role(orchestrator).} =
  ## rootOverride: optional root directory override.
  ## relativePath: optional .iron-relative file path to sync.
  var
    repos: seq[string]
    relPath: string
    sourcePath: string
  result.ok = true
  relPath = relativePath.replace('\\', '/').strip()
  if relPath.len == 0:
    if not isatty(stdin):
      result.ok = false
      addLine(result.lines, "No .iron file selected and terminal selection is unavailable.")
      return
    relPath = selectIronFileForSync(rootOverride)
    if relPath.len == 0:
      result.ok = false
      addLine(result.lines, "Sync cancelled by user.")
      return
  sourcePath = resolveSourceRelativePath(relPath, rootOverride)
  if sourcePath.len == 0:
    result.ok = false
    addLine(result.lines, "Could not locate canonical .iron/" & relPath & ".")
    return
  repos = collectRepos(if rootOverride.strip().len > 0: @[normalizePathValue(rootOverride)] else: getRoots())
  if repos.len == 0:
    result.ok = false
    addLine(result.lines, "No repos found.")
    return
  if not confirmEnter("Sync .iron/" & relPath & " across repos under roots?"):
    result.ok = false
    addLine(result.lines, "Sync cancelled by user.")
    return
  result.relativePath = relPath
  result.sourcePath = sourcePath
  addLine(result.lines, "Source: " & sourcePath)
  for repo in repos:
    syncIronFileInRepo(repo, relPath, sourcePath, result)
  addLine(result.lines, "Repos scanned: " & $result.repos)
  addLine(result.lines, "Updated: " & $result.updated)
  addLine(result.lines, "Unchanged: " & $result.skipped)

proc syncConventionsFromRoots*(rootOverride: string = ""): ConventionsSyncReport {.role(orchestrator).} =
  ## rootOverride: optional root directory override.
  var
    sourcePath: string
    relPath: string
  sourcePath = resolveConventionsSource(rootOverride)
  if sourcePath.len == 0:
    result.ok = false
    addLine(result.lines, "Could not locate canonical .iron/conventions.md.")
    return
  relPath = relativePath(sourcePath, parentDir(sourcePath)).replace('\\', '/')
  result = syncIronFileFromRoots(rootOverride, relPath)
