# ==================================================
# | Valkyrie Repo Coordinator Submodule Extract |
# |------------------------------------------------|
# | Clone submodules into sibling repos and        |
# | apply local overrides for the parent repo.     |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils


type
  CloneOutcome = enum
    coLink
    coSkip
    coAbort

  SubmoduleExtractReport* = object
    ok*: bool
    cloned*: int
    linked*: int
    skipped*: int
    lines*: seq[string]

  SubmoduleExtractGlobalReport* = object
    ok*: bool
    repos*: int
    cloned*: int
    linked*: int
    skipped*: int
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

proc removeTree(p: string) =
  ## p: directory to remove recursively.
  if not dirExists(p):
    return
  for entry in walkDir(p, relative = false):
    if entry.kind == pcFile:
      removeFile(entry.path)
    elif entry.kind == pcDir:
      removeTree(entry.path)
  if dirExists(p):
    removeDir(p)

proc resolveLocalName(m: SubmoduleInfo): string =
  ## m: submodule info.
  var t: string = splitPath(m.path).tail
  if t.len == 0:
    t = extractRepoTail(m.url)
  if t.len == 0:
    t = m.name
  result = t

proc resolveRootDir(repo, rootOverride: string): string =
  ## repo: target repo path.
  ## rootOverride: optional root directory.
  if rootOverride.len > 0:
    return normalizePathValue(rootOverride)
  result = normalizePathValue(parentDir(repo))

proc cloneRepo(url, dest: string): int =
  ## url: git remote to clone.
  ## dest: destination folder.
  var c: string = "git clone " & quoteShell(url) & " " & quoteShell(dest)
  result = execCmd(c)

proc repoOriginUrl(r: string): string =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "remote get-url origin")
  if t.code != 0:
    return ""
  result = t.text.strip()

proc repoAheadCount(r: string): int =
  ## r: repo path.
  ## Returns number of commits ahead of origin/main (or 0 if unknown).
  var t: tuple[text: string, code: int]
  t = runGit(r, "rev-parse --verify origin/main")
  if t.code != 0:
    return 0
  t = runGit(r, "rev-list --left-right --count origin/main...HEAD")
  if t.code != 0:
    return 0
  let parts = t.text.strip().splitWhitespace()
  if parts.len >= 2:
    try:
      result = parseInt(parts[1])
    except ValueError:
      result = 0
  else:
    result = 0

proc isRepoMoreRecent(r, expectedUrl: string): bool =
  ## r: repo path.
  ## expectedUrl: submodule remote url for comparison.
  var
    origin: string
    normOrigin: string
    normExpected: string
    ahead: int
  origin = repoOriginUrl(r)
  if origin.len == 0:
    return true
  normOrigin = normalizeRemoteUrl(origin)
  normExpected = normalizeRemoteUrl(expectedUrl)
  if normExpected.len > 0 and normOrigin != normExpected:
    return true
  ahead = repoAheadCount(r)
  result = ahead > 0

proc ensureLocalClone(url, dest: string, replace: bool, v: bool,
    report: var SubmoduleExtractReport): CloneOutcome =
  ## url: remote url to clone.
  ## dest: desired local path.
  ## replace: remove existing dest if needed.
  ## v: verbose output.
  var idx: int
  if url.len == 0:
    report.ok = false
    addLine(report.lines, "Missing submodule url for " & dest)
    return coAbort
  if dirExists(dest):
    if isGitRepo(dest):
      if replace:
        var opts: seq[string] = @[
          "Overwrite with fresh clone",
          "Use existing repo",
          "Skip this submodule"
        ]
        if isRepoMoreRecent(dest, url):
          addLine(report.lines, "Existing repo appears newer/different: " & dest)
        idx = promptOptions("Repo already exists at " & dest & ".", opts)
        if idx < 0:
          report.ok = false
          addLine(report.lines, "Aborted by user.")
          return coAbort
        if idx == 1:
          return coLink
        if idx == 2:
          inc report.skipped
          return coSkip
        if not confirmEnter("Delete " & dest & " and re-clone?"):
          report.ok = false
          addLine(report.lines, "Aborted by user.")
          return coAbort
        removeTree(dest)
      else:
        var opts: seq[string] = @[
          "Use existing repo",
          "Skip this submodule"
        ]
        if isRepoMoreRecent(dest, url):
          addLine(report.lines, "Existing repo appears newer/different: " & dest)
        idx = promptOptions("Repo already exists at " & dest & ".", opts)
        if idx < 0:
          report.ok = false
          addLine(report.lines, "Aborted by user.")
          return coAbort
        if idx == 1:
          inc report.skipped
          return coSkip
        return coLink
    elif replace:
      var opts: seq[string] = @[
        "Remove folder and clone",
        "Skip this submodule"
      ]
      idx = promptOptions("Non-repo folder exists at " & dest & ".", opts)
      if idx < 0:
        report.ok = false
        addLine(report.lines, "Aborted by user.")
        return coAbort
      if idx == 1:
        inc report.skipped
        return coSkip
      if not confirmEnter("Delete folder " & dest & " and clone?"):
        report.ok = false
        addLine(report.lines, "Aborted by user.")
        return coAbort
      removeTree(dest)
    else:
      var opts: seq[string] = @["Skip this submodule"]
      idx = promptOptions("Non-repo folder exists at " & dest & ".", opts)
      if idx < 0:
        report.ok = false
        addLine(report.lines, "Aborted by user.")
        return coAbort
      inc report.skipped
      return coSkip
  if v:
    addLine(report.lines, "Cloning " & url & " -> " & dest)
  if cloneRepo(url, dest) != 0:
    report.ok = false
    addLine(report.lines, "Clone failed: " & url)
    return coAbort
  inc report.cloned
  result = coLink

proc buildLocalEntry(m: SubmoduleInfo, localPath: string): SubmoduleInfo =
  ## m: submodule info to copy.
  ## localPath: local repo path to use as url.
  var n: SubmoduleInfo = m
  n.url = normalizePathValue(localPath)
  result = n

proc upsertLocalModules(p: string, ms: seq[SubmoduleInfo]): seq[SubmoduleInfo] =
  ## p: path to .gitmodules.local.
  ## ms: submodule entries to insert.
  var existing: seq[SubmoduleInfo] = @[]
  if fileExists(p):
    existing = readSubmodules(p)
  let merged = mergeSubmodules(existing, ms)
  writeLocalModules(p, merged)
  result = merged

proc extractSubmodules*(r: string, rootOverride: string,
    replace: bool, v: bool): SubmoduleExtractReport =
  ## r: target repo to extract submodules from.
  ## rootOverride: optional root folder for local clones.
  ## replace: delete non-repo destinations before cloning.
  ## v: verbose output.
  var
    report: SubmoduleExtractReport
    repo: string
    rootDir: string
    cfg: CoordinatorConfig
    owner: string
    gm: string
    gi: string
    gl: string
    ms: seq[SubmoduleInfo]
    locals: seq[SubmoduleInfo] = @[]
    name: string
    dest: string
    merged: seq[SubmoduleInfo]
    outcome: CloneOutcome
  report.ok = true
  repo = normalizePathValue(r)
  if repo.len == 0 or not isGitRepo(repo):
    report.ok = false
    addLine(report.lines, "Target is not a git repo: " & repo)
    return report
  cfg = readCoordinatorConfig(resolveConfigRoot(repo))
  if not ownersConfigured(cfg):
    report.ok = false
    addLine(report.lines, "No owners configured in valkyrie/repo_coordinator.toml (owners=...).")
    addLine(report.lines, "For safety, submodule extract is disabled.")
    return report
  owner = resolveRepoOwner(repo)
  if not ownerWriteAllowed(cfg, owner):
    report.ok = false
    addLine(report.lines, "Owner not allowed: " & owner)
    return report
  rootDir = resolveRootDir(repo, rootOverride)
  gm = joinPath(repo, ".gitmodules")
  if not fileExists(gm):
    report.ok = false
    addLine(report.lines, "No .gitmodules found in " & repo)
    return report
  ms = readSubmodules(gm)
  if ms.len == 0:
    addLine(report.lines, "No submodules found in " & repo)
    return report
  if not confirmEnter("Extract submodules from " & repo & " into " & rootDir & "?"):
    report.ok = false
    addLine(report.lines, "Extraction cancelled by user.")
    return report
  gi = joinPath(repo, ".gitignore")
  gl = joinPath(repo, LocalModulesFile)
  discard ensureGitignoreEntry(gi, LocalModulesFile)
  for m in ms:
    name = resolveLocalName(m)
    if name.len == 0:
      inc report.skipped
      continue
    dest = joinPath(rootDir, name)
    outcome = ensureLocalClone(m.url, dest, replace, v, report)
    if outcome == coAbort:
      report.ok = false
      addLine(report.lines, "Extraction aborted.")
      return report
    if outcome == coSkip:
      continue
    locals.add(buildLocalEntry(m, dest))
    inc report.linked
  if locals.len == 0:
    addLine(report.lines, "No local overrides applied.")
    return report
  merged = upsertLocalModules(gl, locals)
  if applyLocalConfig(repo, merged) != 0:
    report.ok = false
    addLine(report.lines, "Failed to apply local git config.")
  discard runGit(repo, "submodule sync --recursive")
  discard runGit(repo, "submodule update --init --recursive")
  addLine(report.lines, "Cloned: " & $report.cloned)
  addLine(report.lines, "Linked: " & $report.linked)
  addLine(report.lines, "Skipped: " & $report.skipped)
  result = report

proc extractSubmodulesGlobal*(rootOverride: string,
    replace: bool, v: bool): SubmoduleExtractGlobalReport =
  ## rootOverride: optional root folder for local clones.
  ## replace: delete non-repo destinations before cloning.
  ## v: verbose output.
  var
    report: SubmoduleExtractGlobalReport
    rs: seq[string]
    gm: string
    rReport: SubmoduleExtractReport
  report.ok = true
  rs = collectReposFromRoots()
  if rs.len == 0:
    report.ok = false
    addLine(report.lines, "No repos found.")
    return report
  if not confirmEnter("Extract submodules for " & $rs.len & " repos under roots?"):
    report.ok = false
    addLine(report.lines, "Extraction cancelled by user.")
    return report
  addLine(report.lines, "Scanning " & $rs.len & " repos.")
  for repo in rs:
    if not isGitRepo(repo):
      continue
    gm = joinPath(repo, ".gitmodules")
    if not fileExists(gm):
      continue
    rReport = extractSubmodules(repo, rootOverride, replace, v)
    if not rReport.ok:
      report.ok = false
    report.repos = report.repos + 1
    report.cloned = report.cloned + rReport.cloned
    report.linked = report.linked + rReport.linked
    report.skipped = report.skipped + rReport.skipped
    if v:
      addLine(report.lines, "==> " & repo)
      for line in rReport.lines:
        addLine(report.lines, "  " & line)
  addLine(report.lines, "Repos processed: " & $report.repos)
  addLine(report.lines, "Cloned: " & $report.cloned)
  addLine(report.lines, "Linked: " & $report.linked)
  addLine(report.lines, "Skipped: " & $report.skipped)
  result = report
