# ==================================================
# | iron Repo Coordinator Bootstrap         |
# |------------------------------------------------|
# | Repo init + clone wrapper with .iron defaults. |
# ==================================================

import std/[os, strutils, osproc]
import ../level0/repo_utils


type
  RepoInitReport* = object
    ok*: bool
    repoPath*: string
    created*: seq[string]
    updated*: seq[string]
    skipped*: seq[string]
    lines*: seq[string]

  CloneRepoReport* = object
    ok*: bool
    repoPath*: string
    cloned*: bool
    lines*: seq[string]


const
  DefaultConventionsText = """# Repository Conventions

- Keep repository metadata in `.iron/`.
- Track `.iron/CONVENTIONS.md`, `.iron/PROGRESS.md`, and `.iron/.local*.template`.
- Keep `.iron/.local*` ignored in git, except `.template` files.
- Keep machine-local paths in `.iron/.local.config.toml`.
- Keep local submodule overrides in `.iron/.local.gitmodules.toml`.
"""
  DefaultProgressText = """# Progress

Commit Message: chore: describe the current change

Features (Planned):
- TBD

Features (Done):
- TBD

Features (In Progress):
- TBD
"""
  DefaultLocalConfigTemplate = """# Local machine settings for iron.

root = "C:/ChangeMe/CodingMain"
"""
  DefaultLocalModulesTemplate = """## Delete this comment and replace the path with a local one, if this folder is included in an actual repo

["submodules/MySubmodule"]
path = "submodules/MySubmodule"
url = "C:/ChangeMe/MySubmodule"
"""


proc addLine(ls: var seq[string], l: string) =
  ## ls: line buffer.
  ## l: line to append.
  ls.add(l)

proc runCmd(c: string): tuple[text: string, code: int] =
  ## c: command to execute.
  var
    tText: string
    tCode: int
  (tText, tCode) = execCmdEx(c)
  result = (tText, tCode)

proc runGit(r, a: string): tuple[text: string, code: int] =
  ## r: repo path.
  ## a: git arguments.
  var c: string = "git -C " & quoteShell(r) & " " & a
  result = runCmd(c)

proc isGitRepo(r: string): bool =
  ## r: repo path to validate.
  var t: tuple[text: string, code: int] = runGit(r, "rev-parse --is-inside-work-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc removeTree(p: string) =
  ## p: directory tree to remove recursively.
  if not dirExists(p):
    return
  for entry in walkDir(p, relative = false):
    case entry.kind
    of pcFile, pcLinkToFile:
      removeFile(entry.path)
    of pcDir:
      removeTree(entry.path)
    else:
      discard
  if dirExists(p):
    removeDir(p)

proc ensureTemplateSource(repoPath: string): string =
  ## repoPath: target repo path used to locate proto-conventions templates.
  var
    d: string
    i: int
    c: string
    repoRoot: string
  repoRoot = normalizePathValue(repoPath)
  c = joinPath(repoRoot, "submodules", "proto-conventions", ".iron")
  if dirExists(c):
    return c
  d = normalizePathValue(repoPath)
  i = 0
  while i < 6 and d.len > 0:
    c = joinPath(d, "proto-conventions", ".iron")
    if dirExists(c):
      return c
    c = joinPath(parentDir(d), "proto-conventions", ".iron")
    if dirExists(c):
      return c
    if parentDir(d) == d:
      break
    d = parentDir(d)
    inc i
  result = ""

proc ensureFromTemplate(path: string, templatePath: string, fallbackText: string,
                        overwrite: bool, report: var RepoInitReport) =
  ## path: target file path.
  ## templatePath: optional source template file.
  ## fallbackText: fallback content if template is missing.
  ## overwrite: allow replacing existing files.
  ## report: report object.
  var text: string
  if fileExists(path) and not overwrite:
    report.skipped.add(path)
    return
  if templatePath.len > 0 and fileExists(templatePath):
    text = readFile(templatePath)
  else:
    text = fallbackText
  ensureParentDir(path)
  writeFile(path, text)
  if fileExists(path):
    report.updated.add(path)
  else:
    report.created.add(path)

proc moveLegacyFile(src: string, dst: string, report: var RepoInitReport) =
  ## src: legacy source path.
  ## dst: destination path.
  ## report: report object.
  if not fileExists(src):
    return
  if fileExists(dst):
    report.skipped.add(dst)
    return
  ensureParentDir(dst)
  moveFile(src, dst)
  report.updated.add(dst)

proc migrateLegacyiron(repo: string, report: var RepoInitReport) =
  ## repo: repository root path.
  ## report: report object.
  var
    oldMeta: string
    meta: string
    dst: string
    progressTarget: string
  oldMeta = joinPath(repo, LegacyironDir)
  meta = joinPath(repo, ironDir)
  if not dirExists(oldMeta):
    return
  if not dirExists(meta):
    createDir(meta)
  progressTarget = joinPath(meta, "PROGRESS.md")
  moveLegacyFile(joinPath(oldMeta, "progress.md"), progressTarget, report)
  moveLegacyFile(joinPath(meta, "progress.md"), progressTarget, report)
  moveLegacyFile(joinPath(oldMeta, "conventions.md"), joinPath(meta, "CONVENTIONS.md"), report)
  moveLegacyFile(joinPath(oldMeta, "iron_config.md"), joinPath(meta, ".local.config.toml"), report)
  moveLegacyFile(joinPath(oldMeta, ".gitmodules.local"), joinPath(meta, ".local.gitmodules.toml"), report)
  for kind, path in walkDir(oldMeta):
    if kind != pcFile:
      continue
    dst = joinPath(meta, lastPathPart(path))
    if fileExists(dst):
      continue
    moveFile(path, dst)
    report.updated.add(dst)
  try:
    removeDir(oldMeta)
  except OSError:
    discard

proc ensureProgressFile(repoRoot: string, metaPath: string, report: var RepoInitReport) =
  ## repoRoot: repository root path.
  ## metaPath: .iron metadata folder path.
  ## report: report object.
  var
    target: string
    source: string
  target = joinPath(metaPath, "PROGRESS.md")
  source = resolveProgressFile(repoRoot)
  if fileExists(target):
    return
  if source != target and fileExists(source):
    moveLegacyFile(source, target, report)

proc resolveLocalName(m: SubmoduleInfo): string =
  ## m: submodule metadata.
  var t: string = splitPath(m.path).tail
  if t.len == 0:
    t = extractRepoTail(m.url)
  if t.len == 0:
    t = m.name
  result = t

proc ensureCloneTarget(url, parentDir: string, report: var CloneRepoReport): string =
  ## url: clone URL.
  ## parentDir: clone parent folder.
  ## report: report object.
  var
    t: string
    i: int
    base: string
    dest: string
    idx: int
    opts: seq[string]
  t = url.strip().replace('\\', '/')
  if t.endsWith("/"):
    t = t[0 .. ^2]
  if t.endsWith(".git"):
    t = t[0 .. ^5]
  i = t.rfind('/')
  if i < 0:
    i = t.rfind(':')
  if i >= 0 and i + 1 < t.len:
    base = t[i + 1 .. ^1]
  else:
    base = "repo"
  dest = joinPath(parentDir, base)
  if not dirExists(dest):
    return dest
  if isGitRepo(dest):
    opts = @[
      "Use existing repo at " & dest,
      "Delete existing repo and clone fresh",
      "Clone into a new sibling folder",
      "Abort"
    ]
    idx = promptOptionsDefault("Destination already exists for clone target:", opts, 0)
    if idx < 0 or idx == 3:
      return ""
    if idx == 0:
      return dest
    if idx == 1:
      if not confirmEnter("Delete " & dest & " and re-clone?"):
        return ""
      removeTree(dest)
      return dest
    i = 2
    while true:
      t = joinPath(parentDir, base & "-clone-" & $i)
      if not dirExists(t):
        return t
      inc i
  opts = @[
    "Delete folder and clone here",
    "Clone into a new sibling folder",
    "Abort"
  ]
  idx = promptOptionsDefault("Non-repo folder exists at clone target:", opts, 1)
  if idx < 0 or idx == 2:
    return ""
  if idx == 0:
    if not confirmEnter("Delete " & dest & " and clone?"):
      return ""
    removeTree(dest)
    return dest
  i = 2
  while true:
    t = joinPath(parentDir, base & "-clone-" & $i)
    if not dirExists(t):
      return t
    inc i

proc runSubmoduleUpdate(repo: string, report: var CloneRepoReport) =
  ## repo: repository root path.
  ## report: clone report object.
  discard runGit(repo, "submodule sync --recursive")
  if execCmd("git -C " & quoteShell(repo) & " submodule update --init --recursive") != 0:
    report.ok = false
    addLine(report.lines, "Submodule update failed.")
  else:
    addLine(report.lines, "Submodule update complete.")

proc cloneSubmodulesToParent(repo: string, parentDir: string, ms: seq[SubmoduleInfo],
                             report: var CloneRepoReport) =
  ## repo: repository root path.
  ## parentDir: parent folder where sibling repos are stored.
  ## ms: submodule metadata.
  ## report: clone report object.
  var
    localEntries: seq[SubmoduleInfo]
    name: string
    dest: string
    idx: int
    opts: seq[string]
    m2: SubmoduleInfo
    gl: string
    merged: seq[SubmoduleInfo]
  for m in ms:
    name = resolveLocalName(m)
    if name.len == 0:
      continue
    dest = joinPath(parentDir, name)
    if dirExists(dest):
      if isGitRepo(dest):
        opts = @[
          "Use existing local repo",
          "Delete and clone fresh",
          "Skip this submodule"
        ]
        idx = promptOptionsDefault("Submodule clone target exists: " & dest, opts, 0)
        if idx < 0:
          report.ok = false
          addLine(report.lines, "Submodule setup aborted.")
          return
        if idx == 1:
          if not confirmEnter("Delete " & dest & " and re-clone?"):
            report.ok = false
            addLine(report.lines, "Submodule setup aborted.")
            return
          removeTree(dest)
        elif idx == 2:
          continue
      else:
        opts = @[
          "Delete folder and clone",
          "Skip this submodule"
        ]
        idx = promptOptionsDefault("Non-repo folder exists: " & dest, opts, 1)
        if idx < 0:
          report.ok = false
          addLine(report.lines, "Submodule setup aborted.")
          return
        if idx == 0:
          if not confirmEnter("Delete " & dest & " and clone?"):
            report.ok = false
            addLine(report.lines, "Submodule setup aborted.")
            return
          removeTree(dest)
        else:
          continue
    if not dirExists(dest):
      if m.url.len == 0:
        addLine(report.lines, "Missing submodule URL for " & m.path)
        continue
      if execCmd("git clone " & quoteShell(m.url) & " " & quoteShell(dest)) != 0:
        report.ok = false
        addLine(report.lines, "Failed to clone submodule: " & m.url)
        continue
      addLine(report.lines, "Cloned submodule: " & name)
    m2 = m
    m2.url = normalizePathValue(dest)
    localEntries.add(m2)
  if localEntries.len == 0:
    addLine(report.lines, "No local submodule overrides applied.")
    return
  gl = joinPath(repo, LocalModulesFile)
  merged = mergeSubmodules(readSubmodules(gl), localEntries)
  ensureParentDir(gl)
  writeLocalModules(gl, merged)
  if applyLocalConfig(repo, merged) != 0:
    report.ok = false
    addLine(report.lines, "Failed to apply local submodule config.")
  else:
    addLine(report.lines, "Applied local submodule overrides to " & LocalModulesFile)
  runSubmoduleUpdate(repo, report)

proc setupSubmodulesAfterClone(repo: string, report: var CloneRepoReport) =
  ## repo: repository root path.
  ## report: clone report object.
  var
    gm: string
    ms: seq[SubmoduleInfo]
    idx: int
    parentRoot: string
    localRepos: seq[string]
    locals: seq[SubmoduleInfo]
    gl: string
    merged: seq[SubmoduleInfo]
  gm = joinPath(repo, ".gitmodules")
  if not fileExists(gm):
    addLine(report.lines, "No submodules found in cloned repo.")
    return
  ms = readSubmodules(gm)
  if ms.len == 0:
    addLine(report.lines, "No submodules declared in .gitmodules.")
    return
  parentRoot = parentDir(repo)
  idx = promptOptionsDefault("Submodule setup:", @[
    "Look for local clones in parent folder",
    "Clone submodules now",
    "Skip submodule setup"
  ], 0)
  if idx < 0 or idx == 2:
    addLine(report.lines, "Submodule setup skipped.")
    return
  if idx == 0:
    localRepos = collectRepos(@[parentRoot])
    locals = mapLocalSubmodules(ms, localRepos, repo)
    if locals.len > 0:
      gl = joinPath(repo, LocalModulesFile)
      merged = mergeSubmodules(readSubmodules(gl), locals)
      discard ensureLocalIgnoreRules(repo)
      ensureParentDir(gl)
      writeLocalModules(gl, merged)
      if applyLocalConfig(repo, merged) != 0:
        report.ok = false
        addLine(report.lines, "Failed to apply local submodule config.")
      else:
        addLine(report.lines, "Linked " & $locals.len & " submodules from local clones.")
      runSubmoduleUpdate(repo, report)
      return
    addLine(report.lines, "No local submodule matches found in parent folder.")
    idx = promptOptionsDefault("Clone submodules instead?", @[
      "Clone submodules now",
      "Skip submodule setup"
    ], 0)
    if idx < 0 or idx == 1:
      addLine(report.lines, "Submodule setup skipped.")
      return
  idx = promptOptionsDefault("Where should submodules be cloned?", @[
    "Clone to parent folder and link via .iron/.local.gitmodules.toml",
    "Clone inside repo with git submodule update",
    "Skip submodule setup"
  ], 0)
  if idx < 0 or idx == 2:
    addLine(report.lines, "Submodule setup skipped.")
    return
  if idx == 0:
    cloneSubmodulesToParent(repo, parentRoot, ms, report)
  else:
    runSubmoduleUpdate(repo, report)

proc initRepoLayout*(repoPath: string, overwriteTemplates: bool): RepoInitReport =
  ## repoPath: target repository path.
  ## overwriteTemplates: allow replacing template files.
  var
    report: RepoInitReport
    repo: string
    meta: string
    templateDir: string
  report.ok = true
  repo = normalizePathValue(repoPath)
  if repo.len == 0:
    repo = normalizePathValue(getCurrentDir())
  report.repoPath = repo
  if repo.len == 0 or not dirExists(repo):
    report.ok = false
    addLine(report.lines, "Repo path does not exist: " & repo)
    return report
  meta = joinPath(repo, ironDir)
  if not dirExists(meta):
    createDir(meta)
    report.created.add(meta)
  migrateLegacyiron(repo, report)
  templateDir = ensureTemplateSource(repo)
  ensureProgressFile(repo, meta, report)
  ensureFromTemplate(
    joinPath(meta, "CONVENTIONS.md"),
    joinPath(templateDir, "CONVENTIONS.md"),
    DefaultConventionsText,
    overwriteTemplates,
    report
  )
  ensureFromTemplate(
    joinPath(meta, "PROGRESS.md"),
    joinPath(templateDir, "PROGRESS.md"),
    DefaultProgressText,
    overwriteTemplates,
    report
  )
  ensureFromTemplate(
    joinPath(meta, ".local.config.toml.template"),
    joinPath(templateDir, ".local.config.toml.template"),
    DefaultLocalConfigTemplate,
    overwriteTemplates,
    report
  )
  ensureFromTemplate(
    joinPath(meta, ".local.gitmodules.toml.template"),
    joinPath(templateDir, ".local.gitmodules.toml.template"),
    DefaultLocalModulesTemplate,
    overwriteTemplates,
    report
  )
  if ensureLocalIgnoreRules(repo):
    report.updated.add(joinPath(repo, ".gitignore"))
  addLine(report.lines, "Initialized .iron metadata in " & repo)
  if report.created.len > 0:
    addLine(report.lines, "Created: " & report.created.join(", "))
  if report.updated.len > 0:
    addLine(report.lines, "Updated: " & report.updated.join(", "))
  if report.skipped.len > 0:
    addLine(report.lines, "Skipped: " & report.skipped.join(", "))
  result = report

proc cloneRepoWithiron*(url: string, rootOverride: string,
                       overwriteTemplates: bool, verbose: bool): CloneRepoReport =
  ## url: repository URL/path to clone.
  ## rootOverride: optional destination parent folder.
  ## overwriteTemplates: allow replacing template files during init.
  ## verbose: verbose output toggle.
  var
    report: CloneRepoReport
    parentPath: string
    dest: string
    initReport: RepoInitReport
    t: tuple[text: string, code: int]
  discard verbose
  report.ok = true
  if url.strip().len == 0:
    report.ok = false
    addLine(report.lines, "Missing clone URL.")
    return report
  parentPath = rootOverride.strip()
  if parentPath.len == 0:
    parentPath = getCurrentDir()
  parentPath = normalizePathValue(parentPath)
  if parentPath.len == 0 or not dirExists(parentPath):
    report.ok = false
    addLine(report.lines, "Clone root does not exist: " & parentPath)
    return report
  dest = ensureCloneTarget(url, parentPath, report)
  if dest.len == 0:
    report.ok = false
    addLine(report.lines, "Clone cancelled.")
    return report
  report.repoPath = dest
  if not dirExists(dest):
    t = runCmd("git clone " & quoteShell(url) & " " & quoteShell(dest))
    if t.code != 0:
      report.ok = false
      addLine(report.lines, "Clone failed: " & t.text.strip())
      return report
    report.cloned = true
    addLine(report.lines, "Cloned repo to " & dest)
  elif isGitRepo(dest):
    addLine(report.lines, "Using existing repo at " & dest)
  else:
    report.ok = false
    addLine(report.lines, "Destination exists but is not a git repo: " & dest)
    return report
  initReport = initRepoLayout(dest, overwriteTemplates)
  if not initReport.ok:
    report.ok = false
    for line in initReport.lines:
      addLine(report.lines, line)
    return report
  for line in initReport.lines:
    addLine(report.lines, line)
  setupSubmodulesAfterClone(dest, report)
  result = report
