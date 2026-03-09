# iron Tooling | config helpers
# Default configuration values for CLI and library usage.

import std/[os, strutils]
import types
import ../../level0/repo_utils

proc defaultConfig*(): ToolingConfig =
  ## returns a default ToolingConfig
  var
    t: ToolingConfig
    tRoot: string
    tVerbose: string
  tRoot = getCurrentDir()
  t.rootDir = tRoot
  t.verbose = false
  tVerbose = readEnvWithFallback("IRON_VERBOSE")
  if tVerbose.len > 0:
    tVerbose = tVerbose.strip().toLowerAscii()
    if tVerbose in ["1", "true", "yes", "on"]:
      t.verbose = true
  result = t
