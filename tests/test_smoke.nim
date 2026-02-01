# Valkyrie Tooling | smoke tests
# Basic checks for core command routing.

import std/[strutils, unittest]
import valkyrie_tooling

suite "valkyrie tooling":
  test "parseCommand help":
    var
      cs: seq[string]
      c: ToolingCommand
    cs = @[]
    c = parseCommand(cs)
    check c == tcHelp

  test "runCommand version":
    var
      s: ToolingConfig
      t: string
    s = defaultConfig()
    t = runCommand(tcVersion, s)
    check t.contains("Valkyrie-Tooling")
