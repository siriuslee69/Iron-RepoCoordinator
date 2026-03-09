# ==================================================
# | iron Repo Coordinator Conventions Sync   |
# |------------------------------------------------|
# | Sync canonical .iron/CONVENTIONS.md files      |
# | from Proto-RepoTemplate across local repos.    |
# ==================================================

import std/[os, strutils]
import ../level0/repo_utils


type
  ConventionsSyncReport* = object
    ok*: bool
    repos*: int
    updated*: int
    skipped*: int
    lines*: seq[string]


proc addLine(ls: var seq[string], l: string) =
  ## ls: line buffer.
  ## l: line to append.
  ls.add(l)

proc resolveConventionsSource*(rootOverride: string = ""): string =
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
      joinPath(root, "Proto-RepoTemplate", ".iron", "CONVENTIONS.md"),
      joinPath(root, "Proto-TemplateRepo", ".iron", "CONVENTIONS.md"),
      joinPath(root, "proto-conventions", ".iron", "CONVENTIONS.md")
    ]
    for c in cands:
      if fileExists(c):
        return c
  result = ""

proc syncConventionsInRepo(repo: string, sourcePath: string,
                           report: var ConventionsSyncReport) =
  ## repo: target repository root.
  ## sourcePath: canonical conventions file path.
  ## report: report object.
  var
    meta: string
    target: string
    srcText: string
    dstText: string
  meta = joinPath(repo, ironDir)
  if not dirExists(meta):
    return
  inc report.repos
  target = joinPath(meta, "CONVENTIONS.md")
  srcText = readFile(sourcePath)
  if fileExists(target):
    dstText = readFile(target)
    if dstText == srcText:
      inc report.skipped
      return
  writeFile(target, srcText)
  inc report.updated
  addLine(report.lines, "Updated conventions in " & repo)

proc syncConventionsFromRoots*(rootOverride: string = ""): ConventionsSyncReport =
  ## rootOverride: optional root directory override.
  var
    report: ConventionsSyncReport
    sourcePath: string
    repos: seq[string]
  report.ok = true
  sourcePath = resolveConventionsSource(rootOverride)
  if sourcePath.len == 0:
    report.ok = false
    addLine(report.lines, "Could not locate Proto-RepoTemplate/.iron/CONVENTIONS.md.")
    return report
  repos = collectRepos(if rootOverride.strip().len > 0: @[normalizePathValue(rootOverride)] else: getRoots())
  if repos.len == 0:
    report.ok = false
    addLine(report.lines, "No repos found.")
    return report
  if not confirmEnter("Sync .iron/CONVENTIONS.md across repos under roots?"):
    report.ok = false
    addLine(report.lines, "Sync cancelled by user.")
    return report
  addLine(report.lines, "Source: " & sourcePath)
  for repo in repos:
    syncConventionsInRepo(repo, sourcePath, report)
  addLine(report.lines, "Repos scanned: " & $report.repos)
  addLine(report.lines, "Updated: " & $report.updated)
  addLine(report.lines, "Unchanged: " & $report.skipped)
  result = report
