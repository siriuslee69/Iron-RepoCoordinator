# ==================================================
# | iron Tooling Repo Coordinator Smoke Tests  |
# |------------------------------------------------|
# | Quick sanity checks for integrated coordinator |
# | logic.                                         |
# ==================================================

import std/[os, osproc, random, strutils, times, unittest]
import interfaces/backend/core
import lib/level0/repo_utils
import lib/level1/commit_message_builder
import lib/level1/conventions_sync
import lib/level1/pushall
import lib/level1/repo_health
import lib/level1/repo_bootstrap
import lib/level1/test_picker


proc newTempRoot(p: string): string =
  var
    tBase: string
    tStamp: string
    tRand: int
  randomize()
  tBase = getTempDir()
  tStamp = $getTime().toUnix()
  tRand = rand(1_000_000)
  result = joinPath(tBase, p & "_" & tStamp & "_" & $tRand)
  createDir(result)

proc removeTree(p: string) =
  var
    tEntries: seq[(PathComponent, string)]
    tKind: PathComponent
    tPath: string
    i: int
  if not dirExists(p):
    return
  for tKind, tPath in walkDir(p):
    tEntries.add((tKind, tPath))
  i = tEntries.len - 1
  while i >= 0:
    tKind = tEntries[i][0]
    tPath = tEntries[i][1]
    case tKind
    of pcFile, pcLinkToFile:
      removeFile(tPath)
    of pcDir:
      removeDir(tPath)
    else:
      discard
    dec i
  if dirExists(p):
    removeDir(p)

proc runGitOk(repoPath: string, args: string): string =
  let (tText, tCode) = execCmdEx(
      "git -c init.defaultBranch=main -C " & quoteShell(repoPath) & " " & args)
  if tCode != 0:
    raise newException(IOError, "git failed: " & args & "\n" & tText)
  result = tText


suite "embedded repo coordinator":
  test "init":
    var c: RepoCoordinatorContext = initRepoCoordinator("iron", "/tmp")
    check c.name == "iron"
    check c.root == "/tmp"
    check c.status == "ready"

  test "extractRepoTail variants":
    check extractRepoTail("https://github.com/user/Repo.git") == "repo"
    check extractRepoTail("git@github.com:user/Repo.git") == "repo"
    check extractRepoTail("F:/CodingMain/Repo") == "repo"

  test "mergeSubmodules upsert":
    var
      a: SubmoduleInfo
      b: SubmoduleInfo
      c: SubmoduleInfo
      ms: seq[SubmoduleInfo]
      ns: seq[SubmoduleInfo]
      tOut: seq[SubmoduleInfo]
    a.name = "Alpha"
    a.path = "submodules/Alpha"
    a.url = "https://example.com/alpha.git"
    b.name = "Beta"
    b.path = "submodules/Beta"
    b.url = "https://example.com/beta.git"
    c.name = "Alpha"
    c.path = "submodules/Alpha"
    c.url = "F:/CodingMain/Alpha"
    ms = @[a, b]
    ns = @[c]
    tOut = mergeSubmodules(ms, ns)
    check tOut.len == 2
    check tOut[0].name == "Alpha"
    check tOut[0].url == "F:/CodingMain/Alpha"

  test "buildMappings small and overflow":
    var ms: seq[string]
    ms = buildMappings(3)
    check ms.len == 3
    check ms[0] == "a"
    check ms[1] == "s"
    check ms[2] == "d"
    ms = buildMappings(8)
    check ms.len == 8
    check ms[7] == "aa"

  test "parse status counts":
    var
      ls: seq[string]
      t: tuple[staged: int, modified: int, untracked: int]
    ls = @[
      " M src/main.nim",
      "A  README.md",
      "?? notes.txt",
      "MM config.nims"
    ]
    t = parseStatusCountsFromLines(ls)
    check t.modified == 2
    check t.staged == 2
    check t.untracked == 1

  test "foreign mode normalize":
    check normalizeForeignMode("update") == "update"
    check normalizeForeignMode("skip") == "skip"
    check normalizeForeignMode("whatever") == "skip"

  test "repo exclusion matches name and path":
    var c: CoordinatorConfig
    c = defaultCoordinatorConfig()
    c.excludedRepos = normalizeExcludedRepoList(@["RepoA", "F:/CodingMain/RepoB"])
    check repoExcluded(c, "F:/CodingMain/RepoA")
    check repoExcluded(c, "F:/CodingMain/RepoB")
    check not repoExcluded(c, "F:/CodingMain/RepoC")

  test "owner root repo excluded by default":
    check ownerRootRepoExcluded("F:/CodingMain/siriuslee69", "siriuslee69")
    check ownerRootRepoExcluded("F:/CodingMain/siriuslee69", "SiriusLee69")
    check not ownerRootRepoExcluded("F:/CodingMain/RepoA", "siriuslee69")

  test "pushall prompt input accepts all":
    var
      t: tuple[confirmed: bool, confirmAll: bool]
    t = readPushAllPromptInput("")
    check t.confirmed
    check not t.confirmAll
    t = readPushAllPromptInput("all")
    check t.confirmed
    check t.confirmAll
    t = readPushAllPromptInput("All")
    check t.confirmed
    check t.confirmAll
    t = readPushAllPromptInput("no")
    check not t.confirmed
    check not t.confirmAll

  test "sync iron file copies selected canonical metadata":
    var
      tRoot: string
      tTemplateRepo: string
      tTargetRepo: string
      tTemplateMeta: string
      tTargetMeta: string
      tSourceText: string
      report: IronFileSyncReport
      files: seq[string]
    tRoot = newTempRoot("iron_sync")
    try:
      tTemplateRepo = joinPath(tRoot, "Proto-RepoTemplate")
      tTargetRepo = joinPath(tRoot, "RepoA")
      tTemplateMeta = joinPath(tTemplateRepo, ".iron")
      tTargetMeta = joinPath(tTargetRepo, ".iron")
      createDir(tTemplateRepo)
      createDir(tTargetRepo)
      createDir(tTemplateMeta)
      createDir(tTargetMeta)
      createDir(joinPath(tTemplateRepo, ".git"))
      createDir(joinPath(tTargetRepo, ".git"))
      createDir(joinPath(tTemplateMeta, "docs"))
      tSourceText = "name = \"Template Pipeline\"\nroot_id = \"plan\"\n\n[[nodes]]\nid = \"plan\"\nlabel = \"Plan\"\nstatus = \"todo\"\nparent = \"\"\n"
      writeFile(joinPath(tTemplateMeta, "pipeline.toml"), tSourceText)
      writeFile(joinPath(tTemplateMeta, "conventions.md"), "# conventions\n")
      writeFile(joinPath(tTemplateMeta, "progress.md"), "# progress\n")
      writeFile(joinPath(tTemplateMeta, ".local.config.toml"), "x = 1\n")
      writeFile(joinPath(tTemplateMeta, "docs", "library_api.md"), "# docs\n")
      writeFile(joinPath(tTargetMeta, "pipeline.toml"), "name = \"Old\"\n")

      files = readSyncableIronFiles(tRoot)
      check files.contains("conventions.md")
      check files.contains("pipeline.toml")
      check not files.contains("progress.md")
      check not files.contains(".local.config.toml")
      check not files.contains("docs/library_api.md")

      putEnv("IRON_ASSUME_YES", "1")
      report = syncIronFileFromRoots(tRoot, "pipeline.toml")
      delEnv("IRON_ASSUME_YES")

      check report.ok
      check report.relativePath == "pipeline.toml"
      check fileExists(joinPath(tTargetMeta, "pipeline.toml"))
      check readFile(joinPath(tTargetMeta, "pipeline.toml")) == tSourceText
    finally:
      delEnv("IRON_ASSUME_YES")
      removeTree(tRoot)

  test "clone copies canonical iron tree and root docs":
    var
      tRoot: string
      tTemplateRepo: string
      tTemplateMeta: string
      tRemoteRoot: string
      tSourceRepo: string
      tCloneRoot: string
      tClonedRepo: string
      report: CloneRepoReport
    tRoot = newTempRoot("iron_clone_bootstrap")
    try:
      tTemplateRepo = joinPath(tRoot, "Proto-RepoTemplate")
      tTemplateMeta = joinPath(tTemplateRepo, ".iron")
      tRemoteRoot = joinPath(tRoot, "remote")
      tSourceRepo = joinPath(tRemoteRoot, "ExampleRepo")
      tCloneRoot = joinPath(tRoot, "clones")
      tClonedRepo = joinPath(tCloneRoot, "ExampleRepo")

      createDir(tTemplateRepo)
      createDir(tTemplateMeta)
      createDir(joinPath(tTemplateMeta, "nested"))
      writeFile(joinPath(tTemplateMeta, "CONVENTIONS.md"), "# template conventions\n")
      writeFile(joinPath(tTemplateMeta, "PROGRESS.md"), "# template progress\n")
      writeFile(joinPath(tTemplateMeta, ".local.config.toml"), "root = \"F:/CodingMain\"\n")
      writeFile(joinPath(tTemplateMeta, ".local.config.toml.template"), "root = \"C:/ChangeMe/CodingMain\"\n")
      writeFile(joinPath(tTemplateMeta, ".local.gitmodules.toml.template"), "[\"submodules/MySubmodule\"]\n")
      writeFile(joinPath(tTemplateMeta, "metaPragmas.nim"), "template role*(x: untyped): untyped = x\n")
      writeFile(joinPath(tTemplateMeta, "nested", "future_tool.nim"), "discard\n")
      writeFile(joinPath(tTemplateRepo, "README.md"), "# Template README\n")
      writeFile(joinPath(tTemplateRepo, "CONTRIBUTING.md"), "# Template CONTRIBUTING\n")
      writeFile(joinPath(tTemplateRepo, "UNLICENSE"), "Template UNLICENSE\n")

      createDir(tRemoteRoot)
      createDir(tSourceRepo)
      discard runGitOk(tSourceRepo, "init")
      discard runGitOk(tSourceRepo, "config user.email codex@example.com")
      discard runGitOk(tSourceRepo, "config user.name Codex")
      createDir(joinPath(tSourceRepo, "src"))
      writeFile(joinPath(tSourceRepo, "src", "sample.nim"), "discard\n")
      discard runGitOk(tSourceRepo, "add -A .")
      discard runGitOk(tSourceRepo, "commit -m init")

      createDir(tCloneRoot)
      report = cloneRepoWithiron(tSourceRepo, tCloneRoot, false, false)

      check report.ok
      check fileExists(joinPath(tClonedRepo, ".iron", "CONVENTIONS.md"))
      check fileExists(joinPath(tClonedRepo, ".iron", "PROGRESS.md"))
      check fileExists(joinPath(tClonedRepo, ".iron", ".local.config.toml"))
      check fileExists(joinPath(tClonedRepo, ".iron", "metaPragmas.nim"))
      check fileExists(joinPath(tClonedRepo, ".iron", "nested", "future_tool.nim"))
      check readFile(joinPath(tClonedRepo, ".iron", "metaPragmas.nim")) ==
        "template role*(x: untyped): untyped = x\n"
      check readFile(joinPath(tClonedRepo, "README.md")) == "# Template README\n"
      check readFile(joinPath(tClonedRepo, "CONTRIBUTING.md")) == "# Template CONTRIBUTING\n"
      check readFile(joinPath(tClonedRepo, "UNLICENSE")) == "Template UNLICENSE\n"
    finally:
      removeTree(tRoot)

  test "commit keyword stays short and discerning":
    var
      t: CommitMessageTruthState
    t.docsFiles = 2
    check readCommitKeyword(t) == "Doc change"
    check buildAutomaticCommitMessage(t) == "- Doc change"

    t = CommitMessageTruthState()
    t.docsFiles = 4
    check readCommitKeyword(t) == "Doc sweep"

    t = CommitMessageTruthState()
    t.configFiles = 3
    check readCommitKeyword(t) == "Config sweep"

    t = CommitMessageTruthState()
    t.docsFiles = 2
    t.configFiles = 2
    check readCommitKeyword(t) == "Metadata sweep"

    t = CommitMessageTruthState()
    t.nimFiles = 1
    t.renameOnlyFiles = 1
    t.touchedFunctionCount = 1
    check readCommitKeyword(t) == "Small rename"

    t = CommitMessageTruthState()
    t.nimFiles = 2
    t.touchedFunctionCount = 4
    check readCommitKeyword(t) == "API sweep"
    check buildAutomaticCommitMessage(t) == "- API sweep"

    t = CommitMessageTruthState()
    t.nimFiles = 1
    t.docsFiles = 1
    t.touchedFunctionCount = 1
    check readCommitKeyword(t) == "Code + docs"

    t = CommitMessageTruthState()
    t.otherFiles = 4
    check readCommitKeyword(t) == "Project sweep"

    check normalizeSyntaxShape(
      "proc renameThing*(value: int): int {.role(actor), risk(low), tags({cli}).} = value + leftPad"
    ) == normalizeSyntaxShape(
      "proc swapName*(item: int): int {.role(actor), risk(low), tags({cli}).} = item + rightPad"
    )

  test "commit truth prints touched function metadata and short summary":
    var
      tRoot: string
      truth: CommitMessageTruthState
      msg: string
      lines: seq[string]
    tRoot = newTempRoot("iron_commit_truth")
    try:
      discard runGitOk(tRoot, "init")
      discard runGitOk(tRoot, "config user.email codex@example.com")
      discard runGitOk(tRoot, "config user.name Codex")
      writeFile(joinPath(tRoot, "sample.nim"), """
proc calculateValue*(value: int): int {.role(actor), risk(medium), tags({cli, commit}).} =
  result = value + 1

proc helperValue*(value: int): int {.role(parser), risk(low), tags({internal}).} =
  result = value
""")
      discard runGitOk(tRoot, "add -A .")
      discard runGitOk(tRoot, "commit -m init")

      writeFile(joinPath(tRoot, "sample.nim"), """
proc calculateValue*(value: int): int {.role(actor), risk(medium), tags({cli, commit}).} =
  result = value + 2

proc helperValue*(value: int): int {.role(parser), risk(low), tags({internal}).} =
  result = value
""")

      truth = buildCommitMessageTruthState(tRoot)
      msg = buildAutomaticCommitMessage(truth)
      lines = renderCommitTruthLines(truth)

      check truth.nimFiles == 1
      check truth.docsFiles == 0
      check truth.configFiles == 0
      check truth.renameOnlyFiles == 0
      check truth.touchedFunctionCount == 1
      check truth.touchedFunctions.len == 1
      check truth.touchedFunctions[0].name == "calculateValue"
      check truth.touchedFunctions[0].role == "actor"
      check truth.touchedFunctions[0].risk == "medium"
      check truth.touchedFunctions[0].tags.contains("cli")
      check readCommitKeyword(truth) == "Function change"
      check msg == "- Function change"
      check lines.join("\n").contains("calculateValue")
      check lines.join("\n").contains("role=actor")
      check lines.join("\n").contains("risk=medium")
      check lines.join("\n").contains("Touched functions: 1")
    finally:
      removeTree(tRoot)
