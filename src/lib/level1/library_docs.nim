# ==================================================
# | Valkyrie Tooling Library Docs                  |
# |------------------------------------------------|
# | Autonomous library documentation + scaffolds.  |
# ==================================================

import std/[algorithm, json, os, strutils, times]

type
  ApiSymbol* = object
    kind*: string
    name*: string
    signature*: string
    doc*: string
    exported*: bool
    line*: int
  ModuleDoc* = object
    path*: string
    summary*: string
    imports*: seq[string]
    symbols*: seq[ApiSymbol]
  LibraryDocsReport* = object
    ok*: bool
    lines*: seq[string]
    markdownPath*: string
    jsonPath*: string
    moduleCount*: int
    symbolCount*: int
    missingDocs*: int
  DocsInitReport* = object
    ok*: bool
    lines*: seq[string]
    createdFiles*: seq[string]
    skippedFiles*: seq[string]

const
  DefaultDocsName = "library_api.md"

proc detectMetadataDir(repoPath: string): string =
  ## repoPath: repository root path.
  var
    valkPath: string
    valkyriePath: string
  valkPath = joinPath(repoPath, "valk")
  valkyriePath = joinPath(repoPath, "valkyrie")
  if dirExists(valkPath):
    result = valkPath
    return
  if dirExists(valkyriePath):
    result = valkyriePath
    return
  result = valkPath

proc trimComment(s: string): string =
  ## s: line to normalize from comment markers.
  var
    t: string
  t = s.strip()
  if t.startsWith("#"):
    t = t.strip(chars = {'#', ' ', '\t', '|', '-', '='})
  result = t.strip()

proc readModuleSummary(ls: seq[string]): string =
  ## ls: file lines.
  var
    i: int
    t: string
  i = 0
  while i < ls.len and i < 40:
    t = ls[i].strip()
    if t.len == 0:
      inc i
      continue
    if t.startsWith("#"):
      t = trimComment(t)
      if t.len > 0:
        result = t
        return
      inc i
      continue
    break
  result = "No module summary found."

proc startsWithWordPrefix(s: string, w: string): bool =
  ## s: normalized line.
  ## w: word prefix.
  if not s.startsWith(w):
    result = false
    return
  if s.len == w.len:
    result = true
    return
  result = s[w.len] in {' ', '\t'}

proc readDeclKind(s: string): string =
  ## s: normalized source line.
  if startsWithWordPrefix(s, "proc"):
    result = "proc"
    return
  if startsWithWordPrefix(s, "func"):
    result = "func"
    return
  if startsWithWordPrefix(s, "template"):
    result = "template"
    return
  if startsWithWordPrefix(s, "macro"):
    result = "macro"
    return
  if startsWithWordPrefix(s, "iterator"):
    result = "iterator"
    return
  result = ""

proc parseDeclName(s: string, k: string): tuple[name: string, exported: bool] =
  ## s: normalized declaration line.
  ## k: declaration kind.
  var
    t: string
    i: int
    j: int
    c: char
    n: string
  t = s[k.len .. ^1].strip()
  if t.len == 0:
    result = ("", false)
    return
  if t[0] == '`':
    i = 1
    while i < t.len and t[i] != '`':
      n.add(t[i])
      inc i
    if i < t.len:
      inc i
  else:
    i = 0
    while i < t.len:
      c = t[i]
      if c in {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
        n.add(c)
        inc i
      else:
        break
  if n.len == 0:
    result = ("", false)
    return
  j = i
  while j < t.len and t[j] in {' ', '\t'}:
    inc j
  if j < t.len and t[j] == '*':
    result = (n, true)
  else:
    result = (n, false)

proc readDocBelow(ls: seq[string], i: int): string =
  ## ls: file lines.
  ## i: declaration line index.
  var
    t: seq[string]
    j: int
    s: string
  j = i + 1
  while j < ls.len:
    s = ls[j].strip()
    if s.startsWith("##"):
      t.add(s[2 .. ^1].strip())
      inc j
      continue
    break
  result = t.join(" ")

proc readDocAbove(ls: seq[string], i: int): string =
  ## ls: file lines.
  ## i: declaration line index.
  var
    t: seq[string]
    j: int
    s: string
  j = i - 1
  while j >= 0:
    s = ls[j].strip()
    if s.startsWith("##"):
      t.add(s[2 .. ^1].strip())
      dec j
      continue
    if s.len == 0:
      dec j
      continue
    break
  t.reverse()
  result = t.join(" ")

proc parseImports(ls: seq[string]): seq[string] =
  ## ls: file lines.
  var
    t: seq[string]
    i: int
    s: string
    p: string
    q: int
  i = 0
  while i < ls.len:
    s = ls[i].strip()
    if startsWithWordPrefix(s, "import"):
      p = s["import".len .. ^1].strip()
      if p.len > 0:
        t.add(p)
    elif startsWithWordPrefix(s, "from"):
      p = s["from".len .. ^1].strip()
      q = p.find(" import ")
      if q >= 0:
        p = p[0 .. q - 1].strip()
      if p.len > 0:
        t.add(p)
    inc i
  result = t

proc parseModuleDoc(p: string, repoRoot: string): ModuleDoc =
  ## p: module path.
  ## repoRoot: repository root path.
  var
    ls: seq[string]
    i: int
    s: string
    kind: string
    nameOut: tuple[name: string, exported: bool]
    sym: ApiSymbol
    doc: string
  ls = readFile(p).splitLines()
  result.path = relativePath(p, repoRoot).replace('\\', '/')
  result.summary = readModuleSummary(ls)
  result.imports = parseImports(ls)
  i = 0
  while i < ls.len:
    s = ls[i].strip()
    kind = readDeclKind(s)
    if kind.len == 0:
      inc i
      continue
    nameOut = parseDeclName(s, kind)
    if nameOut.name.len == 0:
      inc i
      continue
    sym.kind = kind
    sym.name = nameOut.name
    sym.exported = nameOut.exported
    sym.signature = s
    sym.line = i + 1
    doc = readDocBelow(ls, i)
    if doc.len == 0:
      doc = readDocAbove(ls, i)
    sym.doc = doc
    result.symbols.add(sym)
    inc i

proc collectNimFiles(srcDir: string): seq[string] =
  ## srcDir: source directory to scan.
  var
    t: seq[string]
  if not dirExists(srcDir):
    result = @[]
    return
  for p in walkDirRec(srcDir):
    if p.toLowerAscii().endsWith(".nim"):
      t.add(p)
  t.sort(system.cmp[string])
  result = t

proc defaultSrcPath(repoPath: string, srcPath: string): string =
  ## repoPath: repository root path.
  ## srcPath: optional source path override.
  var
    t: string
  if srcPath.strip().len > 0:
    t = srcPath.strip()
    if t.isAbsolute():
      result = t
    else:
      result = joinPath(repoPath, t)
  else:
    result = joinPath(repoPath, "src")

proc defaultDocsPath(repoPath: string, docsOut: string): string =
  ## repoPath: repository root path.
  ## docsOut: optional docs path override.
  var
    t: string
    m: string
  if docsOut.strip().len > 0:
    t = docsOut.strip()
    if t.isAbsolute():
      result = t
    else:
      result = joinPath(repoPath, t)
  else:
    m = detectMetadataDir(repoPath)
    result = joinPath(m, "docs", DefaultDocsName)

proc deriveJsonPath(markdownPath: string): string =
  ## markdownPath: markdown output path.
  var
    t: tuple[dir, name, ext: string]
  t = splitFile(markdownPath)
  result = joinPath(t.dir, t.name & ".json")

proc countSymbolStats(ms: seq[ModuleDoc]): tuple[total: int, missingDocs: int] =
  ## ms: parsed module docs.
  var
    i: int
    j: int
    s: ApiSymbol
    total: int
    missing: int
  i = 0
  while i < ms.len:
    j = 0
    while j < ms[i].symbols.len:
      s = ms[i].symbols[j]
      if s.exported:
        inc total
        if s.doc.strip().len == 0:
          inc missing
      inc j
    inc i
  result = (total, missing)

proc toJsonSymbol(s: ApiSymbol): JsonNode =
  ## s: API symbol metadata.
  result = %*{
    "kind": s.kind,
    "name": s.name,
    "signature": s.signature,
    "doc": s.doc,
    "exported": s.exported,
    "line": s.line
  }

proc toJsonModule(m: ModuleDoc): JsonNode =
  ## m: parsed module metadata.
  var
    tSymbols: JsonNode
    i: int
  tSymbols = newJArray()
  i = 0
  while i < m.symbols.len:
    tSymbols.add(toJsonSymbol(m.symbols[i]))
    inc i
  result = %*{
    "path": m.path,
    "summary": m.summary,
    "imports": m.imports,
    "symbols": tSymbols
  }

proc buildJsonBridge(repoPath: string, srcDir: string, ms: seq[ModuleDoc]): JsonNode =
  ## repoPath: repository root path.
  ## srcDir: source directory used for scan.
  ## ms: parsed modules.
  var
    tModules: JsonNode
    i: int
    s: tuple[total: int, missingDocs: int]
  tModules = newJArray()
  i = 0
  while i < ms.len:
    tModules.add(toJsonModule(ms[i]))
    inc i
  s = countSymbolStats(ms)
  result = %*{
    "generatedAt": now().format("yyyy-MM-dd HH:mm:ss"),
    "repoRoot": repoPath.replace('\\', '/'),
    "sourceRoot": srcDir.replace('\\', '/'),
    "moduleCount": ms.len,
    "exportedSymbolCount": s.total,
    "missingExportedDocs": s.missingDocs,
    "modules": tModules
  }

proc appendModuleIndexLines(ls: var seq[string], ms: seq[ModuleDoc]) =
  ## ls: markdown line list.
  ## ms: parsed modules.
  var
    i: int
    j: int
    m: ModuleDoc
    exports: int
  ls.add("## Module Index")
  ls.add("")
  ls.add("| Module | Summary | Exports |")
  ls.add("|---|---|---|")
  i = 0
  while i < ms.len:
    m = ms[i]
    exports = 0
    j = 0
    while j < m.symbols.len:
      if m.symbols[j].exported:
        inc exports
      inc j
    ls.add("| `" & m.path & "` | " & m.summary.replace("|", "\\|") & " | " & $exports & " |")
    inc i
  ls.add("")

proc appendModuleDetailLines(ls: var seq[string], ms: seq[ModuleDoc]) =
  ## ls: markdown line list.
  ## ms: parsed modules.
  var
    i: int
    j: int
    m: ModuleDoc
    s: ApiSymbol
  ls.add("## API Details")
  ls.add("")
  i = 0
  while i < ms.len:
    m = ms[i]
    ls.add("### " & m.path)
    ls.add("")
    ls.add("- Summary: " & m.summary)
    if m.imports.len > 0:
      ls.add("- Imports: `" & m.imports.join("`, `") & "`")
    else:
      ls.add("- Imports: (none)")
    if m.symbols.len == 0:
      ls.add("- Symbols: (none)")
      ls.add("")
      inc i
      continue
    ls.add("- Symbols:")
    j = 0
    while j < m.symbols.len:
      s = m.symbols[j]
      ls.add("  - `" & s.signature & "`")
      ls.add("    - Kind: " & s.kind)
      ls.add("    - Exported: " & (if s.exported: "yes" else: "no"))
      ls.add("    - Line: " & $s.line)
      if s.doc.len > 0:
        ls.add("    - Doc: " & s.doc)
      else:
        ls.add("    - Doc: (missing)")
      inc j
    ls.add("")
    inc i

proc buildMarkdownText(repoPath: string, srcDir: string, ms: seq[ModuleDoc]): string =
  ## repoPath: repository root path.
  ## srcDir: source directory used for scan.
  ## ms: parsed module docs.
  var
    ls: seq[string]
    repoName: string
    tStats: tuple[total: int, missingDocs: int]
    outName: string
  repoName = splitPath(repoPath).tail
  if repoName.len == 0:
    repoName = repoPath
  outName = "library_api.json"
  tStats = countSymbolStats(ms)
  ls = @[
    "# Library API Map - " & repoName,
    "",
    "Generated: " & now().format("yyyy-MM-dd HH:mm:ss"),
    "Repo root: `" & repoPath.replace('\\', '/') & "`",
    "Source root: `" & srcDir.replace('\\', '/') & "`",
    "",
    "## Intent",
    "",
    "This file is generated by `val docs` and optimized for both maintainers and AI agents.",
    "Use it as the first-stop map before touching code.",
    "",
    "## Agent Workflow",
    "",
    "1. Update `valk/pipeline.json` to reflect planned work and dependencies.",
    "2. Run `val show --pipeline valk/pipeline.json` in one terminal.",
    "3. Apply code changes, then refresh docs with `val docs`.",
    "4. Review `" & outName & "` for machine-consumable structure.",
    ""
  ]
  appendModuleIndexLines(ls, ms)
  appendModuleDetailLines(ls, ms)
  ls.add("## Coverage")
  ls.add("")
  ls.add("- Modules scanned: " & $ms.len)
  ls.add("- Exported symbols: " & $tStats.total)
  ls.add("- Missing exported docs: " & $tStats.missingDocs)
  ls.add("")
  result = ls.join("\n")

proc generateLibraryDocs*(repoPath: string, srcPath: string, docsOut: string): LibraryDocsReport =
  ## repoPath: repository root path.
  ## srcPath: optional source path override.
  ## docsOut: optional markdown output path override.
  var
    tRepo: string
    tSrc: string
    tMd: string
    tJson: string
    tFiles: seq[string]
    tModules: seq[ModuleDoc]
    i: int
    tMdText: string
    tJsonNode: JsonNode
    tStats: tuple[total: int, missingDocs: int]
  tRepo = absolutePath(repoPath)
  tSrc = defaultSrcPath(tRepo, srcPath)
  tMd = defaultDocsPath(tRepo, docsOut)
  tJson = deriveJsonPath(tMd)
  result.ok = false
  result.markdownPath = tMd
  result.jsonPath = tJson
  if not dirExists(tRepo):
    result.lines = @["Repo path does not exist: " & tRepo]
    return
  if not dirExists(tSrc):
    result.lines = @["Source path does not exist: " & tSrc]
    return
  tFiles = collectNimFiles(tSrc)
  if tFiles.len == 0:
    result.lines = @["No .nim files found under: " & tSrc]
    return
  i = 0
  while i < tFiles.len:
    tModules.add(parseModuleDoc(tFiles[i], tRepo))
    inc i
  if parentDir(tMd).len > 0:
    createDir(parentDir(tMd))
  if parentDir(tJson).len > 0:
    createDir(parentDir(tJson))
  tMdText = buildMarkdownText(tRepo, tSrc, tModules)
  writeFile(tMd, tMdText)
  tJsonNode = buildJsonBridge(tRepo, tSrc, tModules)
  writeFile(tJson, tJsonNode.pretty())
  tStats = countSymbolStats(tModules)
  result.ok = true
  result.moduleCount = tModules.len
  result.symbolCount = tStats.total
  result.missingDocs = tStats.missingDocs
  result.lines = @[
    "Docs generated.",
    "Markdown: " & tMd,
    "JSON bridge: " & tJson,
    "Modules: " & $result.moduleCount,
    "Exported symbols: " & $result.symbolCount,
    "Missing exported docs: " & $result.missingDocs
  ]

proc buildInstructionsetText(): string =
  var
    ls: seq[string]
  ls = @[
    "# Valkyrie Docs Instructionset",
    "",
    "Use this workflow whenever an agent modifies library code:",
    "",
    "1. Update `valk/pipeline.json` with current steps and statuses.",
    "2. Keep dependencies explicit in the `children` tree.",
    "3. Set status values to one of: `todo`, `active`, `done`, `blocked`, `failed`.",
    "4. Run `val show` in a separate terminal while editing.",
    "5. After edits, run `val docs` to regenerate API map + JSON bridge.",
    "",
    "Commands:",
    "",
    "- `val docs --repo .`",
    "- `val docs --repo . --src ./src --docs-out ./valk/docs/library_api.md`",
    "- `val show --pipeline ./valk/pipeline.json --interval-ms 700`",
    "- `val show --pipeline ./valk/pipeline.json --once`",
    "",
    "JSON tree requirements for `val show`:",
    "",
    "- Root object may define `name`, `description`, and `root`.",
    "- Each node uses: `id`, `label`, `status`, `details`, `children`.",
    "- `children` is an array of nested nodes.",
    "",
    "Maintenance rule:",
    "",
    "- If pipeline shape changed, update this instructionset and regenerate docs."
  ]
  result = ls.join("\n")

proc buildPipelineExampleText(): string =
  var
    t: JsonNode
  t = %*{
    "name": "Library Maintenance Pipeline",
    "description": "Track AI + human workflow for docs-aware development.",
    "intervalMs": 700,
    "root": {
      "id": "plan",
      "label": "Plan change scope",
      "status": "done",
      "details": "Identify touched modules and expected API changes.",
      "children": [
        {
          "id": "edit",
          "label": "Edit source modules",
          "status": "active",
          "details": "Implement and keep doc comments updated.",
          "children": [
            {
              "id": "test",
              "label": "Run tests",
              "status": "todo",
              "details": "Execute smoke/unit tests for touched areas.",
              "children": []
            },
            {
              "id": "docs",
              "label": "Generate library docs",
              "status": "todo",
              "details": "Run val docs and review markdown + bridge JSON.",
              "children": []
            }
          ]
        }
      ]
    }
  }
  result = t.pretty()

proc buildIllwillExampleText(): string =
  var
    ls: seq[string]
  ls = @[
    "# =========================================",
    "# | Valkyrie Illwill Pipeline Demo        |",
    "# |---------------------------------------|",
    "# | Compile manually:                     |",
    "# | nim c -r valk/illwill_pipeline_example.nim |",
    "# =========================================",
    "",
    "import std/[os, strutils]",
    "import illwill",
    "",
    "proc drawFrame(p: string, frame: int) =",
    "  var",
    "    t0: TerminalBuffer",
    "    ls: seq[string]",
    "    i: int",
    "  t0 = newTerminalBuffer(120, 40)",
    "  t0.clear()",
    "  ls = readFile(p).splitLines()",
    "  t0.write(1, 1, \"Illwill Pipeline Demo\")",
    "  t0.write(1, 2, \"Frame: \" & $frame & \" | File: \" & p)",
    "  i = 0",
    "  while i < ls.len and i < 34:",
    "    t0.write(1, 4 + i, ls[i])",
    "    inc i",
    "  display(t0)",
    "",
    "proc runDemo(p: string) =",
    "  var",
    "    i: int",
    "  i = 0",
    "  while true:",
    "    drawFrame(p, i)",
    "    sleep(500)",
    "    inc i",
    "",
    "when isMainModule:",
    "  let p = if paramCount() > 0: paramStr(1) else: \"valk/pipeline.json\"",
    "  initScreen()",
    "  defer: deinitScreen()",
    "  setCursorVisibility(false)",
    "  runDemo(p)"
  ]
  result = ls.join("\n")

proc writeScaffoldFile(path: string, content: string, overwrite: bool,
                       created: var seq[string], skipped: var seq[string]) =
  ## path: target scaffold file path.
  ## content: scaffold content to write.
  ## overwrite: enable overwrite for existing files.
  ## created: created file list.
  ## skipped: skipped file list.
  if fileExists(path) and not overwrite:
    skipped.add(path)
    return
  if parentDir(path).len > 0:
    createDir(parentDir(path))
  writeFile(path, content)
  created.add(path)

proc initDocsScaffold*(repoPath: string, overwrite: bool): DocsInitReport =
  ## repoPath: repository root path.
  ## overwrite: overwrite existing scaffold files.
  var
    tRepo: string
    tPipeline: string
    tPipelineAlt: string
    tInstruction: string
    tIllwill: string
    tMeta: string
    created: seq[string]
    skipped: seq[string]
  tRepo = absolutePath(repoPath)
  result.ok = false
  if not dirExists(tRepo):
    result.lines = @["Repo path does not exist: " & tRepo]
    return
  tMeta = detectMetadataDir(tRepo)
  tPipeline = joinPath(tMeta, "pipeline.json")
  tPipelineAlt = joinPath(tMeta, "pipeline.library.json")
  tInstruction = joinPath(tMeta, "docs_instructionset.md")
  tIllwill = joinPath(tMeta, "illwill_pipeline_example.nim")
  writeScaffoldFile(tPipeline, buildPipelineExampleText(), overwrite, created, skipped)
  writeScaffoldFile(tPipelineAlt, buildPipelineExampleText(), overwrite, created, skipped)
  writeScaffoldFile(tInstruction, buildInstructionsetText(), overwrite, created, skipped)
  writeScaffoldFile(tIllwill, buildIllwillExampleText(), overwrite, created, skipped)
  result.ok = true
  result.createdFiles = created
  result.skippedFiles = skipped
  result.lines = @["Docs scaffold completed."]
  if created.len > 0:
    result.lines.add("Created: " & created.join(", "))
  if skipped.len > 0:
    result.lines.add("Skipped existing: " & skipped.join(", "))
