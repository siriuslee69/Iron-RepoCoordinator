# Valkyrie Tooling | core command logic
# Parsing and dispatch for CLI and library consumers.

import std/strutils
import ../level0/types

proc buildHelp*(): string =
  ## returns CLI help text
  var
    tLines: seq[string]
  tLines = @[
    "Valkyrie Tooling CLI",
    "",
    "Usage:",
    "  valkyrie_cli <command>",
    "",
    "Commands:",
    "  help     Show this help",
    "  status   Show repo status summary",
    "  scan     Scan local repos",
    "  repos    List known repos",
    "  version  Show version"
  ]
  result = tLines.join("\n")

proc parseCommand*(cs: seq[string]): ToolingCommand =
  ## cs: command-line arguments
  var
    t: string
  if cs.len == 0:
    result = tcHelp
    return
  t = cs[0].toLowerAscii()
  case t
  of "help", "-h", "--help":
    result = tcHelp
  of "status":
    result = tcStatus
  of "scan":
    result = tcScan
  of "repos":
    result = tcRepos
  of "version", "-v", "--version":
    result = tcVersion
  else:
    result = tcHelp

proc runCommand*(c: ToolingCommand, s: ToolingConfig): string =
  ## c: command to run
  ## s: tooling configuration
  var
    t: string
  case c
  of tcHelp:
    t = buildHelp()
  of tcStatus:
    t = "Status: not implemented yet (root: " & s.rootDir & ")"
  of tcScan:
    t = "Scan: not implemented yet (root: " & s.rootDir & ")"
  of tcRepos:
    t = "Repos: not implemented yet (root: " & s.rootDir & ")"
  of tcVersion:
    t = "Valkyrie-Tooling v0.1.0"
  result = t
