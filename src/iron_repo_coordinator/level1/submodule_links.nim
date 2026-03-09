# ==================================================
# | iron Repo Coordinator Submodule Links    |
# |------------------------------------------------|
# | Shared helpers for external local submodule    |
# | linking and duplicate checkout cleanup.        |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils


type
  SubmoduleLinkReport* = object
    ok*: bool
    linked*: int
    updated*: int
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

proc toSystemPath(p: string): string =
  ## p: normalized path to convert for local shell commands.
  when defined(windows):
    result = p.replace('/', '\\')
  else:
    result = p

proc cmdQuote(p: string): string =
  ## p: local path to quote for Windows cmd usage.
  result = "\"" & toSystemPath(p).replace("\"", "\"\"") & "\""

proc samePath*(a: string, b: string): bool =
  ## a: first path to compare.
  ## b: second path to compare.
  let na = normalizePathValue(a)
  let nb = normalizePathValue(b)
  result = na.len > 0 and nb.len > 0 and na == nb

proc isGitRepo*(r: string): bool =
  ## r: repo path to validate.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --is-inside-work-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc looksLikeLocalPath*(u: string): bool =
  ## u: raw URL/path value.
  var t: string = u.strip()
  if t.len == 0:
    return false
  if t.startsWith("file://"):
    return true
  if t.len >= 3 and t[1] == ':' and (t[2] == '\\' or t[2] == '/'):
    return true
  if t.startsWith("./") or t.startsWith("../") or t.startsWith("/") or t.startsWith("\\"):
    return true
  if dirExists(t) or fileExists(t):
    return true
  result = false

proc readRepoOrigin*(r: string): string =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "remote get-url origin")
  if t.code != 0:
    return ""
  result = t.text.strip()

proc readRepoBranch*(r: string): string =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "branch --show-current")
  if t.code != 0:
    return ""
  result = t.text.strip()

proc setRepoOrigin*(r: string, u: string): int =
  ## r: repo path.
  ## u: remote URL to assign as origin.
  let tUrl = u.strip()
  if tUrl.len == 0 or looksLikeLocalPath(tUrl):
    return 0
  if runGit(r, "remote get-url origin").code == 0:
    return execCmd("git -C " & quoteShell(r) & " remote set-url origin " & quoteShell(tUrl))
  result = execCmd("git -C " & quoteShell(r) & " remote add origin " & quoteShell(tUrl))

proc dirtyItemCount*(r: string): int =
  ## r: repo path.
  var
    t: tuple[text: string, code: int]
    ls: seq[string]
  t = runGit(r, "status --porcelain")
  if t.code != 0:
    return 0
  ls = t.text.splitLines()
  for l in ls:
    if l.strip().len > 0:
      inc result

proc readCommitEpoch*(r: string): int64 =
  ## r: repo path.
  var
    t: tuple[text: string, code: int]
    s: string
  t = runGit(r, "show -s --format=%ct HEAD")
  if t.code != 0:
    return 0
  s = t.text.strip()
  try:
    result = parseBiggestInt(s)
  except ValueError:
    result = 0

proc localNameForSubmodule*(m: SubmoduleInfo): string =
  ## m: submodule metadata.
  var t: string = splitPath(m.path).tail
  if t.len == 0:
    t = extractRepoTail(m.url)
  if t.len == 0:
    t = m.name
  result = t

proc candidateLocalNames*(m: SubmoduleInfo): seq[string] =
  ## m: submodule metadata.
  var
    names: seq[string]
    t: string
  proc addName(v: string) =
    let s = v.strip()
    if s.len == 0:
      return
    if not names.contains(s):
      names.add(s)
    if s.toLowerAscii() in ["proto-conventions", "proto-templaterepo", "proto-repotemplate"]:
      if not names.contains("Proto-RepoTemplate"):
        names.add("Proto-RepoTemplate")
      if not names.contains("Proto-TemplateRepo"):
        names.add("Proto-TemplateRepo")
  t = splitPath(m.path).tail
  addName(t)
  t = m.url.strip().replace('\\', '/')
  if t.endsWith("/"):
    t = t[0 .. ^2]
  if t.endsWith(".git"):
    t = t[0 .. ^5]
  t = splitPath(t).tail
  addName(t)
  t = splitPath(m.name).tail
  addName(t)
  result = names

proc preferredExistingSiblingRepo*(rootDir: string, m: SubmoduleInfo,
                                   currentRepo: string, nestedPath: string,
                                   lines: var seq[string]): string =
  ## rootDir: root directory to search for sibling repos.
  ## m: submodule metadata.
  ## currentRepo: repo currently being processed.
  ## nestedPath: nested submodule path inside the current repo.
  ## lines: comparison log output.
  var
    candidates: seq[string]
    path: string
    expectedNorm: string
    remoteTail: string
    pathTail: string
    best: string
    bestScore: int = low(int)
    bestTs: int64 = low(int64)
    bestDirty: int = high(int)
    origin: string
    branch: string
    name: string
    score: int
    dirty: int
    ts: int64
  for n in candidateLocalNames(m):
    path = normalizePathValue(joinPath(rootDir, n))
    if samePath(path, currentRepo) or samePath(path, nestedPath):
      continue
    if dirExists(path) and isGitRepo(path) and not candidates.contains(path):
      candidates.add(path)
  if candidates.len == 0:
    return ""
  if candidates.len == 1:
    return candidates[0]
  expectedNorm = normalizeRemoteUrl(m.url)
  remoteTail = extractRepoTail(expectedNorm)
  pathTail = splitPath(m.path).tail.toLowerAscii()
  addLine(lines, "  Multiple sibling repo candidates for " & m.path & ":")
  for c in candidates:
    origin = normalizeRemoteUrl(readRepoOrigin(c))
    branch = readRepoBranch(c)
    name = lastPathPart(c).toLowerAscii()
    dirty = dirtyItemCount(c)
    ts = readCommitEpoch(c)
    score = 0
    if expectedNorm.len > 0 and origin == expectedNorm:
      score = score + 100
    if remoteTail.len > 0 and name == remoteTail:
      score = score + 20
    if pathTail.len > 0 and name == pathTail:
      score = score + 5
    if branch.len > 0:
      score = score + 2
    if dirty == 0:
      score = score + 1
    addLine(lines, "    " & c & " origin=" & origin & " branch=" & branch &
                    " dirty=" & $dirty & " score=" & $score)
    if score > bestScore or
       (score == bestScore and ts > bestTs) or
       (score == bestScore and ts == bestTs and dirty < bestDirty):
      best = c
      bestScore = score
      bestTs = ts
      bestDirty = dirty
  if best.len > 0:
    addLine(lines, "  Preferred sibling repo: " & best)
  result = best

proc setGitmodulesUrl*(repo: string, m: SubmoduleInfo, url: string): int =
  ## repo: parent repository path.
  ## m: submodule metadata.
  ## url: canonical remote URL to persist in .gitmodules.
  var
    keyName: string
    c: string
  keyName = m.name
  if keyName.len == 0:
    keyName = m.path
  if keyName.len == 0 or url.strip().len == 0:
    return 0
  c = "git -C " & quoteShell(repo) & " config --file .gitmodules " &
      quoteShell("submodule." & keyName & ".url") & " " & quoteShell(url)
  result = execCmd(c)

proc canonicalRemoteForSubmodule*(m: SubmoduleInfo, siblingPath: string, nestedPath: string): string =
  ## m: submodule metadata.
  ## siblingPath: external sibling repo path.
  ## nestedPath: current nested submodule checkout path.
  var t: string
  if not looksLikeLocalPath(m.url):
    t = m.url.strip()
    if t.len > 0:
      return t
  if siblingPath.len > 0 and isGitRepo(siblingPath):
    t = readRepoOrigin(siblingPath)
    if t.len > 0 and not looksLikeLocalPath(t):
      return t
  if nestedPath.len > 0 and isGitRepo(nestedPath):
    t = readRepoOrigin(nestedPath)
    if t.len > 0 and not looksLikeLocalPath(t):
      return t
  result = ""

proc removePathTree*(p: string): int =
  ## p: file or directory path to remove.
  if not fileExists(p) and not dirExists(p):
    return 0
  when defined(windows):
    if fileExists(p):
      result = execCmd("cmd /c del /f /q " & cmdQuote(p))
    else:
      result = execCmd("cmd /c rmdir /s /q " & cmdQuote(p))
  else:
    if fileExists(p):
      removeFile(p)
      return 0
    for kind, path in walkDir(p, relative = false):
      case kind
      of pcFile, pcLinkToFile:
        removeFile(path)
      of pcDir:
        discard
      else:
        discard
    for kind, path in walkDir(p, relative = false):
      if kind == pcDir:
        discard removePathTree(path)
    removeDir(p)
    result = 0

proc createDirLink*(linkPath: string, targetPath: string): int =
  ## linkPath: submodule path inside the parent repo.
  ## targetPath: external sibling repo path.
  ensureParentDir(linkPath)
  when defined(windows):
    result = execCmd("cmd /c mklink /J " & cmdQuote(linkPath) & " " & cmdQuote(targetPath))
  else:
    result = execCmd("ln -sfn " & quoteShell(targetPath) & " " & quoteShell(linkPath))

proc copyWorktreeFiles(src: string, dst: string) =
  ## src: source repo worktree.
  ## dst: destination repo worktree.
  var
    rel: string
    target: string
  for kind, path in walkDir(src, relative = false):
    if lastPathPart(path) == ".git":
      continue
    rel = relativePath(path, src)
    target = joinPath(dst, rel)
    case kind
    of pcDir:
      if not dirExists(target):
        createDir(target)
      copyWorktreeFiles(path, target)
    of pcFile:
      ensureParentDir(target)
      copyFile(path, target)
    else:
      discard

proc applyDeletedPaths(src: string, dst: string) =
  ## src: source repo worktree.
  ## dst: destination repo worktree.
  var
    t: tuple[text: string, code: int]
    rel: string
  t = runGit(src, "status --porcelain")
  if t.code != 0:
    return
  for line in t.text.splitLines():
    if line.len < 4:
      continue
    if line[0] != 'D' and line[1] != 'D':
      continue
    rel = line[3 .. ^1].strip()
    if rel.len == 0:
      continue
    discard removePathTree(joinPath(dst, rel))

proc cloneRepoToPath*(source: string, dest: string): int =
  ## source: git remote or local repo path.
  ## dest: sibling destination path.
  result = execCmd("git clone " & quoteShell(source) & " " & quoteShell(dest))

proc copyWorktreeToRepo*(src: string, dst: string) =
  ## src: source worktree to mirror.
  ## dst: destination repo worktree.
  copyWorktreeFiles(src, dst)
  applyDeletedPaths(src, dst)

proc choosePreferredRepo*(nestedPath: string, siblingPath: string,
                          expectedUrl: string, lines: var seq[string]): string =
  ## nestedPath: nested submodule checkout path.
  ## siblingPath: external sibling repo path.
  ## expectedUrl: declared submodule URL from .gitmodules.
  ## lines: comparison log output.
  var
    nestedOrigin: string
    siblingOrigin: string
    nestedBranch: string
    siblingBranch: string
    nestedDirty: int
    siblingDirty: int
    nestedTs: int64
    siblingTs: int64
    expectedNorm: string
  nestedOrigin = normalizeRemoteUrl(readRepoOrigin(nestedPath))
  siblingOrigin = normalizeRemoteUrl(readRepoOrigin(siblingPath))
  expectedNorm = normalizeRemoteUrl(expectedUrl)
  nestedBranch = readRepoBranch(nestedPath)
  siblingBranch = readRepoBranch(siblingPath)
  nestedDirty = dirtyItemCount(nestedPath)
  siblingDirty = dirtyItemCount(siblingPath)
  nestedTs = readCommitEpoch(nestedPath)
  siblingTs = readCommitEpoch(siblingPath)
  addLine(lines, "  Compare nested vs sibling:")
  addLine(lines, "    nested branch=" & nestedBranch & " dirty=" & $nestedDirty &
                  " origin=" & nestedOrigin)
  addLine(lines, "    sibling branch=" & siblingBranch & " dirty=" & $siblingDirty &
                  " origin=" & siblingOrigin)
  if expectedNorm.len > 0:
    if siblingOrigin == expectedNorm and nestedOrigin != expectedNorm:
      addLine(lines, "  Prefer sibling: origin matches declared remote.")
      return "sibling"
    if nestedOrigin == expectedNorm and siblingOrigin != expectedNorm:
      addLine(lines, "  Prefer nested: origin matches declared remote.")
      return "nested"
  if siblingBranch.len > 0 and nestedBranch.len == 0:
    addLine(lines, "  Prefer sibling: nested checkout is detached.")
    return "sibling"
  if siblingTs > nestedTs and siblingDirty <= nestedDirty:
    addLine(lines, "  Prefer sibling: newer commit timestamp with no extra dirt.")
    return "sibling"
  if nestedTs > siblingTs and nestedDirty < siblingDirty:
    addLine(lines, "  Prefer nested: newer commit timestamp and cleaner worktree.")
    return "nested"
  if siblingDirty == 0 and nestedDirty > 0:
    addLine(lines, "  Prefer sibling: nested worktree is dirtier.")
    return "sibling"
  if nestedDirty == 0 and siblingDirty > 0:
    addLine(lines, "  Prefer nested: sibling worktree is dirtier.")
    return "nested"
  addLine(lines, "  Defaulting to sibling: no stronger nested signal found.")
  result = "sibling"

proc linkConfiguredSubmodules*(repo: string, locals: seq[SubmoduleInfo],
                               replaceExisting: bool): SubmoduleLinkReport =
  ## repo: parent repository path.
  ## locals: local override entries with sibling repo paths in `url`.
  ## replaceExisting: allow deleting existing nested working trees before linking.
  var
    report: SubmoduleLinkReport
    siblingPath: string
    nestedPath: string
  report.ok = true
  for m in locals:
    siblingPath = expandFilename(m.url)
    nestedPath = joinPath(repo, m.path)
    if siblingPath.len == 0 or not isGitRepo(siblingPath):
      report.ok = false
      addLine(report.lines, "Missing local sibling repo for " & m.path)
      continue
    if samePath(siblingPath, repo):
      report.ok = false
      addLine(report.lines, "Refused self-link for " & m.path & ": " & siblingPath)
      continue
    if samePath(siblingPath, nestedPath):
      report.ok = false
      addLine(report.lines, "Refused identity link for " & m.path & ": " & siblingPath)
      continue
    if fileExists(nestedPath) or dirExists(nestedPath):
      if not replaceExisting:
        inc report.skipped
        addLine(report.lines, "Skipped existing path without replacement: " & m.path)
        continue
      if removePathTree(nestedPath) != 0:
        report.ok = false
        addLine(report.lines, "Failed to remove existing submodule path: " & m.path)
        continue
    if createDirLink(nestedPath, siblingPath) != 0:
      report.ok = false
      addLine(report.lines, "Failed to create local link for " & m.path)
      continue
    inc report.linked
    addLine(report.lines, "Linked " & m.path & " -> " & siblingPath)
  result = report
