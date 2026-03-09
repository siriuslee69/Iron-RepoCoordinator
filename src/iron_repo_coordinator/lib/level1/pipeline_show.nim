# ==================================================
# | iron Tooling Pipeline Viewer               |
# |------------------------------------------------|
# | Parse pipeline JSON trees and render ASCII UI. |
# ==================================================

import std/[json, os, strutils]

type
  PipelineNode* = object
    id*: string
    label*: string
    status*: string
    details*: string
    children*: seq[PipelineNode]
  PipelineSpec* = object
    name*: string
    description*: string
    intervalMs*: int
    root*: PipelineNode
  PipelineParseResult* = object
    ok*: bool
    spec*: PipelineSpec
    error*: string
  PipelineShowReport* = object
    ok*: bool
    lines*: seq[string]
    frameCount*: int

const
  DefaultIntervalMs = 700

proc normalizeStatus(s: string): string =
  ## s: input node status value.
  var
    t: string
  t = s.strip().toLowerAscii()
  if t in ["done", "ok", "complete", "completed", "success"]:
    result = "done"
    return
  if t in ["active", "running", "run", "in_progress", "working"]:
    result = "active"
    return
  if t in ["blocked", "wait", "waiting"]:
    result = "blocked"
    return
  if t in ["failed", "fail", "error"]:
    result = "failed"
    return
  result = "todo"

proc readJsonString(n: JsonNode, k: string, d: string): string =
  ## n: object node.
  ## k: key to read.
  ## d: default fallback.
  if n.kind == JObject and n.hasKey(k) and n[k].kind in {JString, JInt, JFloat, JBool}:
    result = $n[k]
    result = result.strip(chars = {'"', ' '})
  else:
    result = d

proc readJsonInt(n: JsonNode, k: string, d: int): int =
  ## n: object node.
  ## k: key to read.
  ## d: default fallback.
  if n.kind == JObject and n.hasKey(k):
    if n[k].kind == JInt:
      result = n[k].getInt()
      return
    if n[k].kind == JString:
      try:
        result = parseInt(n[k].getStr().strip())
        return
      except ValueError:
        discard
  result = d

proc parseNode(n: JsonNode, fallbackId: string): PipelineNode =
  ## n: JSON node object.
  ## fallbackId: generated fallback id.
  var
    tChildren: JsonNode
    i: int
    idValue: string
  idValue = readJsonString(n, "id", fallbackId)
  result.id = idValue
  result.label = readJsonString(n, "label", idValue)
  if result.label.len == 0:
    result.label = idValue
  result.status = normalizeStatus(readJsonString(n, "status", "todo"))
  result.details = readJsonString(n, "details", "")
  if n.kind == JObject and n.hasKey("children") and n["children"].kind == JArray:
    tChildren = n["children"]
    i = 0
    while i < tChildren.len:
      result.children.add(parseNode(tChildren[i], idValue & "_" & $i))
      inc i

proc parsePipelineJson(n: JsonNode): PipelineParseResult =
  ## n: top-level pipeline JSON object.
  var
    tRoot: JsonNode
  if n.kind != JObject:
    result.ok = false
    result.error = "pipeline JSON root must be an object"
    return
  result.spec.name = readJsonString(n, "name", "Pipeline")
  result.spec.description = readJsonString(n, "description", "")
  result.spec.intervalMs = readJsonInt(n, "intervalMs", DefaultIntervalMs)
  if result.spec.intervalMs <= 0:
    result.spec.intervalMs = DefaultIntervalMs
  if n.hasKey("root"):
    tRoot = n["root"]
  else:
    tRoot = n
  result.spec.root = parseNode(tRoot, "root")
  result.ok = true

proc readPipelineSpec*(pipelinePath: string): PipelineParseResult =
  ## pipelinePath: JSON pipeline file path.
  var
    n: JsonNode
  if not fileExists(pipelinePath):
    result.ok = false
    result.error = "pipeline file does not exist: " & pipelinePath
    return
  try:
    n = parseFile(pipelinePath)
  except CatchableError:
    result.ok = false
    result.error = "failed to parse pipeline JSON: " & getCurrentExceptionMsg()
    return
  result = parsePipelineJson(n)

proc statusBadge(s: string, frame: int): string =
  ## s: normalized status value.
  ## frame: current frame index.
  const spinner = @["|", "/", "-", "\\"]
  if s == "done":
    result = "DONE"
    return
  if s == "active":
    result = "RUN " & spinner[frame mod spinner.len]
    return
  if s == "blocked":
    result = "BLOCK"
    return
  if s == "failed":
    result = "FAIL"
    return
  result = "TODO"

proc nodeLine(n: PipelineNode, frame: int): string =
  ## n: pipeline node.
  ## frame: current frame index.
  result = "[" & statusBadge(n.status, frame) & "] [" & n.id & "] " & n.label

proc appendNodeLines(ls: var seq[string], n: PipelineNode, prefix: string, last: bool,
                     isRoot: bool, frame: int) =
  ## ls: output lines.
  ## n: pipeline node.
  ## prefix: tree prefix.
  ## last: whether node is the final sibling.
  ## isRoot: marks root rendering.
  ## frame: current frame index.
  var
    connector: string
    childPrefix: string
    i: int
  if isRoot:
    connector = "o-> "
    childPrefix = "    "
  else:
    if last:
      connector = "`-> "
      childPrefix = prefix & "    "
    else:
      connector = "|-> "
      childPrefix = prefix & "|   "
  ls.add(prefix & connector & nodeLine(n, frame))
  if n.details.len > 0:
    ls.add(childPrefix & "(" & n.details & ")")
  i = 0
  while i < n.children.len:
    appendNodeLines(ls, n.children[i], childPrefix, i == n.children.high, false, frame)
    inc i

proc renderPipelineFrame*(s: PipelineSpec, frame: int, pipelinePath: string): string =
  ## s: parsed pipeline spec.
  ## frame: current frame index.
  ## pipelinePath: source pipeline file path.
  var
    ls: seq[string]
  ls = @[
    "iron Pipeline Viewer",
    "",
    "Pipeline: " & s.name,
    "File: " & pipelinePath.replace('\\', '/'),
    "Frame: " & $frame & " | Ctrl+C to stop",
    "Legend: DONE | TODO | RUN | BLOCK | FAIL",
    ""
  ]
  if s.description.len > 0:
    ls.add("Description: " & s.description)
    ls.add("")
  appendNodeLines(ls, s.root, "", true, true, frame)
  result = ls.join("\n")

proc defaultPipelineCandidates*(repoPath: string): seq[string] =
  ## repoPath: repository root path.
  var
    tRepo: string
  tRepo = absolutePath(repoPath)
  result = @[
    joinPath(tRepo, ".iron", "pipeline.json"),
    joinPath(tRepo, ".iron", "pipeline.library.json"),
    joinPath(tRepo, "iron", "pipeline.json"),
    joinPath(tRepo, "iron", "pipeline.library.json")
  ]

proc defaultPipelinePath*(repoPath: string): string =
  ## repoPath: repository root path.
  var
    cands: seq[string]
    i: int
  cands = defaultPipelineCandidates(repoPath)
  i = 0
  while i < cands.len:
    if fileExists(cands[i]):
      result = cands[i]
      return
    inc i
  result = cands[0]

proc resolvePipelinePath*(repoPath: string, pipelinePath: string): string =
  ## repoPath: repository root path.
  ## pipelinePath: command option override path.
  var
    t: string
  t = pipelinePath.strip()
  if t.len == 0:
    result = defaultPipelinePath(repoPath)
    return
  if t.isAbsolute():
    result = t
    return
  result = joinPath(absolutePath(repoPath), t)

proc clearTerminal() =
  stdout.write("\27[2J\27[H")
  flushFile(stdout)

proc showPipeline*(repoPath: string, pipelinePath: string, once: bool, loops: int,
                   intervalMs: int): PipelineShowReport =
  ## repoPath: repository root path.
  ## pipelinePath: optional path override.
  ## once: render one frame only.
  ## loops: max frame count (0 means unbounded).
  ## intervalMs: frame sleep interval in milliseconds.
  var
    p: string
    r: PipelineParseResult
    i: int
    outText: string
    tInterval: int
  p = resolvePipelinePath(repoPath, pipelinePath)
  if not fileExists(p):
    result.ok = false
    result.lines = @["Pipeline file not found: " & p]
    result.frameCount = 0
    return
  tInterval = intervalMs
  if tInterval <= 0:
    tInterval = DefaultIntervalMs
  i = 0
  while true:
    r = readPipelineSpec(p)
    if r.ok:
      if intervalMs <= 0 and r.spec.intervalMs > 0:
        tInterval = r.spec.intervalMs
      outText = renderPipelineFrame(r.spec, i, p)
    else:
      outText = "iron Pipeline Viewer\n\nError: " & r.error & "\nFile: " &
        p.replace('\\', '/')
    clearTerminal()
    echo outText
    inc i
    if once:
      break
    if loops > 0 and i >= loops:
      break
    sleep(tInterval)
  result.ok = true
  result.frameCount = i
  result.lines = @[
    "Pipeline show completed.",
    "Pipeline: " & p,
    "Frames: " & $i
  ]
