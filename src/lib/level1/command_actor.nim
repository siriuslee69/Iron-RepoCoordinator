# ==================================================
# | iron Tooling Command Actor                 |
# |------------------------------------------------|
# | Resolves command menus and suggestion choices. |
# ==================================================

import std/[strutils, terminal]
import ../level0/types
import ../level0/repo_utils
import command_catalog
include ../level0/metaPragmas


proc readSpecLabels(S: seq[ToolingCommandSpec]): seq[string] {.role(parser).} =
  ## S: command specs to show in a menu.
  var
    i: int
    t: string
  i = 0
  while i < S.len:
    t = S[i].name
    if S[i].summary.len > 0:
      t = t & " | " & S[i].summary
    result.add(t)
    inc i

proc readSuggestionMessage(T: ToolingCommandTruth): string {.role(parser).} =
  ## T: command truth state with unknown command suggestions.
  var
    L: seq[string]
    i: int
  if T.input.commandToken.len == 0:
    return "No command provided."
  if T.suggestions.len == 0:
    return "Unknown command: " & T.input.commandToken
  L = @["Unknown command: " & T.input.commandToken, "Did you mean:"]
  i = 0
  while i < T.suggestions.len:
    L.add(" - " & T.suggestions[i].name)
    inc i
  result = L.join("\n")

proc chooseSpec(title: string, S: seq[ToolingCommandSpec], defaultIndex: int): int {.role(helper).} =
  ## title: menu title.
  ## S: specs to show.
  ## defaultIndex: default index for ENTER selection.
  var
    O: seq[string]
  O = readSpecLabels(S)
  result = promptOptionsDefault(title, O, defaultIndex)

proc resolveCommandTruth*(T: ToolingCommandTruth): ToolingCommandTruth {.role(orchestrator).} =
  ## T: command truth state to resolve interactively if needed.
  var
    A: seq[ToolingCommandSpec]
    i: int
    idx: int
  result = T
  if T.recognized:
    return
  if not isatty(stdin):
    result.message = readSuggestionMessage(T)
    return
  if not T.input.hasCommand:
    A = readCommandSpecs()
    idx = chooseSpec("Select command:", A, 0)
    if idx < 0:
      result.cancelled = true
      result.message = "Command selection cancelled."
      return
    result.command = A[idx].command
    result.recognized = true
    return
  if T.suggestions.len > 0:
    idx = chooseSpec("Select the command you meant:", T.suggestions, 0)
    if idx < 0:
      result.cancelled = true
      result.message = "Command selection cancelled."
      return
    result.command = T.suggestions[idx].command
    result.recognized = true
    return
  A = readCommandSpecs()
  i = 0
  while i < A.len:
    if A[i].command != tcHelp:
      result.suggestions.add(A[i])
    inc i
  idx = chooseSpec("Unknown command. Select one instead:", result.suggestions, 0)
  if idx < 0:
    result.cancelled = true
    result.message = "Command selection cancelled."
    return
  result.command = result.suggestions[idx].command
  result.recognized = true
