# =========================================
# | Valkyrie Illwill Pipeline Demo        |
# |---------------------------------------|
# | Compile manually:                     |
# | nim c -r valk/illwill_pipeline_example.nim |
# =========================================

import std/[os, strutils]
import illwill

proc drawFrame(p: string, frame: int) =
  var
    t0: TerminalBuffer
    ls: seq[string]
    i: int
  t0 = newTerminalBuffer(120, 40)
  t0.clear()
  ls = readFile(p).splitLines()
  t0.write(1, 1, "Illwill Pipeline Demo")
  t0.write(1, 2, "Frame: " & $frame & " | File: " & p)
  i = 0
  while i < ls.len and i < 34:
    t0.write(1, 4 + i, ls[i])
    inc i
  display(t0)

proc runDemo(p: string) =
  var
    i: int
  i = 0
  while true:
    drawFrame(p, i)
    sleep(500)
    inc i

when isMainModule:
  let p = if paramCount() > 0: paramStr(1) else: "valk/pipeline.json"
  initScreen()
  defer: deinitScreen()
  setCursorVisibility(false)
  runDemo(p)
