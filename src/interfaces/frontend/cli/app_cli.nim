# iron Tooling | CLI runner
# Wires CLI arguments to core command logic.

import std/os
import ../../../lib/level0/config
import ../../../lib/level0/types
import ../../../lib/level1/core
include ../../../lib/level0/metaPragmas

proc hasVerboseFlag(cs: seq[string]): bool {.role(parser).} =
  ## cs: command-line arguments
  var
    i: int
    tArg: string
  i = 0
  while i < cs.len:
    tArg = cs[i]
    if tArg == "--verbose":
      result = true
      return
    inc i
  result = false

proc stripVerboseFlag(cs: seq[string]): seq[string] {.role(helper).} =
  ## cs: command-line arguments
  var
    t: seq[string]
    i: int
    tArg: string
  i = 0
  while i < cs.len:
    tArg = cs[i]
    if tArg != "--verbose":
      t.add(tArg)
    inc i
  result = t

proc runCli*(): int {.role(metaOrchestrator).} =
  ## returns process exit code
  var
    cs: seq[string]
    tState: ToolingCommandTruth
    o: ToolingOptions
    s: ToolingConfig
    tOut: string
  cs = commandLineParams()
  s = defaultConfig()
  if hasVerboseFlag(cs):
    s.verbose = true
  cs = stripVerboseFlag(cs)
  tState = resolveCliCommand(cs)
  if tState.message.len > 0:
    echo tState.message
  if tState.cancelled:
    result = 1
    return
  if not tState.recognized:
    result = 1
    return
  o = parseOptions(cs)
  tOut = runCommand(tState.command, s, o)
  if tOut.len > 0:
    echo tOut
  result = 0
