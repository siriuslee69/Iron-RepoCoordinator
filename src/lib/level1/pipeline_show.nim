# ==================================================
# | iron Tooling Pipeline Viewer               |
# |------------------------------------------------|
# | Parse pipeline TOML trees and render ASCII UI. |
# ==================================================

import std/[json, os, strutils]
include ../level0/metaPragmas

type
  PipelineNodeInput = object
    id: string
    label: string
    status: string
    details: string
    parent: string
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

proc normalizeStatus(s: string): string {.role(parser).} =
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

proc readJsonString(n: JsonNode, k: string, d: string): string {.role(parser).} =
  ## n: object node.
  ## k: key to read.
  ## d: default fallback.
  if n.kind == JObject and n.hasKey(k) and n[k].kind in {JString, JInt, JFloat, JBool}:
    result = $n[k]
    result = result.strip(chars = {'"', ' '})
  else:
    result = d

proc readJsonInt(n: JsonNode, k: string, d: int): int {.role(parser).} =
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

proc parseNode(n: JsonNode, fallbackId: string): PipelineNode {.role(parser).} =
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

proc parsePipelineJson(n: JsonNode): PipelineParseResult {.role(parser).} =
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

proc trimTomlQuotes(s: string): string {.role(parser).} =
  ## s: raw TOML value string.
  var
    t: string
  t = s.strip()
  if t.len >= 2 and t[0] == '"' and t[^1] == '"':
    t = t[1 .. ^2]
    t = t.replace("\\\"", "\"")
  result = t

proc splitTomlKeyValue(s: string): tuple[ok: bool, key: string, value: string] {.role(parser).} =
  ## s: one TOML line with a key/value pair.
  var
    idx: int
  idx = s.find('=')
  if idx <= 0:
    return (false, "", "")
  result.ok = true
  result.key = s[0 .. idx - 1].strip()
  result.value = s[idx + 1 .. ^1].strip()

proc parseTomlInt(s: string, d: int): int {.role(parser).} =
  ## s: raw TOML integer value.
  ## d: fallback value.
  try:
    result = parseInt(trimTomlQuotes(s))
  except ValueError:
    result = d

proc readNodeInput(inputs: seq[PipelineNodeInput], nodeId: string): PipelineNodeInput {.role(parser).} =
  ## inputs: parsed flat node inputs.
  ## nodeId: id to look up.
  var
    i: int
  i = 0
  while i < inputs.len:
    if inputs[i].id == nodeId:
      return inputs[i]
    inc i

proc buildNodeTree(inputs: seq[PipelineNodeInput], nodeId: string,
                   trail: seq[string] = @[]): PipelineNode {.role(truthBuilder).} =
  ## inputs: parsed flat node inputs.
  ## nodeId: node id to materialize into a tree.
  ## trail: recursion trail used to stop cycles.
  var
    input: PipelineNodeInput
    nextTrail: seq[string]
    i: int
    child: PipelineNode
  input = readNodeInput(inputs, nodeId)
  if input.id.len == 0:
    return
  result.id = input.id
  result.label = if input.label.len > 0: input.label else: input.id
  result.status = normalizeStatus(input.status)
  result.details = input.details
  if trail.contains(input.id):
    return
  nextTrail = trail
  nextTrail.add(input.id)
  i = 0
  while i < inputs.len:
    if inputs[i].parent == input.id and inputs[i].id != input.id:
      child = buildNodeTree(inputs, inputs[i].id, nextTrail)
      if child.id.len > 0:
        result.children.add(child)
    inc i

proc parsePipelineToml(text: string): PipelineParseResult {.role(parser).} =
  ## text: TOML pipeline file contents.
  var
    nodeInputs: seq[PipelineNodeInput]
    current: PipelineNodeInput
    inNode: bool
    rootId: string
    line: string
    kv: tuple[ok: bool, key: string, value: string]
    i: int
  result.spec.name = "Pipeline"
  result.spec.intervalMs = DefaultIntervalMs
  for rawLine in text.splitLines():
    line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line in ["[[nodes]]", "[[node]]"]:
      if inNode and current.id.len > 0:
        nodeInputs.add(current)
      current = PipelineNodeInput()
      inNode = true
      continue
    if line.startsWith("[") and line.endsWith("]"):
      continue
    kv = splitTomlKeyValue(line)
    if not kv.ok:
      continue
    if inNode:
      case kv.key.strip().toLowerAscii()
      of "id":
        current.id = trimTomlQuotes(kv.value)
      of "label":
        current.label = trimTomlQuotes(kv.value)
      of "status":
        current.status = trimTomlQuotes(kv.value)
      of "details":
        current.details = trimTomlQuotes(kv.value)
      of "parent", "parent_id", "parentid":
        current.parent = trimTomlQuotes(kv.value)
      else:
        discard
      continue
    case kv.key.strip().toLowerAscii()
    of "name":
      result.spec.name = trimTomlQuotes(kv.value)
    of "description":
      result.spec.description = trimTomlQuotes(kv.value)
    of "interval_ms", "intervalms":
      result.spec.intervalMs = parseTomlInt(kv.value, DefaultIntervalMs)
    of "root_id", "rootid":
      rootId = trimTomlQuotes(kv.value)
    else:
      discard
  if inNode and current.id.len > 0:
    nodeInputs.add(current)
  if result.spec.intervalMs <= 0:
    result.spec.intervalMs = DefaultIntervalMs
  if nodeInputs.len == 0:
    result.ok = false
    result.error = "pipeline TOML must define at least one [[nodes]] entry"
    return
  if rootId.len == 0:
    i = 0
    while i < nodeInputs.len:
      if nodeInputs[i].parent.strip().len == 0:
        rootId = nodeInputs[i].id
        break
      inc i
  if rootId.len == 0:
    rootId = nodeInputs[0].id
  result.spec.root = buildNodeTree(nodeInputs, rootId)
  if result.spec.root.id.len == 0:
    result.ok = false
    result.error = "pipeline root could not be resolved from TOML nodes"
    return
  result.ok = true

proc readPipelineToml(path: string): PipelineParseResult {.role(parser).} =
  ## path: TOML pipeline file path.
  try:
    result = parsePipelineToml(readFile(path))
  except CatchableError:
    result.ok = false
    result.error = "failed to parse pipeline TOML: " & getCurrentExceptionMsg()

proc readPipelineJson(path: string): PipelineParseResult {.role(parser).} =
  ## path: legacy JSON pipeline file path.
  var
    n: JsonNode
  try:
    n = parseFile(path)
  except CatchableError:
    result.ok = false
    result.error = "failed to parse pipeline JSON: " & getCurrentExceptionMsg()
    return
  result = parsePipelineJson(n)

proc readPipelineSpec*(pipelinePath: string): PipelineParseResult {.role(parser).} =
  ## pipelinePath: TOML or legacy JSON pipeline file path.
  var
    ext: string
    text: string
  ext = splitFile(pipelinePath).ext.toLowerAscii()
  if not fileExists(pipelinePath):
    result.ok = false
    result.error = "pipeline file does not exist: " & pipelinePath
    return
  if ext == ".json":
    return readPipelineJson(pipelinePath)
  result = readPipelineToml(pipelinePath)
  if not result.ok:
    try:
      text = readFile(pipelinePath)
    except CatchableError:
      return
    if text.strip().startsWith("{"):
      result = readPipelineJson(pipelinePath)

proc statusBadge(s: string, frame: int): string {.role(helper).} =
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

proc nodeLine(n: PipelineNode, frame: int): string {.role(helper).} =
  ## n: pipeline node.
  ## frame: current frame index.
  result = "[" & statusBadge(n.status, frame) & "] [" & n.id & "] " & n.label

proc appendNodeLines(ls: var seq[string], n: PipelineNode, prefix: string, last: bool,
                     isRoot: bool, frame: int) {.role(actor).} =
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

proc renderPipelineFrame*(s: PipelineSpec, frame: int, pipelinePath: string): string {.role(helper).} =
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

proc defaultPipelineCandidates*(repoPath: string): seq[string] {.role(helper).} =
  ## repoPath: repository root path.
  var
    tRepo: string
  tRepo = absolutePath(repoPath)
  result = @[
    joinPath(tRepo, ".iron", "pipeline.toml"),
    joinPath(tRepo, ".iron", "pipeline.library.toml"),
    joinPath(tRepo, "iron", "pipeline.toml"),
    joinPath(tRepo, "iron", "pipeline.library.toml"),
    joinPath(tRepo, ".iron", "pipeline.json"),
    joinPath(tRepo, ".iron", "pipeline.library.json"),
    joinPath(tRepo, "iron", "pipeline.json"),
    joinPath(tRepo, "iron", "pipeline.library.json")
  ]

proc defaultPipelinePath*(repoPath: string): string {.role(helper).} =
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

proc resolvePipelinePath*(repoPath: string, pipelinePath: string): string {.role(parser).} =
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

proc clearTerminal() {.role(actor).} =
  stdout.write("\27[2J\27[H")
  flushFile(stdout)

proc showPipeline*(repoPath: string, pipelinePath: string, once: bool, loops: int,
                   intervalMs: int): PipelineShowReport {.role(orchestrator).} =
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
