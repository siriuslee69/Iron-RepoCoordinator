# ==================================================
# | Jormungandr Repo Coordinator Autopush Helper   |
# |------------------------------------------------|
# | Commit and push the current repository.        |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils


type
  AutoPushReport* = object
    ok*: bool
    committed*: bool
    pushed*: bool
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

proc hasChanges(r: string): bool =
  ## r: repo path to check for local changes.
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain")
  result = t.code == 0 and t.text.strip().len > 0

proc readCommitMessage(r: string): string =
  ## r: repo path to read progress.md from.
  var
    p: string
    m: string
  p = joinPath(r, "progress.md")
  m = "Auto update"
  if fileExists(p):
    for line in readFile(p).splitLines:
      if line.startsWith("Commit Message:"):
        m = line["Commit Message:".len .. ^1].strip()
        break
  if m.strip().len == 0:
    m = "Auto update"
  result = m

proc runAddCommit(r, m: string): int =
  ## r: repo path to commit.
  ## m: commit message.
  var
    c1: string
    c2: string
    ec: int
  c1 = "git -C " & quoteShell(r) & " add -A ."
  c2 = "git -C " & quoteShell(r) & " commit -m " & quoteShell(m)
  ec = execCmd(c1)
  if ec != 0:
    return ec
  result = execCmd(c2)

proc runPush(r: string): int =
  ## r: repo path to push.
  var c: string = "git -C " & quoteShell(r) & " push"
  result = execCmd(c)

proc autoPushRepo*(r: string): AutoPushReport =
  ## r: repo path to push.
  var
    tReport: AutoPushReport
    repo: string
    cfg: JrcConfig
    owner: string
    msg: string
  tReport.ok = true
  repo = normalizePathValue(r)
  if repo.len == 0:
    repo = normalizePathValue(getCurrentDir())
  if repo.len == 0 or not isGitRepo(repo):
    tReport.ok = false
    addLine(tReport.lines, "Target is not a git repo: " & repo)
    result = tReport
    return
  if not hasRemote(repo):
    tReport.ok = false
    addLine(tReport.lines, "No remote configured.")
    result = tReport
    return
  cfg = readJrcConfig(resolveConfigRoot(repo))
  if not ownersConfigured(cfg):
    tReport.ok = false
    addLine(tReport.lines, "No owners configured in valkyrie/jrc.toml (owners=...).")
    addLine(tReport.lines, "For safety, autopush is disabled.")
    result = tReport
    return
  owner = resolveRepoOwner(repo)
  if not ownerWriteAllowed(cfg, owner):
    tReport.ok = false
    addLine(tReport.lines, "Owner not allowed: " & owner)
    result = tReport
    return
  if not confirmEnter("Commit and push " & repo & "?"):
    tReport.ok = false
    addLine(tReport.lines, "Autopush cancelled by user.")
    result = tReport
    return
  if hasChanges(repo):
    msg = readCommitMessage(repo)
    if not confirmEnter("Commit changes with message: " & msg & "?"):
      tReport.ok = false
      addLine(tReport.lines, "Commit cancelled by user.")
      result = tReport
      return
    if runAddCommit(repo, msg) != 0:
      tReport.ok = false
      addLine(tReport.lines, "Commit failed.")
      result = tReport
      return
    tReport.committed = true
  if not confirmEnter("Push " & repo & " to origin?"):
    tReport.ok = false
    addLine(tReport.lines, "Push cancelled by user.")
    result = tReport
    return
  if runPush(repo) != 0:
    tReport.ok = false
    addLine(tReport.lines, "Push failed.")
    result = tReport
    return
  tReport.pushed = true
  addLine(tReport.lines, "Push completed.")
  result = tReport
