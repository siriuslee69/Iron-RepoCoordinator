# Valkyrie Tooling | CLI runner
# Wires CLI arguments to core command logic.

import std/os
import ../../lib/level0/config
import ../../lib/level0/types
import ../../lib/level1/core

proc hasVerboseFlag(cs: seq[string]): bool =
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

proc stripVerboseFlag(cs: seq[string]): seq[string] =
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

proc runCli*(): int =
  ## returns process exit code
  var
    cs: seq[string]
    c: ToolingCommand
    s: ToolingConfig
    tOut: string
  cs = commandLineParams()
  s = defaultConfig()
  if hasVerboseFlag(cs):
    s.verbose = true
  cs = stripVerboseFlag(cs)
  c = parseCommand(cs)
  tOut = runCommand(c, s)
  if tOut.len > 0:
    echo tOut
  result = 0
