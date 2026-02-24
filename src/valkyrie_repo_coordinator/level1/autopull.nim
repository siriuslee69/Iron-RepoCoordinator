# ==================================================
# | Valkyrie Repo Coordinator Autopull Helper   |
# |------------------------------------------------|
# | Pull all repos under configured roots.         |
# ==================================================

import std/[strutils, osproc]
import ../level0/repo_utils


type
  AutoPullReport* = object
    ok*: bool
    repos*: int
    pulled*: int
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

proc hasRemote(r: string): bool =
  ## r: repo path to check for remotes.
  var t: tuple[text: string, code: int] = runGit(r, "remote")
  result = t.code == 0 and t.text.strip().len > 0

proc runPull(r: string): int =
  ## r: repo path to pull.
  var c: string = "git -C " & quoteShell(r) & " pull --ff-only"
  result = execCmd(c)

proc autoPullFromRoots*(d: bool): AutoPullReport =
  ## d: dry-run flag.
  var
    rReport: AutoPullReport
    rs: seq[string]
    r: string
    i: int
  rReport.ok = true
  rs = collectReposFromRoots()
  rReport.repos = rs.len
  if rs.len == 0:
    addLine(rReport.lines, "No repos found.")
    result = rReport
    return
  if not d:
    if not confirmEnter("Pull updates for " & $rs.len & " repos?"):
      rReport.ok = false
      addLine(rReport.lines, "Autopull cancelled by user.")
      result = rReport
      return
  addLine(rReport.lines, "Found " & $rs.len & " repos.")
  i = 0
  while i < rs.len:
    r = rs[i]
    addLine(rReport.lines, "==> " & r)
    if not isGitRepo(r):
      addLine(rReport.lines, "  Not a git repo, skipping.")
      rReport.skipped = rReport.skipped + 1
      inc i
      continue
    if not hasRemote(r):
      addLine(rReport.lines, "  No remote, skipping.")
      rReport.skipped = rReport.skipped + 1
      inc i
      continue
    if d:
      addLine(rReport.lines, "  Dry-run.")
      inc i
      continue
    if runPull(r) != 0:
      rReport.ok = false
      addLine(rReport.lines, "  Pull failed.")
      rReport.skipped = rReport.skipped + 1
      inc i
      continue
    addLine(rReport.lines, "  Pulled.")
    rReport.pulled = rReport.pulled + 1
    inc i
  addLine(rReport.lines, "Pulled repos: " & $rReport.pulled)
  addLine(rReport.lines, "Skipped repos: " & $rReport.skipped)
  result = rReport
