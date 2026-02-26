# ==================================================
# | Valkyrie Tooling Repo Coordination Smoke Tests |
# |------------------------------------------------|
# | Quick sanity checks for integrated repo logic. |
# ==================================================

import std/unittest
import valkyrie_repo_coordination/backend/core
import valkyrie_repo_coordination/level0/repo_utils
import valkyrie_repo_coordination/level1/repo_health
import valkyrie_repo_coordination/level1/test_picker


suite "repo coordination":
  test "init":
    var c: RepoCoordinatorContext = initRepoCoordinator("Valkyrie", "/tmp")
    check c.name == "Valkyrie"
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
