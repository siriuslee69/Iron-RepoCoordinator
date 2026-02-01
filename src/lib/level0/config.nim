# Valkyrie Tooling | config helpers
# Default configuration values for CLI and library usage.

import std/[os, strutils]
import types

proc defaultConfig*(): ToolingConfig =
  ## returns a default ToolingConfig
  var
    t: ToolingConfig
    tRoot: string
    tVerbose: string
  tRoot = getCurrentDir()
  t.rootDir = tRoot
  t.verbose = false
  if existsEnv("VALKYRIE_VERBOSE"):
    tVerbose = getEnv("VALKYRIE_VERBOSE")
    tVerbose = tVerbose.strip().toLowerAscii()
    if tVerbose in ["1", "true", "yes", "on"]:
      t.verbose = true
  result = t
