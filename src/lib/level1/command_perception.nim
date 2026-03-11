# ==================================================
# | iron Tooling Command Perception            |
# |------------------------------------------------|
# | Small parsers that read the raw CLI surface.   |
# ==================================================

import ../level0/types
include ../level0/metaPragmas


proc readCommandIndex(A: seq[string]): int {.role(parser).} =
  ## A: raw CLI arguments.
  if A.len == 0:
    return -1
  if A[0] == "--":
    if A.len >= 2:
      return 1
    return -1
  result = 0

proc readCommandInput*(A: seq[string]): ToolingCommandInput {.role(parser).} =
  ## A: raw CLI arguments.
  var
    i: int
  result.args = A
  result.commandIndex = -1
  result.commandToken = ""
  result.hasCommand = false
  i = readCommandIndex(A)
  if i < 0:
    return
  result.commandIndex = i
  result.commandToken = A[i]
  result.hasCommand = result.commandToken.len > 0
