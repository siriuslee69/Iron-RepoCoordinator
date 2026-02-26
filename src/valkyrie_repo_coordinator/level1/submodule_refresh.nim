# ==================================================
# | Valkyrie Repo Coordinator Submodule Refresh |
# |------------------------------------------------|
# | Stash local changes in submodules and pull     |
# | latest main branch.                            |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils


type
  SubmoduleRefreshReport* = object
    ok*: bool
    stashed*: int
    updated*: int
    lines*: seq[string]


proc addLine(ls: var seq[string], l: string) =
  ## ls: line buffer.
  ## l: line to append.
  ls.add(l)

proc runCmd(c: string): tuple[text: string, code: int] =
  ## c: command to execute.
  var tText: string
  var ec: int
  (tText, ec) = execCmdEx(c)
  result = (tText, ec)

proc runGit(r, a: string): tuple[text: string, code: int] =
  ## r: repo path.
  ## a: git arguments to execute.
  var c: string = "git -C " & quoteShell(r) & " " & a
  result = runCmd(c)

proc isGitRepo(r: string): bool =
  ## r: repo path to validate.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --is-inside-work-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc hasChanges(r: string): bool =
  ## r: repo path to check for local changes.
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain")
  result = t.code == 0 and t.text.strip().len > 0

proc runStash(r: string): int =
  ## r: repo path to stash.
  var c: string = "git -C " & quoteShell(r) & " stash push -u -m \"Valkyrie submodule stash\""
  result = execCmd(c)

proc runCheckoutMain(r: string): int =
  ## r: repo path to checkout main (create tracking if needed).
  var c: string = "git -C " & quoteShell(r) & " checkout -B main origin/main"
  result = execCmd(c)

proc runPull(r: string): int =
  ## r: repo path to pull.
  var c: string = "git -C " & quoteShell(r) & " pull --ff-only"
  result = execCmd(c)

proc runFetch(r: string): int =
  ## r: repo path to fetch.
  var c: string = "git -C " & quoteShell(r) & " fetch origin"
  result = execCmd(c)

proc refreshSubmodules*(): SubmoduleRefreshReport =
  var
    report: SubmoduleRefreshReport
    rs: seq[string]
    cfg: CoordinatorConfig
    owner: string
    gm: string
    ms: seq[SubmoduleInfo]
    subPath: string
    idx: int
  report.ok = true
  cfg = readCoordinatorConfig(resolveConfigRoot(getCurrentDir()))
  rs = collectReposFromRoots()
  addLine(report.lines, "Found " & $rs.len & " repos.")
  if not confirmEnter("Stash local changes and pull submodules under roots?"):
    report.ok = false
    addLine(report.lines, "Refresh cancelled by user.")
    return report
  for repo in rs:
    if not isGitRepo(repo):
      continue
    gm = joinPath(repo, ".gitmodules")
    if not fileExists(gm):
      continue
    ms = readSubmodules(gm)
    if ms.len == 0:
      continue
    addLine(report.lines, "==> " & repo)
    for m in ms:
      if m.path.len == 0:
        continue
      subPath = joinPath(repo, m.path)
      if not dirExists(subPath):
        addLine(report.lines, "  Missing submodule: " & m.path)
        report.ok = false
        continue
      if not isGitRepo(subPath):
        addLine(report.lines, "  Not a git repo: " & m.path)
        report.ok = false
        continue
      owner = resolveRepoOwner(subPath)
      if not ownerUpdateAllowed(cfg, owner):
        addLine(report.lines, "  Owner not allowed, skipping: " & m.path)
        continue
      addLine(report.lines, "  -> " & m.path)
      if hasChanges(subPath):
        idx = promptOptions("Submodule has changes: " & m.path, @[
          "Stash changes and update",
          "Skip this submodule"
        ])
        if idx < 0:
          report.ok = false
          addLine(report.lines, "Refresh aborted by user.")
          return report
        if idx == 1:
          addLine(report.lines, "    Skipped by user.")
          continue
        if runStash(subPath) != 0:
          addLine(report.lines, "    Stash failed.")
          report.ok = false
          continue
        inc report.stashed
      if runFetch(subPath) != 0:
        addLine(report.lines, "    Fetch failed.")
        report.ok = false
        continue
      if runCheckoutMain(subPath) != 0:
        addLine(report.lines, "    Checkout main failed.")
        report.ok = false
        continue
      if runPull(subPath) != 0:
        addLine(report.lines, "    Pull failed.")
        report.ok = false
        continue
      inc report.updated
  addLine(report.lines, "Stashed submodules: " & $report.stashed)
  addLine(report.lines, "Updated submodules: " & $report.updated)
  result = report
