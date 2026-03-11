# ==================================================
# | iron Tooling Command Truth                 |
# |------------------------------------------------|
# | Maps perceived CLI tokens into command state.  |
# ==================================================

import std/[algorithm, strutils]
import ../level0/types
import command_catalog
include ../level0/metaPragmas


proc normalizeToken(t: string): string {.role(parser).} =
  ## t: raw token to normalize for matching.
  result = t.strip().toLowerAscii()

proc readPrefixLen(a: string, b: string): int {.role(parser).} =
  ## a: first string to compare.
  ## b: second string to compare.
  var
    i: int
    l: int
  l = a.len
  if b.len < l:
    l = b.len
  i = 0
  while i < l:
    if a[i] != b[i]:
      return
    inc result
    inc i

proc readOrderedHitCount(a: string, b: string): int {.role(parser).} =
  ## a: query string.
  ## b: candidate string.
  var
    i: int
    j: int
  i = 0
  j = 0
  while i < a.len and j < b.len:
    if a[i] == b[j]:
      inc result
      inc i
      inc j
      continue
    inc j

proc readAliasScore(q: string, a: string): int {.role(parser).} =
  ## q: normalized user token.
  ## a: normalized alias.
  var
    tPrefix: int
    tHits: int
    tDiff: int
  if q.len == 0 or a.len == 0:
    return 0
  if q == a:
    return 1000
  tPrefix = readPrefixLen(q, a)
  tHits = readOrderedHitCount(q, a)
  tDiff = abs(a.len - q.len)
  result = result + tPrefix * 25
  result = result + tHits * 8
  result = result - tDiff * 3
  if a.startsWith(q):
    result = result + 200
  if q.startsWith(a):
    result = result + 120
  if a.contains(q):
    result = result + 60
  if q[0] == a[0]:
    result = result + 15

proc readSpecScore(q: string, s: ToolingCommandSpec): int {.role(parser).} =
  ## q: normalized user token.
  ## s: command spec to score.
  var
    i: int
    tScore: int
    tAlias: string
  i = 0
  while i < s.aliases.len:
    tAlias = normalizeToken(s.aliases[i])
    tScore = readAliasScore(q, tAlias)
    if tScore > result:
      result = tScore
    inc i

proc readSuggestions(q: string, S: seq[ToolingCommandSpec]): seq[ToolingCommandSpec] {.role(metaParser).} =
  ## q: normalized user token.
  ## S: full command catalog.
  var
    scored: seq[tuple[score: int, spec: ToolingCommandSpec]]
    i: int
    tScore: int
  i = 0
  while i < S.len:
    tScore = readSpecScore(q, S[i])
    if tScore > 0:
      scored.add((tScore, S[i]))
    inc i
  scored.sort(proc(a, b: tuple[score: int, spec: ToolingCommandSpec]): int =
    result = system.cmp(b.score, a.score)
  )
  i = 0
  while i < scored.len and i < 5:
    result.add(scored[i].spec)
    inc i

proc buildCommandTruth*(I: ToolingCommandInput): ToolingCommandTruth {.role(truthBuilder).} =
  ## I: perceived command input.
  var
    S: seq[ToolingCommandSpec]
    i: int
    j: int
    q: string
    a: string
  result.input = I
  result.command = tcHelp
  result.recognized = false
  result.cancelled = false
  result.message = ""
  result.suggestions = @[]
  if not I.hasCommand:
    return
  q = normalizeToken(I.commandToken)
  S = readCommandSpecs()
  i = 0
  while i < S.len:
    j = 0
    while j < S[i].aliases.len:
      a = normalizeToken(S[i].aliases[j])
      if q == a:
        result.command = S[i].command
        result.recognized = true
        return
      inc j
    inc i
  result.suggestions = readSuggestions(q, S)
