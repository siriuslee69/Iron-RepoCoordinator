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
import lib/level1/pushall
import lib/level1/repo_health
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
