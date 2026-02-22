# ==================================================
# | Jormungandr Repo Health Checks                 |
# |------------------------------------------------|
# | Read-only repo health scans (dirty, ahead).    |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils

type
  RepoHealth* = object
    name*: string
    path*: string
    branch*: string
    upstream*: string
    hasRemote*: bool
    hasUpstream*: bool
    isSubmodule*: bool
    ahead*: int
    behind*: int
    staged*: int
    modified*: int
    untracked*: int

  RepoHealthReport* = object
    repos*: int
    dirty*: int
    ahead*: int
    behind*: int
    untracked*: int
    details*: seq[RepoHealth]

proc runGit(r, a: string): tuple[text: string, code: int] =
  ## r: repo path.
  ## a: git arguments to execute.
  var
    c: string
    t: tuple[output: string, exitCode: int]
  c = "git -C " & quoteShell(r) & " " & a
  t = execCmdEx(c)
  result = (text: t.output, code: t.exitCode)

proc readBranchName(r: string): string =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --abbrev-ref HEAD")
  var v: string
  if t.code != 0:
    return ""
  v = t.text.strip()
  if v == "HEAD":
    v = "detached"
  result = v

proc readUpstreamName(r: string): string =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --abbrev-ref --symbolic-full-name @{u}")
  if t.code != 0:
    return ""
  result = t.text.strip()

proc readHasRemote(r: string): bool =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "remote")
  result = t.code == 0 and t.text.strip().len > 0

proc readIsSubmodule(r: string): bool =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --show-superproject-working-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc parseStatusCountsFromLines*(ls: seq[string]): tuple[staged: int, modified: int, untracked: int] =
  ## ls: status --porcelain lines.
  var
    staged: int
    modified: int
    untracked: int
    i: int
    line: string
  i = 0
  while i < ls.len:
    line = ls[i]
    if line.len >= 2:
      if line[0] == '?' and line[1] == '?':
        inc untracked
      else:
        if line[0] != ' ':
          inc staged
        if line[1] != ' ':
          inc modified
    inc i
  result = (staged: staged, modified: modified, untracked: untracked)

proc readStatusCounts(r: string): tuple[staged: int, modified: int, untracked: int] =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "status --porcelain")
  var ls: seq[string]
  if t.code != 0:
    return (staged: 0, modified: 0, untracked: 0)
  if t.text.strip().len == 0:
    return (staged: 0, modified: 0, untracked: 0)
  ls = t.text.splitLines()
  result = parseStatusCountsFromLines(ls)

proc parseAheadBehind(t: string): tuple[ahead: int, behind: int, ok: bool] =
  ## t: output from rev-list --left-right --count.
  var
    parts: seq[string]
    a: int
    b: int
  parts = t.strip().splitWhitespace()
  if parts.len < 2:
    return (ahead: 0, behind: 0, ok: false)
  try:
    a = parseInt(parts[0])
    b = parseInt(parts[1])
  except ValueError:
    return (ahead: 0, behind: 0, ok: false)
  result = (ahead: a, behind: b, ok: true)

proc readAheadBehind(r: string): tuple[ahead: int, behind: int, ok: bool] =
  ## r: repo path.
  var t: tuple[text: string, code: int] = runGit(r, "rev-list --left-right --count HEAD...@{u}")
  if t.code != 0:
    return (ahead: 0, behind: 0, ok: false)
  result = parseAheadBehind(t.text)

proc buildRepoHealth*(r: string): RepoHealth =
  ## r: repo path.
  var h: RepoHealth
  var tCounts: tuple[staged: int, modified: int, untracked: int]
  var tAhead: tuple[ahead: int, behind: int, ok: bool]
  h.path = normalizePathValue(r)
  h.name = lastPathPart(h.path)
  h.branch = readBranchName(h.path)
  h.upstream = readUpstreamName(h.path)
  h.hasUpstream = h.upstream.len > 0
  h.hasRemote = readHasRemote(h.path)
  h.isSubmodule = readIsSubmodule(h.path)
  tCounts = readStatusCounts(h.path)
  h.staged = tCounts.staged
  h.modified = tCounts.modified
  h.untracked = tCounts.untracked
  if h.hasUpstream:
    tAhead = readAheadBehind(h.path)
    if tAhead.ok:
      h.ahead = tAhead.ahead
      h.behind = tAhead.behind
  result = h

proc buildRepoHealthReport*(rs: seq[string]): RepoHealthReport =
  ## rs: repo paths to scan.
  var
    r: RepoHealthReport
    i: int
    h: RepoHealth
  r.repos = rs.len
  i = 0
  while i < rs.len:
    h = buildRepoHealth(rs[i])
    r.details.add(h)
    if h.staged > 0 or h.modified > 0:
      inc r.dirty
    if h.untracked > 0:
      inc r.untracked
    if h.ahead > 0:
      inc r.ahead
    if h.behind > 0:
      inc r.behind
    inc i
  result = r

proc buildHealthFlags(h: RepoHealth): seq[string] =
  ## h: repo health info.
  var tFlags: seq[string]
  if h.staged > 0:
    tFlags.add("staged:" & $h.staged)
  if h.modified > 0:
    tFlags.add("modified:" & $h.modified)
  if h.untracked > 0:
    tFlags.add("untracked:" & $h.untracked)
  if h.ahead > 0:
    tFlags.add("ahead:" & $h.ahead)
  if h.behind > 0:
    tFlags.add("behind:" & $h.behind)
  if h.isSubmodule:
    tFlags.add("submodule")
  if h.hasRemote:
    tFlags.add("remote")
  if h.hasUpstream:
    tFlags.add("upstream")
  if tFlags.len == 0:
    tFlags.add("clean")
  result = tFlags

proc formatRepoHealthLine*(h: RepoHealth, v: bool): string =
  ## h: repo health info.
  ## v: verbose output toggle.
  var
    t: string
    tFlags: seq[string]
    tBranch: string
  t = h.name
  if v:
    t = t & " | " & h.path
  tBranch = h.branch
  if tBranch.len == 0:
    tBranch = "(unknown)"
  if h.hasUpstream:
    tBranch = tBranch & " -> " & h.upstream
  t = t & " | " & tBranch
  tFlags = buildHealthFlags(h)
  if tFlags.len > 0:
    t = t & " [" & tFlags.join(", ") & "]"
  result = t

proc formatRepoHealthReport*(r: RepoHealthReport, v: bool): seq[string] =
  ## r: health report to format.
  ## v: verbose output toggle.
  var
    ls: seq[string]
    i: int
  ls.add("Repo health:")
  ls.add("Repos: " & $r.repos)
  ls.add("Dirty: " & $r.dirty)
  ls.add("Ahead: " & $r.ahead)
  ls.add("Behind: " & $r.behind)
  ls.add("Untracked: " & $r.untracked)
  if r.details.len == 0:
    ls.add("Details: (none)")
    result = ls
    return
  ls.add("Details:")
  i = 0
  while i < r.details.len:
    ls.add(" - " & formatRepoHealthLine(r.details[i], v))
    inc i
  result = ls
