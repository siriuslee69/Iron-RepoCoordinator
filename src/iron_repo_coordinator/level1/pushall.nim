# ==================================================
# | iron Repo Coordinator Push-All Helper   |
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
  var c: string = "git -c submodule.recurse=false -C " & quoteShell(r) & " " & a
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
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain --ignore-submodules=dirty")
  result = t.code == 0 and t.text.strip().len > 0

proc getChangedFiles(r: string): seq[string] =
  ## r: repo path to list changed files.
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain --ignore-submodules=dirty")
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

proc runAddCommit(r, m: string): int =
  ## r: repo path to commit.
  ## m: commit message.
  var c1: string = "git -c submodule.recurse=false -C " & quoteShell(r) & " add -A ."
  var c2: string = "git -c submodule.recurse=false -C " & quoteShell(r) & " commit -m " & quoteShell(m)
  var ec: int = execCmd(c1)
  if ec != 0:
    return ec
  result = execCmd(c2)

proc runPush(r: string): int =
  ## r: repo path to push.
  var c: string = "git -c submodule.recurse=false -C " & quoteShell(r) &
                  " push --recurse-submodules=no"
  result = execCmd(c)

proc runFetch(r: string): int =
  ## r: repo path to fetch.
  var c: string = "git -c submodule.recurse=false -C " & quoteShell(r) &
                  " fetch --no-recurse-submodules"
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

const
  MaxPushPasses = 4

proc hasAheadCommits(r: string): bool =
  ## r: repo path to check for local commits ahead of origin.
  var
    t: tuple[text: string, code: int]
    line: string
  t = runGit(r, "status --porcelain --branch --ignore-submodules=dirty")
  if t.code != 0:
    return false
  for raw in t.text.splitLines():
    line = raw.strip()
    if line.startsWith("##") and line.contains("ahead"):
      return true
  result = false

proc needsPushWork(r: string): bool =
  ## r: repo path to check for local commit or push work.
  result = hasChanges(r) or hasAheadCommits(r)

proc readRemoteUrl(r: string): string =
  ## r: repo path.
  result = normalizeRemoteUrl(readOriginUrl(r))

proc trackedFileCount(r: string): int =
  ## r: repo path to count tracked files for duplicate selection.
  var t: tuple[text: string, code: int] = runGit(r, "ls-files")
  if t.code != 0:
    return 0
  for line in t.text.splitLines():
    if line.strip().len > 0:
      inc result

proc readHeadEpoch(r: string): int64 =
  ## r: repo path to read the current commit timestamp.
  var
    t: tuple[text: string, code: int]
    raw: string
  t = runGit(r, "show -s --format=%ct HEAD")
  if t.code != 0:
    return 0
  raw = t.text.strip()
  try:
    result = parseBiggestInt(raw)
  except ValueError:
    result = 0

proc findIndex(ss: seq[string], value: string): int =
  ## ss: string list to search.
  ## value: target string.
  var i: int = 0
  while i < ss.len:
    if ss[i] == value:
      return i
    inc i
  result = -1

proc choosePreferredRepo(cs: seq[string], remoteUrl: string): string =
  ## cs: candidate repos with the same configured remote.
  ## remoteUrl: normalized remote URL.
  var
    remoteTail: string
    repo: string
    name: string
    best: string
    score: int
    bestScore: int = low(int)
    files: int
    bestFiles: int = low(int)
    ts: int64
    bestTs: int64 = low(int64)
  remoteTail = extractRepoTail(remoteUrl)
  for c in cs:
    repo = normalizePathValue(c)
    name = lastPathPart(repo).toLowerAscii()
    score = 0
    if remoteTail.len > 0 and name == remoteTail:
      score = score + 100
    files = trackedFileCount(repo)
    ts = readHeadEpoch(repo)
    if score > bestScore or
       (score == bestScore and files > bestFiles) or
       (score == bestScore and files == bestFiles and ts > bestTs):
      best = repo
      bestScore = score
      bestFiles = files
      bestTs = ts
  result = best

proc buildOwnerRepos(rs: seq[string], cfg: CoordinatorConfig, targetOwner: string,
                     report: var PushAllReport, skips: var seq[string]): seq[string] =
  ## rs: all discovered repos.
  ## cfg: owner configuration.
  ## targetOwner: owner selected for pushing.
  ## report: report log collector.
  ## skips: skip summary lines.
  var
    remoteUrls: seq[string]
    remoteRepos: seq[seq[string]]
    repo: string
    owner: string
    remoteUrl: string
    idx: int
    preferred: string
  for r in rs:
    repo = normalizePathValue(r)
    if not isGitRepo(repo):
      skips.add(repo & " | Not a git repo")
      continue
    if isSubmoduleRepo(repo):
      skips.add(repo & " | Submodule repo")
      continue
    if not hasRemote(repo):
      skips.add(repo & " | No remotes")
      continue
    owner = resolveRepoOwner(repo)
    if not ownerWriteAllowed(cfg, owner):
      skips.add(repo & " | Owner not allowed (" & owner & ")")
      continue
    if owner != targetOwner:
      skips.add(repo & " | Owner mismatch (" & owner & ")")
      continue
    remoteUrl = readRemoteUrl(repo)
    if remoteUrl.len == 0:
      skips.add(repo & " | Missing origin URL")
      continue
    idx = findIndex(remoteUrls, remoteUrl)
    if idx < 0:
      remoteUrls.add(remoteUrl)
      remoteRepos.add(@[repo])
    else:
      remoteRepos[idx].add(repo)
  idx = 0
  while idx < remoteUrls.len:
    preferred = choosePreferredRepo(remoteRepos[idx], remoteUrls[idx])
    if preferred.len > 0:
      result.add(preferred)
      if remoteRepos[idx].len > 1:
        addLine(report.lines, "Duplicate remote detected for " & remoteUrls[idx] &
                              "; using " & preferred)
        for repo in remoteRepos[idx]:
          if normalizePathValue(repo) != preferred:
            skips.add(repo & " | Duplicate remote, preferred " & preferred)
    inc idx

proc removeIndexLock(r: string): bool =
  ## r: repo path where a stale index.lock may exist.
  let p = joinPath(r, ".git", "index.lock")
  if not fileExists(p):
    return true
  try:
    removeFile(p)
    return true
  except OSError:
    return false

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
    ownerCounts: seq[tuple[owner: string, count: int]]
    targetOwner: string
    owner: string
    ownerRepos: seq[string]
    passRepos: seq[string]
    repo: string
    msg: string
    files: seq[string]
    success: seq[string]
    fails: seq[string]
    skips: seq[string]
    remaining: int
    previousRemaining: int = high(int)
    pass: int = 1
    sel: int
  discard v
  report.ok = true
  here = normalizePathValue(getCurrentDir())
  parent = normalizePathValue(parentDir(getCurrentDir()))
  if here.len == 0 or not dirExists(here):
    report.ok = false
    addLine(report.lines, "Current directory not found.")
    return report
  hereIsRepo = isGitRepo(here)
  parentIsRepo = parent.len > 0 and dirExists(parent) and isGitRepo(parent)
  rsHere = collectRepos(@[here])
  if parent.len > 0 and dirExists(parent):
    rsParent = collectRepos(@[parent])
  (root, rs) = resolveRoot(rsHere, rsParent, here, parent, hereIsRepo, parentIsRepo)
  if root.len == 0 or not dirExists(root):
    report.ok = false
    addLine(report.lines, "Root directory not found.")
    return report
  if rs.len == 0:
    report.ok = false
    if root == parent:
      addLine(report.lines, "No repos found under parent directory.")
    else:
      addLine(report.lines, "No repos found under current directory.")
    return report
  if hereIsRepo:
    configRoot = here
  elif parentIsRepo:
    configRoot = parent
  else:
    configRoot = ""
  if configRoot.len > 0:
    cfg = readCoordinatorConfig(configRoot)
  else:
    cfg = readCoordinatorConfig(here)
  if not ownersConfigured(cfg):
    report.ok = false
    addLine(report.lines, "No owners configured in .iron/repo_coordinator.toml (owners=...).")
    addLine(report.lines, "For safety, push operations are disabled.")
    return report
  addLine(report.lines, "Found " & $rs.len & " repos under " & root & ".")
  if not confirmFetchPush():
    report.ok = false
    addLine(report.lines, "Fetch/push cancelled by user.")
    return report
  for repo in rs:
    if not isGitRepo(repo) or isSubmoduleRepo(repo) or not hasRemote(repo):
      continue
    owner = resolveRepoOwner(repo)
    if owner.len == 0 or not ownerWriteAllowed(cfg, owner):
      continue
    var found: bool = false
    for i in 0 ..< ownerCounts.len:
      if ownerCounts[i].owner == owner:
        ownerCounts[i].count = ownerCounts[i].count + 1
        found = true
        break
    if not found:
      ownerCounts.add((owner, 1))
  if ownerCounts.len == 0:
    report.ok = false
    addLine(report.lines, "No repos with remotes found to determine owner.")
    return report
  ownerCounts.sort(proc(a, b: tuple[owner: string, count: int]): int = system.cmp(b.count, a.count))
  if ownerCounts.len == 1:
    targetOwner = ownerCounts[0].owner
    addLine(report.lines, "Using only allowed owner: " & targetOwner)
  else:
    var ownerOptions: seq[string] = @[]
    for oc in ownerCounts:
      ownerOptions.add(oc.owner & " (" & $oc.count & ")")
    ownerOptions.add("Other (enter manually)")
    sel = promptOptions("Select owner to push:", ownerOptions)
    if sel < 0:
      report.ok = false
      addLine(report.lines, "Push cancelled by user.")
      return report
    if sel == ownerOptions.len - 1:
      stdout.write("Enter owner: ")
      stdout.flushFile()
      targetOwner = readLine(stdin).strip().toLowerAscii()
      if targetOwner.len == 0:
        report.ok = false
        addLine(report.lines, "No owner provided. Cancelled.")
        return report
    else:
      targetOwner = ownerCounts[sel].owner
  ownerRepos = buildOwnerRepos(rs, cfg, targetOwner, report, skips)
  report.repos = ownerRepos.len
  if ownerRepos.len == 0:
    report.ok = false
    addLine(report.lines, "No repos found for owner: " & targetOwner)
    return report
  while pass <= MaxPushPasses:
    passRepos = @[]
    for r in ownerRepos:
      if needsPushWork(r):
        passRepos.add(r)
    if passRepos.len == 0:
      break
    addLine(report.lines, "Pass " & $pass & ": processing " & $passRepos.len &
                          " repos with local changes or ahead commits.")
    for r in passRepos:
      repo = normalizePathValue(r)
      addLine(report.lines, "==> " & repo)
      files = getChangedFiles(repo)
      if files.len > 0:
        addLine(report.lines, "  Changed files: " & files.join(", "))
      if hasChanges(repo):
        if not removeIndexLock(repo):
          addLine(report.lines, "  Could not remove stale index.lock.")
          report.ok = false
          fails.add(repo & " | Stale index.lock")
          continue
        msg = readCommitMessage(repo)
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
      else:
        msg = ""
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
        success.add(repo & " | " & (if msg.len > 0: msg else: "No changes"))
    remaining = 0
    for r in ownerRepos:
      if needsPushWork(r):
        inc remaining
    addLine(report.lines, "Remaining repos after pass " & $pass & ": " & $remaining)
    if remaining == 0:
      break
    if remaining >= previousRemaining:
      report.ok = false
      addLine(report.lines, "No further progress detected; stopping after pass " & $pass & ".")
      break
    previousRemaining = remaining
    inc pass
  addLine(report.lines, "Successful repos: " & $success.len)
  for s in success:
    addLine(report.lines, "  " & s)
  addLine(report.lines, "Failed repos: " & $fails.len)
  for f in fails:
    addLine(report.lines, "  " & f)
  addLine(report.lines, "Skipped repos: " & $skips.len)
  for s in skips:
    addLine(report.lines, "  " & s)
  addLine(report.lines, "Committed repos: " & $report.committed)
  addLine(report.lines, "Pushed repos: " & $report.pushed)
  result = report
