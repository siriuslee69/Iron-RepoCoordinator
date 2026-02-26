# ==================================================
# | Valkyrie Repo Coordinator Branch Mode       |
# |------------------------------------------------|
# | Switch between main/nightly and promote.       |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils


type
  BranchModeReport* = object
    ok*: bool
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

proc originBranchExists(r, b: string): bool =
  ## r: repo path.
  ## b: branch name.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --verify origin/" & b)
  result = t.code == 0

proc branchExists(r, b: string): bool =
  ## r: repo path.
  ## b: branch name.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --verify " & b)
  result = t.code == 0

proc fetchOrigin(r: string): int =
  ## r: repo path to fetch.
  result = execCmd("git -C " & quoteShell(r) & " fetch origin")

proc checkoutFromOrigin(r, b: string): int =
  ## r: repo path.
  ## b: branch name.
  result = execCmd("git -C " & quoteShell(r) & " checkout -B " & quoteShell(b) & " origin/" & b)

proc checkoutLocal(r, b: string): int =
  ## r: repo path.
  ## b: branch name.
  result = execCmd("git -C " & quoteShell(r) & " checkout " & quoteShell(b))

proc createLocalBranch(r, b: string): int =
  ## r: repo path.
  ## b: branch name.
  result = execCmd("git -C " & quoteShell(r) & " checkout -b " & quoteShell(b))

proc pullFastForward(r: string): int =
  ## r: repo path.
  result = execCmd("git -C " & quoteShell(r) & " pull --ff-only")

proc pushBranch(r, b: string): int =
  ## r: repo path.
  ## b: branch name.
  result = execCmd("git -C " & quoteShell(r) & " push -u origin " & quoteShell(b))

proc checkoutBranch(r, b: string, report: var BranchModeReport): bool =
  ## r: repo path.
  ## b: branch name.
  if hasChanges(r):
    report.ok = false
    addLine(report.lines, "Repo has uncommitted changes. Aborting.")
    return false
  if fetchOrigin(r) != 0:
    report.ok = false
    addLine(report.lines, "Fetch failed.")
    return false
  if originBranchExists(r, b):
    if not confirmEnter("Checkout " & b & " from origin (reset local branch)?"):
      report.ok = false
      addLine(report.lines, "Checkout cancelled.")
      return false
    if checkoutFromOrigin(r, b) != 0:
      report.ok = false
      addLine(report.lines, "Checkout failed.")
      return false
    if pullFastForward(r) != 0:
      report.ok = false
      addLine(report.lines, "Pull failed.")
      return false
    addLine(report.lines, "Checked out " & b & ".")
    return true
  if branchExists(r, b):
    if not confirmEnter("Checkout local " & b & "?"):
      report.ok = false
      addLine(report.lines, "Checkout cancelled.")
      return false
    if checkoutLocal(r, b) != 0:
      report.ok = false
      addLine(report.lines, "Checkout failed.")
      return false
    addLine(report.lines, "Checked out " & b & ".")
    return true
  if not confirmEnter("Branch " & b & " not found. Create local branch?"):
    report.ok = false
    addLine(report.lines, "Branch creation cancelled.")
    return false
  if createLocalBranch(r, b) != 0:
    report.ok = false
    addLine(report.lines, "Create branch failed.")
    return false
  addLine(report.lines, "Created local branch " & b & ".")
  if confirmEnter("Push " & b & " to origin?"):
    if pushBranch(r, b) != 0:
      report.ok = false
      addLine(report.lines, "Push failed.")
      return false
  return true

proc promoteNightly(r: string, report: var BranchModeReport): bool =
  ## r: repo path.
  if hasChanges(r):
    report.ok = false
    addLine(report.lines, "Repo has uncommitted changes. Aborting.")
    return false
  if not confirmEnter("Promote nightly to main (fast-forward only)?"):
    report.ok = false
    addLine(report.lines, "Promotion cancelled.")
    return false
  if fetchOrigin(r) != 0:
    report.ok = false
    addLine(report.lines, "Fetch failed.")
    return false
  if not originBranchExists(r, "nightly") and not branchExists(r, "nightly"):
    report.ok = false
    addLine(report.lines, "Nightly branch not found.")
    return false
  if not checkoutBranch(r, "main", report):
    return false
  if execCmd("git -C " & quoteShell(r) & " merge --ff-only nightly") != 0:
    report.ok = false
    addLine(report.lines, "Fast-forward merge failed. Resolve manually.")
    return false
  addLine(report.lines, "Merged nightly into main (ff-only).")
  if confirmEnter("Push main to origin?"):
    if execCmd("git -C " & quoteShell(r) & " push") != 0:
      report.ok = false
      addLine(report.lines, "Push failed.")
      return false
  return true

proc switchBranchMode*(r: string, mode: string): BranchModeReport =
  ## r: repo path to switch.
  ## mode: main/nightly/promote.
  var report: BranchModeReport
  var repo: string = normalizePathValue(r)
  var cfg: CoordinatorConfig
  var owner: string
  report.ok = true
  if repo.len == 0 or not isGitRepo(repo):
    report.ok = false
    addLine(report.lines, "Target is not a git repo: " & repo)
    return report
  cfg = readCoordinatorConfig(resolveConfigRoot(repo))
  if not ownersConfigured(cfg):
    report.ok = false
    addLine(report.lines, "No owners configured in valkyrie/repo_coordinator.toml (owners=...).")
    addLine(report.lines, "For safety, branch mode is disabled.")
    return report
  owner = resolveRepoOwner(repo)
  if not ownerWriteAllowed(cfg, owner):
    report.ok = false
    addLine(report.lines, "Owner not allowed: " & owner)
    return report
  case mode.toLowerAscii()
  of "main":
    discard checkoutBranch(repo, "main", report)
  of "nightly":
    discard checkoutBranch(repo, "nightly", report)
  of "promote":
    discard promoteNightly(repo, report)
  else:
    report.ok = false
    addLine(report.lines, "Unknown mode: " & mode)
  result = report
