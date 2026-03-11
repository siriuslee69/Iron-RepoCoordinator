# ==================================================
# | iron Repo Coordinator Conflicts         |
# |------------------------------------------------|
# | Interactive conflict overview + resolution.    |
# ==================================================

import std/[os, strutils, osproc, times]
import ../level0/repo_utils
include ../level0/metaPragmas


type
  ConflictRepoState = object
    name: string
    path: string
    branch: string
    mergeBranch: string
    headEpoch: int64
    mergeEpoch: int64
    files: seq[string]

  ConflictSessionReport* = object
    ok*: bool
    repos*: int
    files*: int
    lines*: seq[string]


const
  ColorGreen = "\e[32m"
  ColorBlue = "\e[34m"
  ColorReset = "\e[0m"


proc addLine(ls: var seq[string], l: string) {.role(helper).} =
  ## ls: line buffer.
  ## l: line to append.
  ls.add(l)

proc runCmd(c: string): tuple[text: string, code: int] {.role(actor).} =
  ## c: command to execute.
  var
    tText: string
    tCode: int
  (tText, tCode) = execCmdEx(c)
  result = (tText, tCode)

proc runGit(r, a: string): tuple[text: string, code: int] {.role(actor).} =
  ## r: repo path.
  ## a: git command arguments.
  var c: string = "git -C " & quoteShell(r) & " " & a
  result = runCmd(c)

proc parseEpoch(text: string): int64 {.role(parser).} =
  ## text: unix epoch text.
  var t: string = text.strip()
  if t.len == 0:
    return 0
  try:
    result = parseInt(t).int64
  except ValueError:
    result = 0

proc formatEpoch(epoch: int64): string {.role(actor).} =
  ## epoch: unix epoch value.
  if epoch <= 0:
    return "unknown"
  result = fromUnix(epoch).local().format("yyyy-MM-dd HH:mm:ss")

proc readConflictFiles(repo: string): seq[string] {.role(parser).} =
  ## repo: repo path to scan for unresolved conflicts.
  var
    t: tuple[text: string, code: int]
    line: string
  t = runGit(repo, "diff --name-only --diff-filter=U")
  if t.code != 0:
    return @[]
  for raw in t.text.splitLines:
    line = raw.strip()
    if line.len > 0:
      result.add(line)

proc readBranch(repo: string): string {.role(parser).} =
  ## repo: repo path.
  var t: tuple[text: string, code: int] = runGit(repo, "rev-parse --abbrev-ref HEAD")
  if t.code != 0:
    return "(unknown)"
  result = t.text.strip()

proc readMergeBranch(repo: string): string {.role(parser).} =
  ## repo: repo path.
  var t: tuple[text: string, code: int]
  t = runGit(repo, "name-rev --name-only MERGE_HEAD")
  if t.code == 0 and t.text.strip().len > 0:
    return t.text.strip()
  t = runGit(repo, "rev-parse --short MERGE_HEAD")
  if t.code == 0 and t.text.strip().len > 0:
    return t.text.strip()
  result = "(merge)"

proc readHeadEpoch(repo: string): int64 {.role(parser).} =
  ## repo: repo path.
  var t: tuple[text: string, code: int] = runGit(repo, "show -s --format=%ct HEAD")
  if t.code != 0:
    return 0
  result = parseEpoch(t.text)

proc readMergeEpoch(repo: string): int64 {.role(parser).} =
  ## repo: repo path.
  var t: tuple[text: string, code: int] = runGit(repo, "show -s --format=%ct MERGE_HEAD")
  if t.code != 0:
    return 0
  result = parseEpoch(t.text)

proc collectConflictRepos(rootPath: string): seq[ConflictRepoState] {.role(truthBuilder).} =
  ## rootPath: directory containing repos to scan.
  var
    repos: seq[string]
    s: ConflictRepoState
  repos = collectRepos(@[rootPath])
  for r in repos:
    s.path = r
    s.files = readConflictFiles(r)
    if s.files.len == 0:
      continue
    s.name = lastPathPart(r)
    s.branch = readBranch(r)
    s.mergeBranch = readMergeBranch(r)
    s.headEpoch = readHeadEpoch(r)
    s.mergeEpoch = readMergeEpoch(r)
    result.add(s)

proc chooseColors(s: ConflictRepoState): tuple[ours: string, theirs: string] {.role(helper).} =
  ## s: conflict repo state with timestamp metadata.
  if s.headEpoch <= 0 or s.mergeEpoch <= 0:
    return (ColorGreen, ColorBlue)
  if s.headEpoch >= s.mergeEpoch:
    result = (ColorGreen, ColorBlue)
  else:
    result = (ColorBlue, ColorGreen)

proc buildDiffLines(oursText: string, theirsText: string, maxDiffs: int): seq[string] {.role(truthBuilder).} =
  ## oursText: ours version file content.
  ## theirsText: theirs version file content.
  ## maxDiffs: max differing lines to display.
  var
    ours: seq[string]
    theirs: seq[string]
    maxLen: int
    i: int
    oc: string
    tc: string
  ours = oursText.splitLines()
  theirs = theirsText.splitLines()
  maxLen = ours.len
  if theirs.len > maxLen:
    maxLen = theirs.len
  i = 0
  while i < maxLen and result.len < maxDiffs:
    oc = if i < ours.len: ours[i] else: ""
    tc = if i < theirs.len: theirs[i] else: ""
    if oc != tc:
      result.add($i & ":")
      result.add("  ours  : " & oc)
      result.add("  theirs: " & tc)
    inc i

proc showConflictFile(repo: ConflictRepoState, filePath: string) {.role(actor).} =
  ## repo: conflict state for branch metadata.
  ## filePath: conflicted file path in repo.
  var
    ours: tuple[text: string, code: int]
    theirs: tuple[text: string, code: int]
    cols: tuple[ours: string, theirs: string]
    lines: seq[string]
  ours = runGit(repo.path, "show :2:" & quoteShell(filePath))
  theirs = runGit(repo.path, "show :3:" & quoteShell(filePath))
  if ours.code != 0 or theirs.code != 0:
    echo "Could not load ours/theirs for " & filePath
    return
  cols = chooseColors(repo)
  echo ""
  echo "Conflict file: " & filePath
  echo cols.ours & "OURS   (" & repo.branch & " @ " & formatEpoch(
      repo.headEpoch) & ")" & ColorReset
  echo cols.theirs & "THEIRS (" & repo.mergeBranch & " @ " & formatEpoch(
      repo.mergeEpoch) & ")" & ColorReset
  echo ""
  lines = buildDiffLines(ours.text, theirs.text, 200)
  if lines.len == 0:
    echo "No line-level differences could be computed."
    return
  for line in lines:
    if line.startsWith("  ours"):
      echo cols.ours & line & ColorReset
    elif line.startsWith("  theirs"):
      echo cols.theirs & line & ColorReset
    else:
      echo line
  if lines.len >= 200:
    echo "(diff output truncated)"

proc resolveFile(repoPath: string, filePath: string, mode: string): bool {.role(parser).} =
  ## repoPath: git repo path.
  ## filePath: conflicted file path.
  ## mode: ours/theirs.
  var
    c1: string
    c2: string
  c1 = "git -C " & quoteShell(repoPath) & " checkout --" & mode & " -- " &
      quoteShell(filePath)
  c2 = "git -C " & quoteShell(repoPath) & " add -- " & quoteShell(filePath)
  if execCmd(c1) != 0:
    return false
  result = execCmd(c2) == 0

proc interactRepoConflicts(state: var ConflictRepoState,
    report: var ConflictSessionReport) {.role(helper).} =
  ## state: selected conflict repo state.
  ## report: output report.
  var
    idx: int
    f: string
    action: int
    opts: seq[string]
  while true:
    state.files = readConflictFiles(state.path)
    if state.files.len == 0:
      addLine(report.lines, "Resolved all tracked conflicts in " & state.name & ".")
      return
    opts = @[]
    for fPath in state.files:
      opts.add(fPath)
    opts.add("Rescan")
    opts.add("Back")
    idx = promptOptionsDefault("Conflicts in " & state.name & ":", opts, 0)
    if idx < 0 or idx == opts.len - 1:
      return
    if idx == opts.len - 2:
      continue
    f = state.files[idx]
    showConflictFile(state, f)
    action = promptOptionsDefault("Choose action for " & f & ":", @[
      "Keep ours and mark resolved",
      "Keep theirs and mark resolved",
      "Refresh this file view",
      "Back"
    ], 3)
    if action < 0 or action == 3:
      continue
    if action == 2:
      showConflictFile(state, f)
      continue
    if action == 0:
      if resolveFile(state.path, f, "ours"):
        addLine(report.lines, "Resolved with ours: " & state.name & " :: " & f)
      else:
        report.ok = false
        addLine(report.lines, "Failed resolving with ours: " & state.name &
            " :: " & f)
    elif action == 1:
      if resolveFile(state.path, f, "theirs"):
        addLine(report.lines, "Resolved with theirs: " & state.name & " :: " & f)
      else:
        report.ok = false
        addLine(report.lines, "Failed resolving with theirs: " & state.name &
            " :: " & f)

proc runConflictsExplorer*(rootOverride: string): ConflictSessionReport {.role(orchestrator).} =
  ## rootOverride: optional root directory override.
  var
    report: ConflictSessionReport
    rootPath: string
    states: seq[ConflictRepoState]
    idx: int
    options: seq[string]
    s: ConflictRepoState
  report.ok = true
  rootPath = rootOverride.strip()
  if rootPath.len == 0:
    rootPath = getCurrentDir()
  rootPath = normalizePathValue(rootPath)
  if rootPath.len == 0 or not dirExists(rootPath):
    report.ok = false
    report.lines = @["Root path does not exist: " & rootPath]
    return report
  while true:
    states = collectConflictRepos(rootPath)
    report.repos = states.len
    report.files = 0
    for st in states:
      report.files = report.files + st.files.len
    if states.len == 0:
      addLine(report.lines, "No unresolved conflicts found under " & rootPath)
      return report
    options = @[]
    for st in states:
      options.add(st.name & " (" & $st.files.len & " files)")
    options.add("Rescan")
    options.add("Exit")
    idx = promptOptionsDefault("Conflict overview (" & $states.len & " repos):",
        options, 0)
    if idx < 0 or idx == options.len - 1:
      return report
    if idx == options.len - 2:
      continue
    s = states[idx]
    interactRepoConflicts(s, report)
