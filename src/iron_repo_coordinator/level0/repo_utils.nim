# ==================================================
# | iron Repo Coordinator Repo Utilities    |
# |------------------------------------------------|
# | Shared helpers for scanning and mapping repos. |
# ==================================================

import std/[os, strutils, sets, algorithm, osproc, terminal]


const
  ironDir* = ".iron"
  LegacyironDir* = "iron"
  LocalModulesFile* = ".iron/.local.gitmodules.toml"
  LocalConfigFile* = ".iron/.local.config.toml"
  LocalConfigTemplateFile* = ".iron/.local.config.toml.template"
  LocalModulesTemplateFile* = ".iron/.local.gitmodules.toml.template"
  ProgressFile* = ".iron/PROGRESS.md"
  ProgressFileLower* = ".iron/progress.md"
  LegacyProgressFile* = "iron/progress.md"
  RootsEnv* = "IRON_ROOTS"
  OwnersEnv* = "IRON_OWNERS"
  ForeignModeEnv* = "IRON_FOREIGN_MODE"
  CoordinatorConfigFile* = ".iron/repo_coordinator.toml"
  CoordinatorConfigFileLegacy* = "iron/repo_coordinator.toml"


type
  SubmoduleInfo* = object
    name*: string
    path*: string
    url*: string

  CoordinatorConfig* = object
    owners*: seq[string]
    foreignMode*: string

proc readEnvWithFallback*(envName: string): string =
  ## envName: environment variable name.
  if existsEnv(envName):
    return getEnv(envName, "")
  result = ""

proc normalizeForeignMode*(v: string): string =
  ## v: raw foreign mode value.
  var t: string = v.strip().toLowerAscii()
  if t == "update":
    return "update"
  result = "skip"

proc isTruthyEnv*(envName: string): bool =
  ## envName: environment variable to check for a truthy value.
  var t: string
  if not existsEnv(envName):
    return false
  t = getEnv(envName, "").strip().toLowerAscii()
  result = t in ["1", "true", "yes", "on"]

proc normalizePathValue*(p: string): string =
  ## p: path to normalize for consistent matching.
  var t: string = expandFilename(p)
  t = t.replace('\\', '/')
  if t.len > 1 and t.endsWith("/"):
    t = t[0 .. ^2]
  result = t

proc confirmEnter*(msg: string): bool =
  ## msg: confirmation message.
  if isTruthyEnv("IRON_ASSUME_YES"):
    echo msg & " [auto-confirmed by IRON_ASSUME_YES]"
    return true
  if not isatty(stdin):
    echo msg & " (non-interactive; aborting)"
    return false
  stdout.write(msg & " Press ENTER to continue (anything else aborts): ")
  stdout.flushFile()
  try:
    result = stdin.readLine().len == 0
  except EOFError:
    echo ""
    result = false
  except IOError:
    echo ""
    result = false

proc trimQuotes*(v: string): string =
  ## v: raw value possibly surrounded by quotes.
  var t: string
  t = v.strip()
  if t.len >= 2:
    if (t[0] == '"' and t[^1] == '"') or (t[0] == '\'' and t[^1] == '\''):
      t = t[1 .. ^2]
  result = t

proc splitKeyValueLine*(l: string): tuple[ok: bool, key: string, value: string] =
  ## l: raw line to parse for key-value pairs.
  var t: string
  var i: int
  var k: string
  var v: string
  t = l.strip()
  if t.len == 0:
    result = (false, "", "")
  elif t.startsWith("#") or t.startsWith(";"):
    result = (false, "", "")
  else:
    i = t.find('=')
    if i <= 0:
      result = (false, "", "")
    else:
      k = t[0 .. i - 1].strip()
      v = t[i + 1 .. ^1].strip()
      v = trimQuotes(v)
      result = (k.len > 0, k, v)

proc splitOwners*(v: string): seq[string] =
  ## v: raw owner list.
  var rs: seq[string] = @[]
  var t: string
  var parts: seq[string]
  t = v.replace(';', ',')
  parts = t.split(',')
  for p in parts:
    let s = p.strip().toLowerAscii()
    if s.len > 0:
      rs.add(s)
  result = rs

proc readCoordinatorConfig*(r: string): CoordinatorConfig =
  ## r: repo root directory.
  var c: CoordinatorConfig
  var env: string = readEnvWithFallback(OwnersEnv)
  var fm: string = readEnvWithFallback(ForeignModeEnv)
  var p: string
  c.foreignMode = "update"
  if env.len > 0:
    c.owners = splitOwners(env)
  if fm.len > 0:
    c.foreignMode = normalizeForeignMode(fm)
  p = joinPath(r, CoordinatorConfigFile)
  if not fileExists(p):
    p = joinPath(r, CoordinatorConfigFileLegacy)
  if fileExists(p):
    for line in readFile(p).splitLines:
      let kv = splitKeyValueLine(line)
      if kv.ok:
        case kv.key.toLowerAscii()
        of "owners":
          c.owners = splitOwners(kv.value)
        of "foreign_mode", "foreignmode":
          c.foreignMode = normalizeForeignMode(kv.value)
        else:
          discard
  result = c

proc ownerAllowed*(c: CoordinatorConfig, owner: string): bool =
  ## c: coordinator config with owner list.
  ## owner: repo owner/user string.
  if c.owners.len == 0:
    return true
  result = c.owners.contains(owner.toLowerAscii())

proc ownersConfigured*(c: CoordinatorConfig): bool =
  ## c: coordinator config to check.
  result = c.owners.len > 0

proc ownerWriteAllowed*(c: CoordinatorConfig, owner: string): bool =
  ## c: coordinator config with owner list.
  ## owner: repo owner/user string.
  if owner.len == 0:
    return false
  if not ownersConfigured(c):
    return false
  result = ownerAllowed(c, owner)

proc ownerUpdateAllowed*(c: CoordinatorConfig, owner: string): bool =
  ## c: coordinator config with owner list.
  ## owner: repo owner/user string.
  if ownerWriteAllowed(c, owner):
    return true
  if owner.len == 0:
    return false
  result = c.foreignMode == "update"

proc readOriginUrl*(r: string): string =
  ## r: repo path.
  var
    c: string
    t: tuple[output: string, exitCode: int]
  c = "git -C " & quoteShell(r) & " remote get-url origin"
  t = execCmdEx(c)
  if t.exitCode != 0:
    return ""
  result = t.output.strip()

proc normalizeRemoteUrl*(u: string): string

proc extractOriginOwner*(u: string): string =
  ## u: remote url to parse owner/user from.
  var t: string = u.strip()
  var i: int
  var start: int
  var tail: string
  if t.len == 0:
    return ""
  t = normalizeRemoteUrl(t)
  if t.len == 0:
    return ""
  i = t.find("://")
  if i >= 0:
    start = i + 3
    i = t.find('/', start)
    if i < 0:
      return ""
    tail = t[i + 1 .. ^1]
  else:
    i = t.find(':')
    if i < 0 or i + 1 >= t.len:
      return ""
    tail = t[i + 1 .. ^1]
  i = tail.find('/')
  if i < 0:
    return ""
  result = tail[0 .. i - 1].strip().toLowerAscii()

proc resolveRepoOwner*(r: string): string =
  ## r: repo path.
  var u: string = readOriginUrl(r)
  result = extractOriginOwner(u)

proc findRepoRoot*(p: string, maxSteps: int): string

proc resolveConfigRoot*(p: string): string =
  ## p: starting path.
  var t: string = findRepoRoot(p, 5)
  if t.len == 0:
    return ""
  result = t

proc promptOptionsDefault*(title: string, options: seq[string], defaultIndex: int): int =
  ## title: prompt header.
  ## options: numbered options to display.
  ## defaultIndex: option index returned when ENTER is pressed.
  var
    t: string
    hasDefault: bool
  if not isatty(stdin):
    echo title & " (non-interactive; aborting)"
    return -1
  if options.len == 0:
    return -1
  hasDefault = defaultIndex >= 0 and defaultIndex < options.len
  echo title
  for i in 0 ..< options.len:
    if hasDefault and i == defaultIndex:
      echo "  " & $(i + 1) & ") " & options[i] & " (default)"
    else:
      echo "  " & $(i + 1) & ") " & options[i]
  echo "  x) Abort"
  while true:
    if hasDefault:
      stdout.write("Select option (ENTER for " & $(defaultIndex + 1) & "): ")
    else:
      stdout.write("Select option: ")
    stdout.flushFile()
    try:
      t = stdin.readLine().strip().toLowerAscii()
    except EOFError:
      echo ""
      return -1
    except IOError:
      echo ""
      return -1
    if t.len == 0 and hasDefault:
      return defaultIndex
    if t == "x":
      return -1
    try:
      let idx = parseInt(t)
      if idx >= 1 and idx <= options.len:
        return idx - 1
    except ValueError:
      discard
    echo "Invalid selection. Use 1-" & $options.len & " or x to abort."

proc promptOptions*(title: string, options: seq[string]): int =
  ## title: prompt header.
  ## options: numbered options to display.
  result = promptOptionsDefault(title, options, -1)

proc hasGitMarker*(p: string): bool =
  ## p: path to check for a git marker.
  var t: string = joinPath(p, ".git")
  result = dirExists(t) or fileExists(t)

proc findRepoRoot*(p: string, maxSteps: int): string =
  ## p: start path (may be inside a repo).
  ## maxSteps: max parent traversal steps.
  var
    t: string = normalizePathValue(p)
    i: int = 0
    parent: string
  while t.len > 0 and i < maxSteps:
    if hasGitMarker(t):
      return t
    parent = parentDir(t)
    if parent == t:
      break
    t = parent
    inc i
  result = ""

proc findRepoBelow*(p: string, maxDepth: int): string =
  ## p: start path (not inside a repo).
  ## maxDepth: max depth to scan.
  var
    queue: seq[(string, int)]
    idx: int = 0
    entry: (string, int)
    child: string
  if maxDepth <= 0:
    return ""
  queue.add((normalizePathValue(p), 0))
  while idx < queue.len:
    entry = queue[idx]
    inc idx
    if entry[1] >= maxDepth:
      continue
    for kind, path in walkDir(entry[0]):
      if kind != pcDir:
        continue
      child = path
      if hasGitMarker(child):
        return child
      queue.add((child, entry[1] + 1))
  result = ""

proc resolveDefaultRoot*(p: string, maxSteps: int): string =
  ## p: start path.
  ## maxSteps: max traversal steps.
  var
    repoRoot: string
    root: string
    step: int = 0
  repoRoot = findRepoRoot(p, maxSteps)
  if repoRoot.len == 0:
    repoRoot = findRepoBelow(p, maxSteps)
  if repoRoot.len == 0:
    return ""
  root = parentDir(repoRoot)
  while root.len > 0 and step < maxSteps and hasGitMarker(root):
    root = parentDir(root)
    inc step
  result = normalizePathValue(root)

proc normalizeRemoteUrl*(u: string): string =
  ## u: remote url to normalize.
  var
    t: string
    i: int
  t = u.strip()
  if t.len == 0:
    return ""
  t = t.replace('\\', '/')
  if not t.contains("://"):
    i = t.find(':')
    if i > 0 and i + 1 < t.len and t[i + 1] != '/':
      t = t[0 .. i - 1] & "/" & t[i + 1 .. ^1]
  if t.endsWith(".git"):
    t = t[0 .. ^5]
  if t.len > 1 and t.endsWith("/"):
    t = t[0 .. ^2]
  result = t

proc extractRepoTail*(u: string): string =
  ## u: repo url or path.
  var
    t: string
    i: int
  t = normalizeRemoteUrl(u)
  if t.len == 0:
    result = ""
    return
  i = t.rfind('/')
  if i >= 0:
    t = t[i + 1 .. ^1]
  result = t.toLowerAscii()

proc addRepo(rs: var seq[string], ss: var HashSet[string], r: string) =
  ## rs: repo list to append to.
  ## ss: repo set for de-duplication.
  ## r: repo path to add.
  var t: string = normalizePathValue(r)
  if t.len == 0:
    return
  if not ss.contains(t):
    ss.incl(t)
    rs.add(t)

proc scanRoot(rs: var seq[string], ss: var HashSet[string], r: string) =
  ## rs: repo list to append to.
  ## ss: repo set for de-duplication.
  ## r: root directory to scan.
  var ds: seq[string] = @[]
  var n: string
  try:
    for kind, path in walkDir(r):
      n = lastPathPart(path)
      if kind == pcDir:
        if n == ".git":
          addRepo(rs, ss, parentDir(path))
        else:
          ds.add(path)
      elif kind == pcFile:
        if n == ".git":
          addRepo(rs, ss, parentDir(path))
  except OSError:
    echo "Skipping unreadable path: " & r
  for d in ds:
    scanRoot(rs, ss, d)

proc getRoots*(): seq[string] =
  ## Return configured root directories for repo discovery.
  var rs: seq[string] = @[]
  var t: string = readEnvWithFallback(RootsEnv)
  if t.len == 0:
    let c = resolveDefaultRoot(getCurrentDir(), 5)
    if c.len == 0:
      echo "Please bring me to your coding folder and into one repo and run again."
      return @[]
    rs.add(c)
  else:
    for r in t.split({':', ';'}):
      if r.strip().len > 0:
        rs.add(normalizePathValue(r.strip()))
  result = rs

proc collectRepos*(rs: seq[string]): seq[string] =
  ## rs: root directories to scan.
  var tOut: seq[string] = @[]
  var ss: HashSet[string]
  for r in rs:
    if dirExists(r):
      scanRoot(tOut, ss, r)
  tOut.sort(system.cmp)
  result = tOut

proc collectReposFromRoots*(): seq[string] =
  ## Collect repos using the default root discovery.
  var rs: seq[string] = getRoots()
  result = collectRepos(rs)

proc readSubmodules*(p: string): seq[SubmoduleInfo] =
  ## p: path to the .gitmodules file.
  var
    ms: seq[SubmoduleInfo] = @[]
    m: SubmoduleInfo
    inModule: bool = false
    s: string
    start: int
    stop: int
    n: string
    body: string
    kv: tuple[ok: bool, key: string, value: string]
  if not fileExists(p):
    return @[]
  for line in readFile(p).splitLines:
    s = line.strip()
    if s.len == 0 or s.startsWith("#") or s.startsWith(";"):
      continue
    if s.startsWith("[") and s.endsWith("]"):
      if inModule:
        if m.name.len == 0 and m.path.len > 0:
          m.name = m.path
        ms.add(m)
      m = SubmoduleInfo()
      inModule = true
      if s.startsWith("[submodule"):
        start = s.find('"')
        stop = s.rfind('"')
        if start >= 0 and stop > start:
          m.name = s[start + 1 .. stop - 1]
      else:
        body = s[1 .. ^2].strip()
        n = trimQuotes(body)
        if n.startsWith("submodule."):
          n = n["submodule.".len .. ^1]
        m.name = n
      continue
    if not inModule:
      continue
    kv = splitKeyValueLine(s)
    if not kv.ok:
      continue
    case kv.key.toLowerAscii()
    of "name":
      m.name = kv.value
    of "path":
      m.path = kv.value
    of "url":
      m.url = kv.value
    else:
      discard
  if inModule:
    if m.name.len == 0 and m.path.len > 0:
      m.name = m.path
    ms.add(m)
  result = ms

proc findLocalRepo*(rs: seq[string], t, r: string): string =
  ## rs: known repo paths.
  ## t: repo tail to match.
  ## r: current repo path for preference.
  var ps: seq[string] = @[]
  var root: string = parentDir(r)
  for p in rs:
    if lastPathPart(p) == t:
      ps.add(p)
  if ps.len == 0:
    return ""
  if ps.len == 1:
    return ps[0]
  var opts: seq[string] = @[]
  for p in ps:
    if parentDir(p) == root:
      opts.add(p & " (same parent)")
    else:
      opts.add(p)
  opts.add("Skip")
  let idx = promptOptions("Multiple local repos match " & t & ":", opts)
  if idx < 0 or idx == opts.len - 1:
    return ""
  result = ps[idx]

proc mapLocalSubmodules*(ms: seq[SubmoduleInfo], rs: seq[string], r: string): seq[SubmoduleInfo] =
  ## ms: submodules parsed from .gitmodules.
  ## rs: repo list to match local clones.
  ## r: repo path used for preference.
  var tOut: seq[SubmoduleInfo] = @[]
  var t: string
  var l: string
  var n: SubmoduleInfo
  for m in ms:
    t = splitPath(m.path).tail
    l = findLocalRepo(rs, t, r)
    if l.len > 0:
      n = m
      n.url = l.replace('\\', '/')
      tOut.add(n)
  result = tOut

proc ensureGitignoreEntry*(p, e: string): bool =
  ## p: .gitignore path.
  ## e: entry to ensure.
  var t: string = ""
  var lines: seq[string] = @[]
  if fileExists(p):
    t = readFile(p)
    lines = t.splitLines
  for line in lines:
    if line.strip() == e:
      return false
  if t.len > 0 and not t.endsWith("\n"):
    t.add("\n")
  t.add(e & "\n")
  writeFile(p, t)
  result = true

proc ensureLocalIgnoreRules*(repoPath: string): bool =
  ## repoPath: repository root path.
  var
    gi: string
    changed: bool
  gi = joinPath(repoPath, ".gitignore")
  if ensureGitignoreEntry(gi, ".iron/.local*"):
    changed = true
  if ensureGitignoreEntry(gi, "!.iron/.local*.template"):
    changed = true
  result = changed

proc ensureParentDir*(p: string) =
  ## p: file path to ensure parent directories for.
  let d = parentDir(p)
  if d.len == 0:
    return
  if not dirExists(d):
    createDir(d)

proc resolveProgressFile*(repoPath: string): string =
  ## repoPath: repository root path.
  var
    cands: seq[string]
    i: int
  cands = @[
    joinPath(repoPath, ProgressFile),
    joinPath(repoPath, ProgressFileLower),
    joinPath(repoPath, LegacyProgressFile),
    joinPath(repoPath, "progress.md")
  ]
  i = 0
  while i < cands.len:
    if fileExists(cands[i]):
      return cands[i]
    inc i
  result = cands[0]

proc readCommitMessage*(repoPath: string, defaultMsg: string = "Auto update"): string =
  ## repoPath: repository root path.
  ## defaultMsg: fallback message when no progress file value exists.
  var
    p: string
    m: string
  p = resolveProgressFile(repoPath)
  m = defaultMsg
  if fileExists(p):
    for line in readFile(p).splitLines:
      if line.startsWith("Commit Message:"):
        m = line["Commit Message:".len .. ^1].strip()
        break
  if m.strip().len == 0:
    m = defaultMsg
  result = m

proc tomlQuote(v: string): string =
  ## v: raw string to quote for toml output.
  result = "\"" & v.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc writeLocalModules*(p: string, ms: seq[SubmoduleInfo]) =
  ## p: path to .local.gitmodules.toml.
  ## ms: submodules with local urls.
  var
    t: string
    sectionName: string
  t = "# Local submodule overrides generated by iron\n"
  for m in ms:
    sectionName = m.name
    if sectionName.len == 0:
      sectionName = m.path
    if sectionName.len == 0:
      sectionName = extractRepoTail(m.url)
    t.add("\n[" & tomlQuote(sectionName) & "]\n")
    t.add("name = " & tomlQuote(m.name) & "\n")
    t.add("path = " & tomlQuote(m.path) & "\n")
    t.add("url = " & tomlQuote(m.url) & "\n")
  ensureParentDir(p)
  writeFile(p, t)

proc mergeSubmodules*(ms, ns: seq[SubmoduleInfo]): seq[SubmoduleInfo] =
  ## ms: existing submodule list.
  ## ns: new submodule entries.
  var
    tOut: seq[SubmoduleInfo] = ms
    n: SubmoduleInfo
    i: int
    j: int
    found: bool
    nKey: string
    tKey: string
  i = 0
  while i < ns.len:
    n = ns[i]
    nKey = n.name
    if nKey.len == 0:
      nKey = n.path
    found = false
    j = 0
    while j < tOut.len:
      tKey = tOut[j].name
      if tKey.len == 0:
        tKey = tOut[j].path
      if tKey == nKey:
        tOut[j] = n
        found = true
        break
      inc j
    if not found:
      tOut.add(n)
    inc i
  result = tOut

proc applyLocalConfig*(r: string, ms: seq[SubmoduleInfo]): int =
  ## r: repo path to update git config in.
  ## ms: submodule overrides with local urls.
  var
    m: SubmoduleInfo
    k: string
    c: string
    fail: int = 0
    i: int
    keyName: string
  i = 0
  while i < ms.len:
    m = ms[i]
    keyName = m.name
    if keyName.len == 0:
      keyName = m.path
    if keyName.len == 0 or m.url.len == 0:
      inc i
      continue
    k = "submodule." & keyName & ".url"
    c = "git -C " & quoteShell(r) & " config " & quoteShell(k) & " " & quoteShell(m.url)
    if execCmd(c) != 0:
      fail = 1
    inc i
  result = fail
