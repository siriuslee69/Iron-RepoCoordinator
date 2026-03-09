# ==================================================
# | iron Repo Coordinator Submodule Finder  |
# |------------------------------------------------|
# | Build local submodule overrides under roots.   |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils
import submodule_links


type
  FindLocalSubmodulesReport* = object
    ok*: bool
    repos*: int
    updated*: int
    linked*: int
    skipped*: int
    lines*: seq[string]


proc addLine(ls: var seq[string], l: string) =
  ## ls: line buffer.
  ## l: line to append.
  ls.add(l)

proc runCmd(c: string): tuple[text: string, code: int] =
  ## c: command to execute.
  var
    tText: string
    tCode: int
  (tText, tCode) = execCmdEx(c)
  result = (tText, tCode)

proc runGit(r, a: string): tuple[text: string, code: int] =
  ## r: repo path.
  ## a: git arguments.
  var c: string = "git -C " & quoteShell(r) & " " & a
  result = runCmd(c)

proc isGitRepo(r: string): bool =
  ## r: repo path to validate.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --is-inside-work-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc processRepo(r: string, rs: seq[string], d: bool, tReport: var FindLocalSubmodulesReport) =
  ## r: repo path to process.
  ## rs: known repo list for matching local clones.
  ## d: dry-run flag.
  ## tReport: report object to update.
  var
    gm: string
    gl: string
    ms: seq[SubmoduleInfo]
    ls: seq[SubmoduleInfo]
    linkReport: SubmoduleLinkReport
  gm = joinPath(r, ".gitmodules")
  gl = joinPath(r, LocalModulesFile)
  if not fileExists(gm):
    return
  ms = readSubmodules(gm)
  if ms.len == 0:
    return
  ls = mapLocalSubmodules(ms, rs, r)
  if ls.len == 0:
    addLine(tReport.lines, "  No local matches.")
    tReport.skipped = tReport.skipped + 1
    return
  if d:
    addLine(tReport.lines, "  Would write local overrides for " & $ls.len & " submodules.")
    tReport.linked = tReport.linked + ls.len
    return
  if ensureLocalIgnoreRules(r):
    addLine(tReport.lines, "  Updated .gitignore")
    tReport.updated = tReport.updated + 1
  writeLocalModules(gl, ls)
  if applyLocalConfig(r, ls) != 0:
    tReport.ok = false
    addLine(tReport.lines, "  Failed to update git config.")
    return
  linkReport = linkConfiguredSubmodules(r, ls, true)
  if not linkReport.ok:
    tReport.ok = false
  for line in linkReport.lines:
    addLine(tReport.lines, "  " & line)
  tReport.linked = tReport.linked + linkReport.linked
  tReport.updated = tReport.updated + 1

proc findLocalSubmodulesFromRoots*(d: bool): FindLocalSubmodulesReport =
  ## d: dry-run flag.
  var
    tReport: FindLocalSubmodulesReport
    rs: seq[string]
    r: string
    i: int
  tReport.ok = true
  rs = collectReposFromRoots()
  tReport.repos = rs.len
  if rs.len == 0:
    addLine(tReport.lines, "No repos found.")
    result = tReport
    return
  if not d:
    if not confirmEnter("Apply local submodule overrides under roots?"):
      tReport.ok = false
      addLine(tReport.lines, "Find cancelled by user.")
      result = tReport
      return
  addLine(tReport.lines, "Found " & $rs.len & " repos.")
  i = 0
  while i < rs.len:
    r = rs[i]
    if not isGitRepo(r):
      inc i
      continue
    addLine(tReport.lines, "==> " & r)
    processRepo(r, rs, d, tReport)
    inc i
  addLine(tReport.lines, "Updated repos: " & $tReport.updated)
  addLine(tReport.lines, "Linked submodules: " & $tReport.linked)
  addLine(tReport.lines, "Skipped repos: " & $tReport.skipped)
  result = tReport
