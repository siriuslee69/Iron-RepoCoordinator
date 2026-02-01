# Valkyrie Tooling | CLI runner
# Wires CLI arguments to core command logic.

import std/os
import ../../lib/level0/config
import ../../lib/level1/core

proc runCli*(): int =
  ## returns process exit code
  var
    cs: seq[string]
    c: ToolingCommand
    s: ToolingConfig
    tOut: string
  cs = commandLineParams()
  c = parseCommand(cs)
  s = defaultConfig()
  tOut = runCommand(c, s)
  if tOut.len > 0:
    echo tOut
  result = 0
