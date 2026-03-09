import std/[os, strutils]

version       = "0.4.0"
author        = "siriuslee69"
description   = "CLI-first multi-repo tooling with embedded repo-coordinator features"
license       = "UNLICENSED"
srcDir        = "src"
bin           = @["iron", "iron_cli"]

requires "nim >= 1.6.0"

task buildCli, "Build the CLI entrypoint":
  exec "nim c -d:release src/iron.nim"
  exec "nim c -d:release src/iron_cli.nim"

task runCli, "Run the CLI entrypoint":
  exec "nim c -r src/iron.nim"

task test, "Run unit tests":
  exec "nim c -r tests/test_smoke.nim"
  exec "nim c -r tests/test_repo_coordinator_smoke.nim"

task autopull, "Pull all repos under configured roots":
  exec "nim c -r src/iron.nim -- autopull"

task autopushall, "Push all repos under configured roots":
  exec "nim c -r src/iron.nim -- pushall"

task pushall, "Add/commit/push all repos under parent directory":
  exec "nim c -r src/iron.nim -- pushall"

task submodrefresh, "Stash and pull latest main for submodule repos":
  exec "nim c -r src/iron.nim -- refresh"

task find, "Create local submodule overrides and update git config":
  exec "nim c -r src/iron.nim -- find"

task expand, "Expand updated submodule across sibling repos":
  exec "nim c -r src/iron.nim -- expand"

task extract_submodules, "Clone submodules to sibling repos and apply local overrides":
  exec "nim c -r src/iron.nim -- extract"

task extract_submodules_global, "Extract submodules for all repos under roots":
  exec "nim c -r src/iron.nim -- extract-all"

task branch_mode, "Switch repo between main/nightly or promote nightly":
  exec "nim c -r src/iron.nim -- branch"

task clone, "Clone a repo and initialize .iron defaults":
  exec "nim c -r src/iron.nim -- clone"

task init, "Initialize .iron defaults in the current repo":
  exec "nim c -r src/iron.nim -- init --repo ."

task conflicts, "Interactive conflict overview and resolver":
  exec "nim c -r src/iron.nim -- conflicts --root ."

task repotest, "Pick and run a test task (nimble + eitri)":
  exec "nim c -r src/iron.nim -- test"

task docs_init, "Scaffold docs + pipeline files in .iron/":
  exec "nim c -r src/iron.nim -- docs-init --repo ."

task docs, "Generate library docs markdown + JSON bridge":
  exec "nim c -r src/iron.nim -- docs --repo ."

task show, "Render one frame of the local pipeline graph":
  exec "nim c -r src/iron.nim -- show --repo . --once"

task autopush, "Add, commit, and push with message from .iron/PROGRESS.md":
  let path = ".iron/PROGRESS.md"
  var msg = ""
  var source = path
  if not fileExists(source):
    let alt = ".iron/progress.md"
    if fileExists(alt):
      source = alt
  if fileExists(source):
    let content = readFile(source)
    for line in content.splitLines:
      if line.startsWith("Commit Message:"):
        msg = line["Commit Message:".len .. ^1].strip()
        break
  if msg.len == 0:
    msg = "No specific commit message given."
  exec "git add -A ."
  exec "git commit -m \" " & msg & "\""
  exec "git push"

task find_current, "Use local clones for submodules in parent folder (current repo only)":
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

task smoke, "Run smoke tests":
  exec "nim c -r ../tests/test_repo_coordinator_smoke.nim"
  exec "nim c -r ../tests/test_smoke.nim"

