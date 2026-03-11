# ==================================================
# | iron Tooling Command Options               |
# |------------------------------------------------|
# | Parses CLI flags into the shared options state.|
# ==================================================

import std/[os, strutils]
import ../level0/types
import command_perception
include ../level0/metaPragmas


proc defaultOptions*(): ToolingOptions {.role(helper).} =
  ## returns default command options.
  var
    t: ToolingOptions
  t.repo = getCurrentDir()
  t.root = ""
  t.mode = ""
  t.cloneUrl = ""
  t.srcPath = ""
  t.docsOut = ""
  t.pipelinePath = ""
  t.replace = false
  t.dryRun = false
  t.once = false
  t.loops = 0
  t.intervalMs = 700
  t.overwrite = false
  t.configOwners = ""
  t.configAddOwner = ""
  t.configRemoveOwner = ""
  t.configExcludedRepos = ""
  t.configAddExcludedRepo = ""
  t.configRemoveExcludedRepo = ""
  t.configForeignMode = ""
  result = t

proc parseIntWithFallback(t: string, d: int): int {.role(parser).} =
  ## t: input string to parse as integer.
  ## d: fallback value when parsing fails.
  try:
    result = parseInt(t)
  except ValueError:
    result = d

proc readFlagValue(A: seq[string], i: int): string {.role(parser).} =
  ## A: raw CLI arguments.
  ## i: flag index.
  if i + 1 >= A.len:
    return ""
  result = A[i + 1]

proc parseOptions*(A: seq[string]): ToolingOptions {.role(parser).} =
  ## A: raw CLI arguments.
  var
    O: ToolingOptions
    I: ToolingCommandInput
    i: int
    t: string
    v: string
  O = defaultOptions()
  I = readCommandInput(A)
  i = 0
  while i < A.len:
    if i == I.commandIndex:
      inc i
      continue
    t = A[i]
    if not t.startsWith("-"):
      if O.cloneUrl.len == 0:
        O.cloneUrl = t
      inc i
      continue
    if t == "--repo":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.repo = v
        i = i + 2
        continue
    if t.startsWith("--repo="):
      O.repo = t["--repo=".len .. ^1]
      inc i
      continue
    if t == "--root":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.root = v
        i = i + 2
        continue
    if t.startsWith("--root="):
      O.root = t["--root=".len .. ^1]
      inc i
      continue
    if t == "--mode":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.mode = v
        i = i + 2
        continue
    if t.startsWith("--mode="):
      O.mode = t["--mode=".len .. ^1]
      inc i
      continue
    if t == "--replace":
      O.replace = true
      inc i
      continue
    if t == "--src":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.srcPath = v
        i = i + 2
        continue
    if t.startsWith("--src="):
      O.srcPath = t["--src=".len .. ^1]
      inc i
      continue
    if t == "--docs-out":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.docsOut = v
        i = i + 2
        continue
    if t.startsWith("--docs-out="):
      O.docsOut = t["--docs-out=".len .. ^1]
      inc i
      continue
    if t == "--pipeline":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.pipelinePath = v
        i = i + 2
        continue
    if t.startsWith("--pipeline="):
      O.pipelinePath = t["--pipeline=".len .. ^1]
      inc i
      continue
    if t == "--dry-run" or t == "--dryrun":
      O.dryRun = true
      inc i
      continue
    if t == "--once":
      O.once = true
      inc i
      continue
    if t == "--loops":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.loops = parseIntWithFallback(v, O.loops)
        i = i + 2
        continue
    if t.startsWith("--loops="):
      O.loops = parseIntWithFallback(t["--loops=".len .. ^1], O.loops)
      inc i
      continue
    if t == "--interval-ms":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.intervalMs = parseIntWithFallback(v, O.intervalMs)
        i = i + 2
        continue
    if t.startsWith("--interval-ms="):
      O.intervalMs = parseIntWithFallback(t["--interval-ms=".len .. ^1], O.intervalMs)
      inc i
      continue
    if t == "--overwrite":
      O.overwrite = true
      inc i
      continue
    if t == "--owners":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configOwners = v
        i = i + 2
        continue
    if t.startsWith("--owners="):
      O.configOwners = t["--owners=".len .. ^1]
      inc i
      continue
    if t == "--owner":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configOwners = v
        i = i + 2
        continue
    if t.startsWith("--owner="):
      O.configOwners = t["--owner=".len .. ^1]
      inc i
      continue
    if t == "--add-owner":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configAddOwner = v
        i = i + 2
        continue
    if t.startsWith("--add-owner="):
      O.configAddOwner = t["--add-owner=".len .. ^1]
      inc i
      continue
    if t == "--remove-owner":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configRemoveOwner = v
        i = i + 2
        continue
    if t.startsWith("--remove-owner="):
      O.configRemoveOwner = t["--remove-owner=".len .. ^1]
      inc i
      continue
    if t == "--exclude-repos" or t == "--excluded-repos":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configExcludedRepos = v
        i = i + 2
        continue
    if t.startsWith("--exclude-repos="):
      O.configExcludedRepos = t["--exclude-repos=".len .. ^1]
      inc i
      continue
    if t.startsWith("--excluded-repos="):
      O.configExcludedRepos = t["--excluded-repos=".len .. ^1]
      inc i
      continue
    if t == "--exclude-repo" or t == "--excluded-repo":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configExcludedRepos = v
        i = i + 2
        continue
    if t.startsWith("--exclude-repo="):
      O.configExcludedRepos = t["--exclude-repo=".len .. ^1]
      inc i
      continue
    if t.startsWith("--excluded-repo="):
      O.configExcludedRepos = t["--excluded-repo=".len .. ^1]
      inc i
      continue
    if t == "--add-exclude" or t == "--add-excluded-repo":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configAddExcludedRepo = v
        i = i + 2
        continue
    if t.startsWith("--add-exclude="):
      O.configAddExcludedRepo = t["--add-exclude=".len .. ^1]
      inc i
      continue
    if t.startsWith("--add-excluded-repo="):
      O.configAddExcludedRepo = t["--add-excluded-repo=".len .. ^1]
      inc i
      continue
    if t == "--remove-exclude" or t == "--remove-excluded-repo":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configRemoveExcludedRepo = v
        i = i + 2
        continue
    if t.startsWith("--remove-exclude="):
      O.configRemoveExcludedRepo = t["--remove-exclude=".len .. ^1]
      inc i
      continue
    if t.startsWith("--remove-excluded-repo="):
      O.configRemoveExcludedRepo = t["--remove-excluded-repo=".len .. ^1]
      inc i
      continue
    if t == "--foreign-mode":
      v = readFlagValue(A, i)
      if v.len > 0:
        O.configForeignMode = v
        i = i + 2
        continue
    if t.startsWith("--foreign-mode="):
      O.configForeignMode = t["--foreign-mode=".len .. ^1]
      inc i
      continue
    inc i
  result = O
