# Valkyrie Tooling | config helpers
# Default configuration values for CLI and library usage.

import std/os
import types

proc defaultConfig*(): ToolingConfig =
  ## returns a default ToolingConfig
  var
    t: ToolingConfig
    tRoot: string
  tRoot = getCurrentDir()
  t.rootDir = tRoot
  t.verbose = false
  result = t
