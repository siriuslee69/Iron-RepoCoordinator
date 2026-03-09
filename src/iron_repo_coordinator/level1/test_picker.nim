# ==================================================
# | iron Repo Coordinator Test Picker       |
# |------------------------------------------------|
# | Discover and run test tasks across repos.      |
# ==================================================

import std/[os, strutils, osproc, sequtils]
import ../level0/repo_utils


const
  TestMapLetters* = @["a", "s", "d", "f", "j", "k", "l"]
  EitriTasksFile* = "eitri.toml"


type
  TaskKind* = enum
    tkNimble,
    tkEitri
  TaskEntry* = object
    kind*: TaskKind
    repo*: string
    name*: string
    detail*: string
    command*: string


proc hasTestWord(s: string): bool =
  ## s: text to check for test keyword.
  result = s.toLowerAscii().contains("test")

proc parseTaskName(s: string): string =
  ## s: nimble task line content after "task ".
  var
    t: string
    iComma: int
    iSpace: int
    iEnd: int
  t = s.strip()
  iComma = t.find(',')
  iSpace = t.find(' ')
  iEnd = t.len
  if iComma >= 0 and iComma < iEnd:
    iEnd = iComma
  if iSpace >= 0 and iSpace < iEnd:
    iEnd = iSpace
  if iEnd <= 0:
    return ""
  result = t[0 .. iEnd - 1].strip()

proc parseTaskDesc(s: string): string =
  ## s: nimble task line.
  var
    iStart: int
    iStop: int
  iStart = s.find('"')
  iStop = s.rfind('"')
  if iStart >= 0 and iStop > iStart:
    result = s[iStart + 1 .. iStop - 1]
  else:
    result = ""

proc readNimbleTasks*(p, r: string): seq[TaskEntry] =
  ## p: nimble file path.
  ## r: repo root path.
  var
    tOut: seq[TaskEntry]
    ls: seq[string]
    line: string
    s: string
    name: string
    desc: string
    t: TaskEntry
    i: int
  ls = readFile(p).splitLines
  i = 0
  while i < ls.len:
    line = ls[i]
    s = line.strip()
    if s.startsWith("task "):
      name = parseTaskName(s["task ".len .. ^1])
      if name.len == 0:
        inc i
        continue
      if not hasTestWord(name):
        inc i
        continue
      desc = parseTaskDesc(s)
      t.kind = tkNimble
      t.repo = r
      t.name = name
      t.detail = desc
      t.command = "nimble " & name
      tOut.add(t)
    inc i
  result = tOut

proc cleanTomlValue(s: string): string =
  ## s: toml value string.
  var t: string = s.strip()
  if t.len >= 2 and t[0] == '"' and t[^1] == '"':
    t = t[1 .. ^2]
  result = t

proc readEitriTasks*(p, r: string): seq[TaskEntry] =
  ## p: eitri.toml file path.
  ## r: repo root path.
  var
    tOut: seq[TaskEntry]
    ls: seq[string]
    line: string
    s: string
    section: string
    inTasks: bool
    iEq: int
    name: string
    cmd: string
    t: TaskEntry
    i: int
  ls = readFile(p).splitLines
  i = 0
  while i < ls.len:
    line = ls[i]
    s = line.strip()
    if s.len == 0 or s.startsWith("#"):
      inc i
      continue
    if s.startsWith("[") and s.endsWith("]"):
      section = s[1 .. ^2].strip().toLowerAscii()
      inTasks = section == "tasks" or section == "eitri.tasks"
      inc i
      continue
    if not inTasks:
      inc i
      continue
    iEq = s.find('=')
    if iEq < 0:
      inc i
      continue
    name = s[0 .. iEq - 1].strip()
    cmd = cleanTomlValue(s[iEq + 1 .. ^1])
    if name.len == 0:
      inc i
      continue
    if not hasTestWord(name):
      inc i
      continue
    t.kind = tkEitri
    t.repo = r
    t.name = name
    t.detail = cmd
    t.command = cmd
    tOut.add(t)
    inc i
  result = tOut

proc collectTestTasks*(rs: seq[string]): seq[TaskEntry] =
  ## rs: repo roots to scan.
  var
    tOut: seq[TaskEntry]
    r: string
    kind: PathComponent
    path: string
    p: string
    ts: seq[TaskEntry]
    i: int
    entries: seq[(PathComponent, string)]
    j: int
  i = 0
  while i < rs.len:
    r = rs[i]
    if not dirExists(r):
      inc i
      continue
    entries = toSeq(walkDir(r))
    j = 0
    while j < entries.len:
      kind = entries[j][0]
      path = entries[j][1]
      if kind == pcFile and path.endsWith(".nimble"):
        ts = readNimbleTasks(path, r)
        if ts.len > 0:
          tOut.add(ts)
      inc j
    p = joinPath(r, EitriTasksFile)
    if fileExists(p):
      ts = readEitriTasks(p, r)
      if ts.len > 0:
        tOut.add(ts)
    inc i
  result = tOut

proc buildMappings*(l: int): seq[string] =
  ## l: number of mappings needed.
  var
    tOut: seq[string]
    i: int
    j: int
    a: string
    b: string
  i = 0
  while i < TestMapLetters.len and tOut.len < l:
    tOut.add(TestMapLetters[i])
    inc i
  i = 0
  while i < TestMapLetters.len and tOut.len < l:
    a = TestMapLetters[i]
    j = 0
    while j < TestMapLetters.len and tOut.len < l:
      b = TestMapLetters[j]
      tOut.add(a & b)
      inc j
    inc i
  result = tOut

proc formatTaskLine*(m: string, t: TaskEntry): string =
  ## m: mapping token.
  ## t: task entry.
  var
    k: string
    repoName: string
    line: string
  case t.kind
  of tkNimble:
    k = "nimble"
  of tkEitri:
    k = "eitri"
  repoName = lastPathPart(t.repo)
  line = "[" & m & "] " & k & ":" & t.name & " (" & repoName & ")"
  if t.detail.len > 0:
    line = line & " - " & t.detail
  result = line

proc readChoice(ms: seq[string]): int =
  ## ms: mapping tokens.
  var
    input: string
    i: int
  stdout.write("Select test: ")
  stdout.flushFile()
  input = stdin.readLine().strip().toLowerAscii()
  i = 0
  while i < ms.len:
    if ms[i] == input:
      result = i
      return
    inc i
  result = -1

proc runProcessInDir(r: string, c: string, args: seq[string]): int =
  ## r: working directory.
  ## c: command to execute.
  ## args: command arguments.
  var p: Process
  p = startProcess(c, args = args, workingDir = r, options = {poUsePath, poParentStreams})
  result = waitForExit(p)

proc splitCommand(s: string): tuple[cmd: string, args: seq[string]] =
  ## s: command string to split.
  var
    parts: seq[string]
  parts = s.splitWhitespace()
  if parts.len == 0:
    result = ("", @[])
    return
  result = (parts[0], parts[1 .. ^1])

proc runTask*(t: TaskEntry): int =
  ## t: task entry to execute.
  var
    parts: tuple[cmd: string, args: seq[string]]
  case t.kind
  of tkNimble:
    result = runProcessInDir(t.repo, "nimble", @[t.name])
  of tkEitri:
    if t.command.len == 0:
      echo "No command configured for Eitri task: " & t.name
      return 1
    parts = splitCommand(t.command)
    if parts.cmd.len == 0:
      echo "Invalid command for Eitri task: " & t.name
      return 1
    result = runProcessInDir(t.repo, parts.cmd, parts.args)

proc runTestPicker*(): int =
  ## runs the interactive test picker.
  var
    rs: seq[string]
    ts: seq[TaskEntry]
    ms: seq[string]
    i: int
    line: string
    choice: int
  rs = collectReposFromRoots()
  ts = collectTestTasks(rs)
  if ts.len == 0:
    echo "No test tasks found."
    return 0
  ms = buildMappings(ts.len)
  if ms.len < ts.len:
    echo "Too many tasks for available mappings."
    return 1
  echo "Discovered " & $ts.len & " test tasks."
  i = 0
  while i < ts.len:
    line = formatTaskLine(ms[i], ts[i])
    echo line
    inc i
  choice = readChoice(ms)
  if choice < 0 or choice >= ts.len:
    echo "Invalid selection."
    return 1
  result = runTask(ts[choice])
