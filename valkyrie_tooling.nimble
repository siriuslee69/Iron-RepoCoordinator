import std/[os, strutils]

version       = "0.1.0"
author        = "siriuslee69"
description   = "Tooling library with CLI for Eitri/Jormungandr integrations"
license       = "UNLICENSED"
srcDir        = "src"
bin           = @["valkyrie_cli", "val"]

requires "nim >= 1.6.0"

task buildCli, "Build the CLI entrypoint":
  exec "nim c -d:release src/valkyrie_cli.nim"
  exec "nim c -d:release src/val.nim"

task runCli, "Run the CLI entrypoint":
  exec "nim c -r src/valkyrie_cli.nim"

task runVal, "Run the short CLI alias":
  exec "nim c -r src/val.nim"

task test, "Run unit tests":
  exec "nim c -r tests/test_smoke.nim"

task autopush, "Add, commit, and push with message from progress.md":
  let path = "progress.md"
  var msg = ""
  if fileExists(path):
    let content = readFile(path)
    for line in content.splitLines:
      if line.startsWith("Commit Message:"):
        msg = line["Commit Message:".len .. ^1].strip()
        break
  if msg.len == 0:
    msg = "No specific commit message given."
  exec "git add -A ."
  exec "git commit -m \" " & msg & "\""
  exec "git push"

task find, "Use local clones for submodules in parent folder":
  let modulesPath = ".gitmodules"
  if not fileExists(modulesPath):
    echo "No .gitmodules found."
  else:
    let root = parentDir(getCurrentDir())
    var current = ""
    for line in readFile(modulesPath).splitLines:
      let s = line.strip()
      if s.startsWith("[submodule"):
        let start = s.find('"')
        let stop = s.rfind('"')
        if start >= 0 and stop > start:
          current = s[start + 1 .. stop - 1]
      elif current.len > 0 and s.startsWith("path"):
        let parts = s.split("=", maxsplit = 1)
        if parts.len == 2:
          let subPath = parts[1].strip()
          let tail = splitPath(subPath).tail
          let localDir = joinPath(root, tail)
          if dirExists(localDir):
            let localUrl = localDir.replace('\\', '/')
            exec "git config -f .gitmodules submodule." & current & ".url " & localUrl
            exec "git config submodule." & current & ".url " & localUrl
    exec "git submodule sync --recursive"
