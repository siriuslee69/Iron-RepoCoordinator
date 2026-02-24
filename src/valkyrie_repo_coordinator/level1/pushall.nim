# ==================================================
# | Valkyrie Repo Coordinator Push-All Helper   |
# |------------------------------------------------|
# | Commit (when needed) and push all repos in the |
# | parent directory.                              |
# ==================================================

import std/[os, strutils, osproc, algorithm]
import ../level0/repo_utils


type
  PushAllReport* = object
    ok*: bool
    repos*: int
    committed*: int
    pushed*: int
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

proc isSubmoduleRepo(r: string): bool =
  ## r: repo path to check for submodule context.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --show-superproject-working-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc hasRemote(r: string): bool =
  ## r: repo path to check for remotes.
  var t: tuple[text: string, code: int] = runGit(r, "remote")
  result = t.code == 0 and t.text.strip().len > 0

proc hasChanges(r: string): bool =
  ## r: repo path to check for local changes.
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain")
  result = t.code == 0 and t.text.strip().len > 0

proc getChangedFiles(r: string): seq[string] =
  ## r: repo path to list changed files.
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain")
  var lines: seq[string]
  var p: string
  if t.code != 0 or t.text.strip().len == 0:
    return @[]
  lines = t.text.splitLines
  for s in lines:
    if s.len < 4:
      continue
    p = s[3 .. ^1].strip()
    if p.len > 0:
      result.add(p)

proc readCommitMessage(r: string): string =
  ## r: repo path to read progress.md from.
  var p: string = joinPath(r, "progress.md")
  var msg: string = "Auto update"
  if fileExists(p):
    for line in readFile(p).splitLines:
      if line.startsWith("Commit Message:"):
        msg = line["Commit Message:".len .. ^1].strip()
        break
  if msg.strip().len == 0:
    msg = "Auto update"
  result = msg

proc runAddCommit(r, m: string): int =
  ## r: repo path to commit.
  ## m: commit message.
  var c1: string = "git -C " & quoteShell(r) & " add -A ."
  var c2: string = "git -C " & quoteShell(r) & " commit -m " & quoteShell(m)
  var ec: int = execCmd(c1)
  if ec != 0:
    return ec
  result = execCmd(c2)

proc runPush(r: string): int =
  ## r: repo path to push.
  var c: string = "git -C " & quoteShell(r) & " push"
  result = execCmd(c)

proc runFetch(r: string): int =
  ## r: repo path to fetch.
  var c: string = "git -C " & quoteShell(r) & " fetch"
  result = execCmd(c)

proc confirmFetchPush(): bool =
  ## Ask user to confirm fetch+push.
  result = confirmEnter("Fetch and push repos under the selected root?")


proc resolveRoot(rsHere, rsParent: seq[string], here, parent: string, hereIsRepo, parentIsRepo: bool): tuple[root: string, repos: seq[string]] =
  ## Decide which root to use based on current and parent repo status.
  if hereIsRepo or rsHere.len > 0:
    result = (here, rsHere)
    return
  if parentIsRepo:
    result = (here, rsHere)
    return
  result = (parent, rsParent)

proc pushAllFromParent*(v: bool = false): PushAllReport =
  ## v: verbose toggle (unused for now).
  var
    report: PushAllReport
    root: string
    here: string
    parent: string
    rsHere: seq[string]
    rsParent: seq[string]
    hereIsRepo: bool
    parentIsRepo: bool
    configRoot: string
    cfg: CoordinatorConfig
    rs: seq[string]
    msg: string
    tOwner: string
    targetOwner: string
    ownerCounts: seq[tuple[owner: string, count: int]]
    success: seq[string]
    fails: seq[string]
  discard v
  report.ok = true
  here = normalizePathValue(getCurrentDir())
  parent = normalizePathValue(parentDir(getCurrentDir()))
  if here.len == 0 or not dirExists(here):
    report.ok = false
    addLine(report.lines, "Current directory not found.")
    result = report
    return
  hereIsRepo = isGitRepo(here)
  parentIsRepo = parent.len > 0 and dirExists(parent) and isGitRepo(parent)
  rsHere = collectRepos(@[here])
  if parent.len > 0 and dirExists(parent):
    rsParent = collectRepos(@[parent])
  (root, rs) = resolveRoot(rsHere, rsParent, here, parent, hereIsRepo, parentIsRepo)
  if root.len == 0 or not dirExists(root):
    report.ok = false
    addLine(report.lines, "Root directory not found.")
    result = report
    return
  if rs.len == 0:
    report.ok = false
    if root == parent:
      addLine(report.lines, "No repos found under parent directory.")
    else:
      addLine(report.lines, "No repos found under current directory.")
    result = report
    return
  if hereIsRepo:
    configRoot = here
  elif parentIsRepo:
    configRoot = parent
  else:
    configRoot = ""
  if configRoot.len > 0:
    cfg = readCoordinatorConfig(configRoot)
  if not ownersConfigured(cfg):
    report.ok = false
    addLine(report.lines, "No owners configured in valkyrie/repo_coordinator.toml (owners=...).")
    addLine(report.lines, "For safety, push operations are disabled.")
    result = report
    return
  report.repos = rs.len
  addLine(report.lines, "Found " & $rs.len & " repos under " & root & ".")
  if not confirmFetchPush():
    report.ok = false
    addLine(report.lines, "Fetch/push cancelled by user.")
    result = report
    return
  for repo in rs:
    if not isGitRepo(repo):
      continue
    if isSubmoduleRepo(repo):
      continue
    if not hasRemote(repo):
      continue
    tOwner = resolveRepoOwner(repo)
    if tOwner.len == 0:
      addLine(report.lines, "Cannot read origin owner: " & repo)
      continue
    if not ownerWriteAllowed(cfg, tOwner):
      continue
    var found: bool = false
    for i in 0 ..< ownerCounts.len:
      if ownerCounts[i].owner == tOwner:
        ownerCounts[i].count = ownerCounts[i].count + 1
        found = true
        break
    if not found:
      ownerCounts.add((tOwner, 1))
  if ownerCounts.len == 0:
    report.ok = false
    addLine(report.lines, "No repos with remotes found to determine owner.")
    result = report
    return
  ownerCounts.sort(proc(a, b: tuple[owner: string, count: int]): int = system.cmp(b.count, a.count))
  var ownerOptions: seq[string] = @[]
  for oc in ownerCounts:
    ownerOptions.add(oc.owner & " (" & $oc.count & ")")
  ownerOptions.add("Other (enter manually)")
  let sel = promptOptions("Select owner to push:", ownerOptions)
  if sel < 0:
    report.ok = false
    addLine(report.lines, "Push cancelled by user.")
    result = report
    return
  if sel == ownerOptions.len - 1:
    stdout.write("Enter owner: ")
    stdout.flushFile()
    targetOwner = readLine(stdin).strip().toLowerAscii()
    if targetOwner.len == 0:
      report.ok = false
      addLine(report.lines, "No owner provided. Cancelled.")
      result = report
      return
  else:
    targetOwner = ownerCounts[sel].owner
  var ownerMatchCount: int = 0
  for repo in rs:
    if not isGitRepo(repo):
      continue
    if isSubmoduleRepo(repo):
      continue
    if not hasRemote(repo):
      continue
    tOwner = resolveRepoOwner(repo)
    if tOwner == targetOwner:
      inc ownerMatchCount
  if ownerMatchCount == 0:
    report.ok = false
    addLine(report.lines, "No repos found for owner: " & targetOwner)
    result = report
    return
  for repo in rs:
    addLine(report.lines, "==> " & repo)
    if not isGitRepo(repo):
      addLine(report.lines, "  Not a git repo, skipping.")
      fails.add(repo & " | Not a git repo")
      continue
    if isSubmoduleRepo(repo):
      addLine(report.lines, "  Submodule repo, skipping.")
      fails.add(repo & " | Submodule repo")
      continue
    if not hasRemote(repo):
      addLine(report.lines, "  No remotes, skipping.")
      fails.add(repo & " | No remotes")
      continue
    tOwner = resolveRepoOwner(repo)
    if not ownerWriteAllowed(cfg, tOwner):
      addLine(report.lines, "  Owner not allowed, skipping.")
      fails.add(repo & " | Owner not allowed (" & tOwner & ")")
      continue
    if tOwner != targetOwner:
      addLine(report.lines, "  Owner mismatch, skipping.")
      fails.add(repo & " | Owner mismatch (" & tOwner & ")")
      continue
    if hasChanges(repo):
      msg = readCommitMessage(repo)
      var files: seq[string] = getChangedFiles(repo)
      if files.len > 0:
        addLine(report.lines, "  Changed files: " & files.join(", "))
      if not confirmEnter("Commit changes in " & repo & "?"):
        addLine(report.lines, "  Commit cancelled by user.")
        fails.add(repo & " | Commit cancelled")
        continue
      if runAddCommit(repo, msg) != 0:
        addLine(report.lines, "  Commit failed.")
        report.ok = false
        fails.add(repo & " | Commit failed")
        continue
      report.committed = report.committed + 1
    if runFetch(repo) != 0:
      addLine(report.lines, "  Fetch failed.")
      report.ok = false
      fails.add(repo & " | Fetch failed")
      continue
    if not confirmEnter("Push " & repo & " to origin?"):
      addLine(report.lines, "  Push cancelled by user.")
      fails.add(repo & " | Push cancelled")
      continue
    if runPush(repo) != 0:
      addLine(report.lines, "  Push failed.")
      report.ok = false
      fails.add(repo & " | Push failed")
    else:
      report.pushed = report.pushed + 1
      var files: seq[string] = getChangedFiles(repo)
      if msg.len == 0:
        if files.len == 0:
          success.add(repo & " | No changes")
        else:
          success.add(repo & " | No changes | " & files.join(", "))
      else:
        if files.len == 0:
          success.add(repo & " | " & msg)
        else:
          success.add(repo & " | " & msg & " | " & files.join(", "))
    msg = ""
  addLine(report.lines, "Successful repos: " & $success.len)
  for s in success:
    addLine(report.lines, "  " & s)
  addLine(report.lines, "Failed repos: " & $fails.len)
  for f in fails:
    addLine(report.lines, "  " & f)
  addLine(report.lines, "Committed repos: " & $report.committed)
  addLine(report.lines, "Pushed repos: " & $report.pushed)
  result = report
