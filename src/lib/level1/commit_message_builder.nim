# ==================================================
# | iron Commit Message Builder               |
# |------------------------------------------------|
# | Diff-aware commit message perception/truth/act.|
# ==================================================

import std/[algorithm, os, osproc, sets, strutils]
import ../level0/repo_utils
include ../level0/metaPragmas


type
  CommitFileKind* = enum
    cfNim
    cfDocs
    cfConfig
    cfOther

  DiffStatusKind = enum
    dskUnknown
    dskModified
    dskAdded
    dskDeleted
    dskRenamed
    dskCopied
    dskUntracked

  CommitStatusInput = object
    path: string
    oldPath: string
    kind: DiffStatusKind

  CommitDiffLineInput = object
    kind: char
    oldLine: int
    newLine: int
    text: string

  CommitHunkInput = object
    oldStart: int
    oldLen: int
    newStart: int
    newLen: int
    lines: seq[CommitDiffLineInput]

  CommitPatchInput = object
    path: string
    oldPath: string
    renameOnlyByHeader: bool
    hunks: seq[CommitHunkInput]

  CommitFileInput = object
    status: CommitStatusInput
    patch: CommitPatchInput
    currentText: string
    previousText: string
    currentExists: bool
    previousExists: bool

  NimFunctionTruth* = object
    filePath*: string
    name*: string
    role*: string
    risk*: string
    tags*: string

  CommitMessageTruthState* = object
    repoPath*: string
    nimFiles*: int
    docsFiles*: int
    configFiles*: int
    otherFiles*: int
    renameOnlyFiles*: int
    touchedFunctionCount*: int
    touchedFunctions*: seq[NimFunctionTruth]
    progressHint*: string

  NimDeclTruth = object
    filePath: string
    name: string
    role: string
    risk: string
    tags: string
    startLine: int
    endLine: int


const
  NimKeywords = [
    "addr", "and", "as", "asm", "bind", "block", "break", "case", "cast",
    "concept", "const", "continue", "converter", "defer", "discard", "distinct",
    "div", "do", "elif", "else", "end", "enum", "except", "export", "finally",
    "for", "from", "func", "if", "import", "in", "include", "interface",
    "is", "isnot", "iterator", "let", "macro", "method", "mixin", "mod", "nil",
    "not", "notin", "object", "of", "or", "out", "proc", "ptr", "raise", "ref",
    "return", "shl", "shr", "static", "template", "try", "tuple", "type",
    "using", "var", "when", "while", "xor", "yield"
  ]


proc runGit(repoPath: string, args: string): tuple[text: string, code: int] {.role(actor).} =
  ## repoPath: repo path to run git in.
  ## args: git arguments.
  var
    tText: string
    tCode: int
    cmd: string
  cmd = "git -c submodule.recurse=false -C " & quoteShell(repoPath) & " " & args
  (tText, tCode) = execCmdEx(cmd)
  result = (tText, tCode)

proc readCommitMessageHeadline*(msg: string): string {.role(parser).} =
  ## msg: full commit message.
  for line in msg.splitLines():
    if line.strip().len > 0:
      return line.strip()
  result = msg.strip()

proc readCommitKeyword*(t: CommitMessageTruthState): string {.role(parser).} =
  ## t: commit message truth state to classify.
  let totalFiles = t.nimFiles + t.docsFiles + t.configFiles + t.otherFiles
  let codeOnly = t.nimFiles > 0 and t.docsFiles == 0 and t.configFiles == 0 and
      t.otherFiles == 0
  let renameOnly = t.renameOnlyFiles > 0 and t.renameOnlyFiles == totalFiles
  let onlyDocs = t.docsFiles > 0 and t.nimFiles == 0 and t.configFiles == 0 and
      t.otherFiles == 0
  let onlyConfig = t.configFiles > 0 and t.nimFiles == 0 and t.docsFiles == 0 and
      t.otherFiles == 0
  let docsAndConfigOnly = t.nimFiles == 0 and t.otherFiles == 0 and
      t.docsFiles > 0 and t.configFiles > 0
  let onlyOther = t.otherFiles > 0 and t.nimFiles == 0 and t.docsFiles == 0 and
      t.configFiles == 0
  let apiHeavy = t.touchedFunctionCount >= 5 or
      (t.nimFiles >= 2 and t.touchedFunctionCount >= 3)
  let mixedCode = t.nimFiles > 0 and (t.docsFiles > 0 or t.configFiles > 0 or
      t.otherFiles > 0)
  if totalFiles == 0:
    return "Auto update"
  if renameOnly:
    if onlyDocs:
      if t.docsFiles >= 3:
        return "Doc rename sweep"
      return "Doc rename"
    if onlyConfig:
      if t.configFiles >= 3:
        return "Config rename sweep"
      return "Config rename"
    if docsAndConfigOnly:
      return "Metadata rename"
    if t.renameOnlyFiles >= 3 or t.touchedFunctionCount >= 3 or t.nimFiles >= 2:
      return "Big rename"
    return "Small rename"
  if onlyDocs:
    if t.docsFiles >= 3:
      return "Doc sweep"
    return "Doc change"
  if onlyConfig:
    if t.configFiles >= 3:
      return "Config sweep"
    return "Config change"
  if docsAndConfigOnly:
    if t.docsFiles + t.configFiles >= 4:
      return "Metadata sweep"
    return "Metadata update"
  if codeOnly and t.touchedFunctionCount == 1 and totalFiles == 1:
    return "Function change"
  if codeOnly and apiHeavy:
    return "API sweep"
  if codeOnly and t.touchedFunctionCount >= 2:
    return "API change"
  if codeOnly and t.renameOnlyFiles > 0 and totalFiles <= 2 and
      t.touchedFunctionCount <= 2:
    return "Code rename"
  if codeOnly and t.nimFiles >= 3:
    return "Code sweep"
  if codeOnly:
    return "Code change"
  if t.nimFiles > 0 and t.docsFiles > 0 and t.configFiles == 0 and t.otherFiles == 0:
    if apiHeavy or totalFiles >= 5:
      return "Big change"
    return "Code + docs"
  if t.nimFiles > 0 and t.configFiles > 0 and t.docsFiles == 0 and t.otherFiles == 0:
    if apiHeavy or totalFiles >= 5:
      return "Big change"
    return "Code + config"
  if t.nimFiles > 0 and (apiHeavy or mixedCode or totalFiles >= 5):
    return "Big change"
  if onlyOther:
    if totalFiles >= 4:
      return "Project sweep"
    return "Project change"
  if t.otherFiles > 0 and (t.docsFiles > 0 or t.configFiles > 0):
    if totalFiles >= 5:
      return "Project sweep"
    return "Project update"
  result = "Mixed change"

proc readFileKind(path: string): CommitFileKind {.role(parser).} =
  ## path: changed file path.
  let ext = splitFile(path).ext.toLowerAscii()
  case ext
  of ".nim":
    result = cfNim
  of ".md", ".markdown":
    result = cfDocs
  of ".json", ".toml", ".nims", ".nimble", ".cfg", ".ini", ".yaml", ".yml":
    result = cfConfig
  else:
    result = cfOther

proc parseStatusKind(t: string): DiffStatusKind {.role(parser).} =
  ## t: porcelain status code.
  var
    c: char
  if t == "??":
    return dskUntracked
  c = ' '
  if t.len >= 1 and t[0] != ' ':
    c = t[0]
  elif t.len >= 2 and t[1] != ' ':
    c = t[1]
  case c
  of 'M':
    result = dskModified
  of 'A':
    result = dskAdded
  of 'D':
    result = dskDeleted
  of 'R':
    result = dskRenamed
  of 'C':
    result = dskCopied
  else:
    result = dskUnknown

proc readStatusInputs(repoPath: string): seq[CommitStatusInput] {.role(parser).} =
  ## repoPath: repo path to inspect.
  var
    t: tuple[text: string, code: int]
    line: string
    status: CommitStatusInput
    body: string
    idx: int
  t = runGit(repoPath,
      "status --porcelain=1 --find-renames --untracked-files=all --ignore-submodules=dirty")
  if t.code != 0:
    return @[]
  for rawLine in t.text.splitLines():
    line = rawLine
    if line.len < 3:
      continue
    status = CommitStatusInput()
    status.kind = parseStatusKind(line[0 .. 1])
    body = line[3 .. ^1].strip()
    if status.kind == dskRenamed or status.kind == dskCopied:
      idx = body.find(" -> ")
      if idx >= 0:
        status.oldPath = body[0 .. idx - 1].strip()
        status.path = body[idx + " -> ".len .. ^1].strip()
      else:
        status.path = body
    else:
      status.path = body
      status.oldPath = body
    if status.kind == dskDeleted:
      status.oldPath = status.path
    result.add(status)

proc trimDiffPathToken(t: string): string {.role(parser).} =
  ## t: diff header path token.
  var
    s: string
  s = t.strip()
  if s == "/dev/null":
    return ""
  if s.len >= 2 and s[0] == '"' and s[^1] == '"':
    s = s[1 .. ^2]
    s = s.replace("\\\"", "\"")
  if s.startsWith("a/") or s.startsWith("b/"):
    s = s[2 .. ^1]
  result = s

proc parseRange(t: string): tuple[startPos: int, len: int] {.role(parser).} =
  ## t: unified diff range token without leading +/-.
  var
    idx: int
  idx = t.find(',')
  if idx < 0:
    if t.len == 0:
      return (0, 0)
    return (parseInt(t), 1)
  result.startPos = parseInt(t[0 .. idx - 1])
  result.len = parseInt(t[idx + 1 .. ^1])

proc parseHunkHeader(t: string): tuple[ok: bool, oldStart: int, oldLen: int,
    newStart: int, newLen: int] {.role(parser).} =
  ## t: unified diff hunk header.
  var
    line: string
    closeIdx: int
    body: string
    parts: seq[string]
    oldRange: tuple[startPos: int, len: int]
    newRange: tuple[startPos: int, len: int]
  line = t.strip()
  if not line.startsWith("@@"):
    return (false, 0, 0, 0, 0)
  closeIdx = line.find("@@", 2)
  if closeIdx < 0:
    return (false, 0, 0, 0, 0)
  body = line[2 .. closeIdx - 1].strip()
  parts = body.splitWhitespace()
  if parts.len < 2:
    return (false, 0, 0, 0, 0)
  if parts[0].len < 2 or parts[1].len < 2:
    return (false, 0, 0, 0, 0)
  oldRange = parseRange(parts[0][1 .. ^1])
  newRange = parseRange(parts[1][1 .. ^1])
  result = (true, oldRange.startPos, oldRange.len, newRange.startPos, newRange.len)

proc parsePatchSection(lines: seq[string]): CommitPatchInput {.role(parser).} =
  ## lines: patch lines for one file.
  var
    i: int
    header: tuple[ok: bool, oldStart: int, oldLen: int, newStart: int, newLen: int]
    hunk: CommitHunkInput
    oldLine: int
    newLine: int
    text: string
  i = 0
  while i < lines.len:
    if lines[i].startsWith("--- "):
      result.oldPath = trimDiffPathToken(lines[i]["--- ".len .. ^1])
    elif lines[i].startsWith("+++ "):
      result.path = trimDiffPathToken(lines[i]["+++ ".len .. ^1])
    elif lines[i].startsWith("@@"):
      header = parseHunkHeader(lines[i])
      if not header.ok:
        inc i
        continue
      hunk.oldStart = header.oldStart
      hunk.oldLen = header.oldLen
      hunk.newStart = header.newStart
      hunk.newLen = header.newLen
      hunk.lines = @[]
      oldLine = header.oldStart
      newLine = header.newStart
      inc i
      while i < lines.len and not lines[i].startsWith("@@"):
        text = lines[i]
        if text.startsWith("\\ No newline"):
          inc i
          continue
        if text.len > 0 and text[0] == '-':
          hunk.lines.add(CommitDiffLineInput(
            kind: '-',
            oldLine: oldLine,
            newLine: 0,
            text: text[1 .. ^1]
          ))
          inc oldLine
        elif text.len > 0 and text[0] == '+':
          hunk.lines.add(CommitDiffLineInput(
            kind: '+',
            oldLine: 0,
            newLine: newLine,
            text: text[1 .. ^1]
          ))
          inc newLine
        elif text.len > 0 and text[0] == ' ':
          inc oldLine
          inc newLine
        inc i
      result.hunks.add(hunk)
      continue
    inc i
  if result.path.len == 0:
    result.path = result.oldPath
  if result.oldPath.len == 0:
    result.oldPath = result.path
  result.renameOnlyByHeader = result.path.len > 0 and result.oldPath.len > 0 and
      result.path != result.oldPath and result.hunks.len == 0

proc readPatchInputs(repoPath: string): seq[CommitPatchInput] {.role(parser).} =
  ## repoPath: repo path to inspect.
  var
    t: tuple[text: string, code: int]
    section: seq[string]
  t = runGit(repoPath, "diff --no-ext-diff --find-renames --unified=0 HEAD --")
  if t.code != 0 or t.text.len == 0:
    return @[]
  for line in t.text.splitLines():
    if line.startsWith("diff --git "):
      if section.len > 0:
        result.add(parsePatchSection(section))
      section = @[line]
    elif section.len > 0:
      section.add(line)
  if section.len > 0:
    result.add(parsePatchSection(section))

proc findPatchInput(status: CommitStatusInput, patches: seq[CommitPatchInput]): CommitPatchInput {.role(parser).} =
  ## status: changed file status input.
  ## patches: parsed patch sections.
  var
    i: int
    patch: CommitPatchInput
  i = 0
  while i < patches.len:
    patch = patches[i]
    if status.kind in [dskRenamed, dskCopied]:
      if patch.path == status.path and patch.oldPath == status.oldPath:
        return patch
    elif status.kind == dskDeleted:
      if patch.oldPath == status.path or patch.path == status.path:
        return patch
    else:
      if patch.path == status.path or patch.oldPath == status.path:
        return patch
    inc i

proc toSystemPath(repoPath: string, relPath: string): string {.role(helper).} =
  ## repoPath: repository root path.
  ## relPath: repo-relative path.
  result = joinPath(repoPath, relPath.replace('/', DirSep).replace('\\', DirSep))

proc readCurrentText(repoPath: string, relPath: string): tuple[ok: bool, text: string] {.role(parser).} =
  ## repoPath: repository root path.
  ## relPath: repo-relative current path.
  let p = toSystemPath(repoPath, relPath)
  if relPath.len == 0 or not fileExists(p):
    return (false, "")
  result = (true, readFile(p))

proc readPreviousText(repoPath: string, relPath: string): tuple[ok: bool, text: string] {.role(parser).} =
  ## repoPath: repository root path.
  ## relPath: repo-relative HEAD path.
  var t: tuple[text: string, code: int]
  if relPath.len == 0:
    return (false, "")
  t = runGit(repoPath, "show " & quoteShell("HEAD:" & relPath.replace('\\', '/')))
  if t.code != 0:
    return (false, "")
  result = (true, t.text)

proc buildCommitInputs(repoPath: string): seq[CommitFileInput] {.role(truthBuilder).} =
  ## repoPath: repository root path.
  var
    statuses: seq[CommitStatusInput]
    patches: seq[CommitPatchInput]
    currentText: tuple[ok: bool, text: string]
    previousText: tuple[ok: bool, text: string]
    i: int
    input: CommitFileInput
  statuses = readStatusInputs(repoPath)
  patches = readPatchInputs(repoPath)
  i = 0
  while i < statuses.len:
    input = CommitFileInput()
    input.status = statuses[i]
    input.patch = findPatchInput(statuses[i], patches)
    if statuses[i].kind != dskDeleted:
      currentText = readCurrentText(repoPath, statuses[i].path)
      input.currentExists = currentText.ok
      input.currentText = currentText.text
    if statuses[i].kind notin [dskAdded, dskUntracked]:
      previousText = readPreviousText(repoPath,
          if statuses[i].oldPath.len > 0: statuses[i].oldPath else: statuses[i].path)
      input.previousExists = previousText.ok
      input.previousText = previousText.text
    result.add(input)
    inc i

proc startsWithWordPrefix(s: string, w: string): bool {.role(helper).} =
  ## s: normalized line.
  ## w: word prefix.
  if not s.startsWith(w):
    return false
  if s.len == w.len:
    return true
  result = s[w.len] in {' ', '\t'}

proc readDeclKind(s: string): string {.role(parser).} =
  ## s: normalized source line.
  if startsWithWordPrefix(s, "proc"):
    return "proc"
  if startsWithWordPrefix(s, "func"):
    return "func"
  if startsWithWordPrefix(s, "template"):
    return "template"
  if startsWithWordPrefix(s, "macro"):
    return "macro"
  if startsWithWordPrefix(s, "iterator"):
    return "iterator"
  result = ""

proc parseDeclName(s: string, k: string): string {.role(parser).} =
  ## s: normalized declaration line.
  ## k: declaration kind.
  var
    t: string
    i: int
    c: char
  t = s[k.len .. ^1].strip()
  if t.len == 0:
    return ""
  if t[0] == '`':
    i = 1
    while i < t.len and t[i] != '`':
      result.add(t[i])
      inc i
    return result
  i = 0
  while i < t.len:
    c = t[i]
    if c in {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
      result.add(c)
      inc i
    else:
      break

proc readIndentLevel(s: string): int {.role(parser).} =
  ## s: source line to inspect.
  var
    i: int
  i = 0
  while i < s.len:
    if s[i] == ' ':
      inc result
    elif s[i] == '\t':
      result = result + 2
    else:
      break
    inc i

proc readPragmaValue(signature: string, pragmaName: string): string {.role(parser).} =
  ## signature: flattened declaration signature text.
  ## pragmaName: pragma function name to read.
  var
    startIdx: int
    idx: int
    depth: int
  startIdx = signature.find(pragmaName & "(")
  if startIdx < 0:
    return ""
  idx = startIdx + pragmaName.len + 1
  depth = 1
  while idx < signature.len:
    if signature[idx] == '(':
      inc depth
      result.add(signature[idx])
    elif signature[idx] == ')':
      dec depth
      if depth == 0:
        break
      result.add(signature[idx])
    else:
      result.add(signature[idx])
    inc idx
  result = result.strip()

proc normalizeTagsText(t: string): string {.role(parser).} =
  ## t: raw tags pragma contents.
  var
    s: string
  s = t.strip()
  if s.len == 0:
    return "none"
  if s.startsWith("{") and s.endsWith("}") and s.len >= 2:
    s = s[1 .. ^2].strip()
  if s.len == 0:
    return "none"
  result = s

proc normalizePragmaText(t: string): string {.role(parser).} =
  ## t: raw pragma text.
  if t.strip().len == 0:
    return "none"
  result = t.strip()

proc readDeclSignature(lines: seq[string], startIdx: int): tuple[lastSigIdx: int, text: string] {.role(parser).} =
  ## lines: source lines.
  ## startIdx: declaration start index.
  var
    i: int
    startIndent: int
    nextIndent: int
  i = startIdx
  startIndent = readIndentLevel(lines[startIdx])
  result.text = lines[startIdx].strip()
  result.lastSigIdx = startIdx
  while i + 1 < lines.len:
    if lines[i].contains("=") or lines[i].strip().endsWith("="):
      break
    if lines[i + 1].strip().len == 0:
      break
    nextIndent = readIndentLevel(lines[i + 1])
    if nextIndent <= startIndent and readDeclKind(lines[i + 1].strip()).len > 0:
      break
    inc i
    result.text = result.text & " " & lines[i].strip()
    result.lastSigIdx = i
    if lines[i].contains("=") or lines[i].strip().endsWith("="):
      break

proc parseNimDecls(text: string, filePath: string): seq[NimDeclTruth] {.role(metaParser).} =
  ## text: Nim module source text.
  ## filePath: repo-relative file path.
  var
    lines: seq[string]
    sig: tuple[lastSigIdx: int, text: string]
    decl: NimDeclTruth
    idxs: seq[int]
    i: int
    j: int
    nextIdx: int
    currentIndent: int
    nextIndent: int
    kind: string
  lines = text.splitLines()
  i = 0
  while i < lines.len:
    kind = readDeclKind(lines[i].strip())
    if kind.len > 0:
      decl = NimDeclTruth()
      decl.name = parseDeclName(lines[i].strip(), kind)
      if decl.name.len > 0:
        sig = readDeclSignature(lines, i)
        decl.role = normalizePragmaText(readPragmaValue(sig.text, "role"))
        decl.risk = normalizePragmaText(readPragmaValue(sig.text, "risk"))
        decl.tags = normalizeTagsText(readPragmaValue(sig.text, "tags"))
        decl.startLine = i + 1
        decl.endLine = sig.lastSigIdx + 1
        result.add(decl)
        idxs.add(i)
    inc i
  i = 0
  while i < result.len:
    nextIdx = lines.len
    currentIndent = readIndentLevel(lines[idxs[i]])
    j = i + 1
    while j < result.len:
      nextIndent = readIndentLevel(lines[idxs[j]])
      if nextIndent <= currentIndent:
        nextIdx = idxs[j]
        break
      inc j
    result[i].endLine = nextIdx
    inc i
  i = 0
  while i < result.len:
    result[i].filePath = filePath
    inc i

proc findDeclForLine(decls: seq[NimDeclTruth], lineNo: int): NimDeclTruth {.role(parser).} =
  ## decls: parsed declaration ranges.
  ## lineNo: 1-based changed line number.
  var
    i: int
  i = 0
  while i < decls.len:
    if lineNo >= decls[i].startLine and lineNo <= decls[i].endLine:
      return decls[i]
    inc i

proc isIdentifierStart(c: char): bool {.role(parser).} =
  ## c: character to test.
  result = c in {'A'..'Z', 'a'..'z', '_'}

proc isIdentifierBody(c: char): bool {.role(parser).} =
  ## c: character to test.
  result = c in {'A'..'Z', 'a'..'z', '0'..'9', '_'}

proc readQuotedToken(s: string, startIdx: int): tuple[text: string, nextIdx: int] {.role(parser).} =
  ## s: input text.
  ## startIdx: starting index of a quote or backtick.
  var
    i: int
    quoteChar: char
  i = startIdx
  quoteChar = s[i]
  result.text.add(quoteChar)
  inc i
  while i < s.len:
    result.text.add(s[i])
    if s[i] == '\\' and i + 1 < s.len:
      inc i
      result.text.add(s[i])
    elif s[i] == quoteChar:
      inc i
      result.nextIdx = i
      return
    inc i
  result.nextIdx = i

proc normalizeSyntaxShape*(s: string): string {.role(parser).} =
  ## s: one changed source line to normalize for rename-only detection.
  var
    i: int
    token: string
    raw: tuple[text: string, nextIdx: int]
    stack: seq[string]
    lastCall: string
    preserveIdentifiers: bool
    lowered: string
  i = 0
  lastCall = ""
  while i < s.len:
    if s[i] in {' ', '\t', '\r', '\n'}:
      inc i
      continue
    if s[i] == '"' or s[i] == '\'' or s[i] == '`':
      raw = readQuotedToken(s, i)
      result.add(raw.text)
      lastCall = ""
      i = raw.nextIdx
      continue
    if isIdentifierStart(s[i]):
      token = $s[i]
      inc i
      while i < s.len and isIdentifierBody(s[i]):
        token.add(s[i])
        inc i
      lowered = token.toLowerAscii()
      preserveIdentifiers = lowered in NimKeywords
      if stack.len > 0 and stack[^1] in ["role", "risk", "tags"]:
        preserveIdentifiers = true
      if preserveIdentifiers:
        result.add(lowered)
      else:
        result.add("ID")
      lastCall = lowered
      continue
    if s[i] == '(':
      stack.add(lastCall)
      result.add("(")
      lastCall = ""
      inc i
      continue
    if s[i] == ')':
      if stack.len > 0:
        stack.setLen(stack.len - 1)
      result.add(")")
      lastCall = ""
      inc i
      continue
    result.add(s[i])
    lastCall = ""
    inc i

proc sameSyntaxShape(a: string, b: string): bool {.role(parser).} =
  ## a: removed line text.
  ## b: added line text.
  result = normalizeSyntaxShape(a.strip()) == normalizeSyntaxShape(b.strip())

proc hunkRenameOnly(h: CommitHunkInput): bool {.role(parser).} =
  ## h: one diff hunk to classify.
  var
    removed: seq[string]
    added: seq[string]
    i: int
  i = 0
  while i < h.lines.len:
    if h.lines[i].kind == '-':
      removed.add(h.lines[i].text)
    elif h.lines[i].kind == '+':
      added.add(h.lines[i].text)
    inc i
  if removed.len == 0 and added.len == 0:
    return false
  if removed.len != added.len:
    return false
  i = 0
  while i < removed.len:
    if not sameSyntaxShape(removed[i], added[i]):
      return false
    inc i
  result = true

proc fileRenameOnly(input: CommitFileInput): bool {.role(parser).} =
  ## input: perceived changed file data.
  var
    i: int
  if input.patch.renameOnlyByHeader:
    return true
  if input.patch.hunks.len == 0:
    return false
  i = 0
  while i < input.patch.hunks.len:
    if not hunkRenameOnly(input.patch.hunks[i]):
      return false
    inc i
  result = true

proc addTouchedFunction(outItems: var seq[NimFunctionTruth], seen: var HashSet[string],
    decl: NimDeclTruth) {.role(actor).} =
  ## outItems: touched function accumulator.
  ## seen: de-duplication set.
  ## decl: touched declaration truth.
  var
    item: NimFunctionTruth
    key: string
  if decl.name.len == 0:
    return
  item.filePath = decl.filePath
  item.name = decl.name
  item.role = decl.role
  item.risk = decl.risk
  item.tags = decl.tags
  key = item.filePath & "|" & item.name & "|" & item.role & "|" & item.risk & "|" & item.tags
  if seen.contains(key):
    return
  seen.incl(key)
  outItems.add(item)

proc readTouchedFunctions(input: CommitFileInput): seq[NimFunctionTruth] {.role(truthBuilder).} =
  ## input: perceived changed file data.
  var
    currentDecls: seq[NimDeclTruth]
    previousDecls: seq[NimDeclTruth]
    seen: HashSet[string]
    i: int
    j: int
    decl: NimDeclTruth
  if readFileKind(input.status.path) != cfNim:
    return @[]
  if input.currentExists:
    currentDecls = parseNimDecls(input.currentText, input.status.path)
  if input.previousExists:
    previousDecls = parseNimDecls(input.previousText,
        if input.status.oldPath.len > 0: input.status.oldPath else: input.status.path)
  if input.status.kind in [dskAdded, dskUntracked] and currentDecls.len > 0:
    for decl in currentDecls:
      addTouchedFunction(result, seen, decl)
    return result
  if input.status.kind == dskDeleted and previousDecls.len > 0:
    for decl in previousDecls:
      addTouchedFunction(result, seen, decl)
    return result
  i = 0
  while i < input.patch.hunks.len:
    j = 0
    while j < input.patch.hunks[i].lines.len:
      if input.patch.hunks[i].lines[j].kind == '+' and currentDecls.len > 0:
        decl = findDeclForLine(currentDecls, input.patch.hunks[i].lines[j].newLine)
        addTouchedFunction(result, seen, decl)
      inc j
    inc i
  if result.len > 0:
    return result
  i = 0
  while i < input.patch.hunks.len:
    j = 0
    while j < input.patch.hunks[i].lines.len:
      if input.patch.hunks[i].lines[j].kind == '-' and previousDecls.len > 0:
        decl = findDeclForLine(previousDecls, input.patch.hunks[i].lines[j].oldLine)
        addTouchedFunction(result, seen, decl)
      inc j
    inc i

proc buildCommitMessageTruthState*(repoPath: string): CommitMessageTruthState {.role(truthBuilder).} =
  ## repoPath: repository root path.
  var
    inputs: seq[CommitFileInput]
    i: int
    kind: CommitFileKind
    touched: seq[NimFunctionTruth]
  result.repoPath = normalizePathValue(repoPath)
  result.progressHint = readCommitMessage(repoPath, "").strip()
  if result.repoPath.len == 0 or not dirExists(result.repoPath):
    return
  inputs = buildCommitInputs(result.repoPath)
  i = 0
  while i < inputs.len:
    kind = readFileKind(inputs[i].status.path)
    case kind
    of cfNim:
      inc result.nimFiles
    of cfDocs:
      inc result.docsFiles
    of cfConfig:
      inc result.configFiles
    of cfOther:
      inc result.otherFiles
    if fileRenameOnly(inputs[i]):
      inc result.renameOnlyFiles
    touched = readTouchedFunctions(inputs[i])
    for item in touched:
      result.touchedFunctions.add(item)
    inc i
  result.touchedFunctions.sort(proc(a, b: NimFunctionTruth): int =
    result = system.cmp(a.filePath & ":" & a.name, b.filePath & ":" & b.name)
  )
  result.touchedFunctionCount = result.touchedFunctions.len

proc renderCommitTruthLines*(t: CommitMessageTruthState): seq[string] {.role(actor).} =
  ## t: commit message truth state to render for CLI display.
  result.add("Change truth: " & readCommitKeyword(t))
  result.add("Nim files: " & $t.nimFiles)
  result.add("Docs files: " & $t.docsFiles)
  result.add("Config files: " & $t.configFiles)
  result.add("Other files: " & $t.otherFiles)
  result.add("Rename-only files: " & $t.renameOnlyFiles)
  result.add("Touched functions: " & $t.touchedFunctionCount)
  if t.touchedFunctions.len > 0:
    for item in t.touchedFunctions:
      result.add("  - " & item.filePath & "::" & item.name &
          " [role=" & item.role & ", risk=" & item.risk & ", tags=" & item.tags & "]")
  if t.progressHint.len > 0:
    result.add("Progress hint: " & t.progressHint)

proc buildSummaryParts(t: CommitMessageTruthState): seq[string] {.role(truthBuilder).} =
  ## t: commit message truth state.
  if t.nimFiles > 0:
    result.add("nim " & $t.nimFiles)
  if t.docsFiles > 0:
    result.add("docs " & $t.docsFiles)
  if t.configFiles > 0:
    result.add("config " & $t.configFiles)
  if t.otherFiles > 0:
    result.add("other " & $t.otherFiles)
  if t.renameOnlyFiles > 0:
    result.add("rename-only " & $t.renameOnlyFiles)
  if t.touchedFunctionCount > 0:
    result.add("functions " & $t.touchedFunctionCount)

proc buildCommitHeadline(keyword: string, defaultMsg: string): string {.role(actor).} =
  ## keyword: diff-derived classifier keyword.
  ## defaultMsg: fallback summary keyword.
  let label = (if keyword.strip().len > 0: keyword.strip() else: defaultMsg.strip())
  if label.startsWith("-"):
    return label
  result = "- " & label

proc buildCommitMessageText(t: CommitMessageTruthState, defaultMsg: string): string {.role(actor).} =
  ## t: commit message truth state.
  ## defaultMsg: fallback commit message.
  let keyword = readCommitKeyword(t)
  let summary = buildSummaryParts(t)
  if summary.len == 0:
    return buildCommitHeadline("", defaultMsg)
  result = buildCommitHeadline(keyword, defaultMsg)

proc buildAutomaticCommitMessage*(repoPath: string,
    defaultMsg: string = "Auto update"): string {.role(metaOrchestrator).} =
  ## repoPath: repository root path.
  ## defaultMsg: fallback commit message.
  let t = buildCommitMessageTruthState(repoPath)
  result = buildCommitMessageText(t, defaultMsg)

proc buildAutomaticCommitMessage*(t: CommitMessageTruthState,
    defaultMsg: string = "Auto update"): string {.role(actor).} =
  ## t: precomputed commit message truth state.
  ## defaultMsg: fallback commit message.
  result = buildCommitMessageText(t, defaultMsg)
