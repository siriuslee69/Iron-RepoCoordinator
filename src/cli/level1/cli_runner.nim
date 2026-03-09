# iron Tooling | CLI runner
# Wires CLI arguments to core command logic.

import std/os
import ../../iron_repo_coordinator/lib/level0/config
import ../../iron_repo_coordinator/lib/level0/types
import ../../iron_repo_coordinator/lib/level1/core

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
    o: ToolingOptions
    s: ToolingConfig
    tOut: string
  cs = commandLineParams()
  s = defaultConfig()
  if hasVerboseFlag(cs):
    s.verbose = true
  cs = stripVerboseFlag(cs)
  c = parseCommand(cs)
  o = parseOptions(cs)
  tOut = runCommand(c, s, o)
  if tOut.len > 0:
    echo tOut
  result = 0
