# ==================================================
# | iron Repo Coordinator Expand Helper     |
# |------------------------------------------------|
# | Propagate updated submodules across repos.     |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils
import submodule_links


type
  ExpandReport* = object
    ok*: bool
    updatedRepos*: int
    updatedSubmodules*: int
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

proc hasRemote(r: string): bool =
  ## r: repo path to check for remotes.
  var t: tuple[text: string, code: int] = runGit(r, "remote")
  result = t.code == 0 and t.text.strip().len > 0

proc getOriginUrl(r: string): string =
  ## r: repo path to read origin url from.
  var t: tuple[text: string, code: int] = runGit(r, "remote get-url origin")
  if t.code != 0:
    return ""
  result = t.text.strip()

proc hasChanges(r: string): bool =
  ## r: repo path to check for local changes.
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain")
  result = t.code == 0 and t.text.strip().len > 0

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

proc matchSubmodule(m: SubmoduleInfo, n, u: string): bool =
  ## m: submodule metadata.
  ## n: target repo name.
  ## u: target origin url.
  var
    tName: string
    tPath: string
    tUrl: string
    tOrigin: string
    tSub: string
  tName = n.toLowerAscii()
  tPath = extractRepoTail(m.path)
  tUrl = extractRepoTail(m.url)
  if tName.len > 0:
    if tPath == tName or tUrl == tName:
      result = true
      return
  tOrigin = normalizeRemoteUrl(u)
  tSub = normalizeRemoteUrl(m.url)
  if tOrigin.len > 0 and tSub.len > 0 and tOrigin == tSub:
    result = true
    return
  result = false

proc buildLocalEntry(m: SubmoduleInfo, l: string): SubmoduleInfo =
  ## m: submodule info to copy.
  ## l: local repo path to use as url.
  var n: SubmoduleInfo = m
  n.url = l
  result = n

proc upsertLocalModules(p: string, ms: seq[SubmoduleInfo]): seq[SubmoduleInfo] =
  ## p: path to .local.gitmodules.toml.
  ## ms: submodule entries to insert.
  var
    existing: seq[SubmoduleInfo] = @[]
    merged: seq[SubmoduleInfo]
  if fileExists(p):
    existing = readSubmodules(p)
  merged = mergeSubmodules(existing, ms)
  writeLocalModules(p, merged)
  result = merged

proc expandSubmodule*(r: string, v: bool): ExpandReport =
  ## r: repo path to expand from.
  ## v: verbose output toggle.
  var
    report: ExpandReport
    target: string
    origin: string
    name: string
    cfg: CoordinatorConfig
    owner: string
    doTargetPush: bool
    doExpand: bool
    actionIdx: int
    options: seq[string]
    rs: seq[string]
    repo: string
    gm: string
    gi: string
    gl: string
    ms: seq[SubmoduleInfo]
    hits: seq[SubmoduleInfo]
    locals: seq[SubmoduleInfo]
    merged: seq[SubmoduleInfo]
    m: SubmoduleInfo
    msg: string
    localUrl: string
    fail: int
    linkReport: SubmoduleLinkReport
    i: int
    j: int
  report.ok = true
  target = normalizePathValue(r)
  if target.len == 0:
    report.ok = false
    addLine(report.lines, "No target repo given.")
    result = report
    return
  if not isGitRepo(target):
    report.ok = false
    addLine(report.lines, "Target is not a git repo: " & target)
    result = report
    return
  cfg = readCoordinatorConfig(resolveConfigRoot(target))
  if not ownersConfigured(cfg):
    report.ok = false
    addLine(report.lines, "No owners configured in .iron/repo_coordinator.toml (owners=...).")
    addLine(report.lines, "For safety, expand is disabled.")
    result = report
    return
  owner = resolveRepoOwner(target)
  if not ownerWriteAllowed(cfg, owner):
    report.ok = false
    addLine(report.lines, "Target owner not allowed: " & owner)
    result = report
    return
  name = lastPathPart(target)
  origin = getOriginUrl(target)
  addLine(report.lines, "Target: " & name & " (" & target & ")")
  options = @[
    "Commit/push target and update sibling repos",
    "Only update sibling repos",
    "Only commit/push target"
  ]
  actionIdx = promptOptions("Expand options for " & name & ".", options)
  if actionIdx < 0:
    report.ok = false
    addLine(report.lines, "Expand cancelled by user.")
    result = report
    return
  doTargetPush = actionIdx == 0 or actionIdx == 2
  doExpand = actionIdx == 0 or actionIdx == 1
  if doTargetPush:
    if hasRemote(target):
      if hasChanges(target):
        if not confirmEnter("Commit changes in target repo " & name & "?"):
          report.ok = false
          addLine(report.lines, "Commit cancelled by user.")
          result = report
          return
        msg = readCommitMessage(target)
        if runAddCommit(target, msg) != 0:
          report.ok = false
          addLine(report.lines, "Commit failed in target repo.")
      if not confirmEnter("Push target repo " & name & " to origin?"):
        addLine(report.lines, "Push cancelled by user.")
      elif runPush(target) != 0:
        report.ok = false
        addLine(report.lines, "Push failed in target repo.")
    else:
      addLine(report.lines, "No remote configured for target repo.")
  if not doExpand:
    result = report
    return
  if not confirmEnter("Update sibling repos with local overrides and pull submodules?"):
    report.ok = false
    addLine(report.lines, "Expand cancelled by user.")
    result = report
    return
  rs = collectReposFromRoots()
  addLine(report.lines, "Scanning " & $rs.len & " repos.")
  i = 0
  while i < rs.len:
    repo = rs[i]
    if repo == target:
      inc i
      continue
    owner = resolveRepoOwner(repo)
    if not ownerWriteAllowed(cfg, owner):
      if v:
        addLine(report.lines, "==> " & repo)
        addLine(report.lines, "  Owner not allowed (" & owner & "), skipping.")
      inc i
      continue
    gm = joinPath(repo, ".gitmodules")
    if not fileExists(gm):
      inc i
      continue
    ms = readSubmodules(gm)
    if ms.len == 0:
      inc i
      continue
    hits = @[]
    j = 0
    while j < ms.len:
      m = ms[j]
      if matchSubmodule(m, name, origin):
        hits.add(m)
      inc j
    if hits.len == 0:
      inc i
      continue
    if v:
      addLine(report.lines, "==> " & repo)
    gi = joinPath(repo, ".gitignore")
    gl = joinPath(repo, LocalModulesFile)
    if ensureGitignoreEntry(gi, LocalModulesFile):
      addLine(report.lines, "  Updated .gitignore")
    locals = @[]
    localUrl = target.replace('\\', '/')
    j = 0
    while j < hits.len:
      m = hits[j]
      locals.add(buildLocalEntry(m, localUrl))
      inc j
    merged = upsertLocalModules(gl, locals)
    fail = applyLocalConfig(repo, merged)
    if fail != 0:
      report.ok = false
      addLine(report.lines, "  Failed to update git config.")
    linkReport = linkConfiguredSubmodules(repo, locals, true)
    if not linkReport.ok:
      report.ok = false
    for line in linkReport.lines:
      addLine(report.lines, "  " & line)
    report.updatedSubmodules = report.updatedSubmodules + linkReport.linked
    report.updatedRepos = report.updatedRepos + 1
    inc i
  addLine(report.lines, "Updated repos: " & $report.updatedRepos)
  addLine(report.lines, "Updated submodules: " & $report.updatedSubmodules)
  result = report
