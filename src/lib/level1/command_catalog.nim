# ==================================================
# | iron Tooling Command Catalog               |
# |------------------------------------------------|
# | Shared command metadata for CLI parsing and UI.|
# ==================================================

import std/strutils
import ../level0/types
include ../level0/metaPragmas


proc addSpec(S: var seq[ToolingCommandSpec], c: ToolingCommand, n: string,
             A: seq[string], s: string) {.role(helper).} =
  ## S: command spec list.
  ## c: command enum value.
  ## n: canonical command name.
  ## A: accepted aliases.
  ## s: short help summary.
  var
    t: ToolingCommandSpec
  t.command = c
  t.name = n
  t.aliases = A
  t.summary = s
  S.add(t)

proc readCommandSpecs*(): seq[ToolingCommandSpec] {.role(truthBuilder).} =
  ## returns the supported command catalog.
  var
    S: seq[ToolingCommandSpec]
  addSpec(S, tcHelp, "help", @["help", "-h", "--help"], "Show this help")
  addSpec(S, tcInit, "init", @["init"], "Initialize .iron metadata in a repo")
  addSpec(S, tcClone, "clone", @["clone"], "Clone repo and initialize .iron defaults")
  addSpec(S, tcHealth, "health", @["health"], "Show repo health checks")
  addSpec(S, tcStatus, "status", @["status"], "Show repo status summary")
  addSpec(S, tcScan, "scan", @["scan"], "Scan local repos")
  addSpec(S, tcRepos, "repos", @["repos"], "List known repos")
  addSpec(S, tcTest, "test", @["test", "repotest"], "Pick and run a test task")
  addSpec(S, tcDocsInit, "docs-init",
          @["docs-init", "docsinit", "init-docs", "initdocs"],
          "Create docs + pipeline scaffold files in .iron/")
  addSpec(S, tcDocs, "docs", @["docs", "doc", "gendocs", "generate-docs"],
          "Generate autonomous library docs")
  addSpec(S, tcShow, "show", @["show", "pipeline", "pipeline-show"],
          "Render .iron/pipeline.json as live ASCII tree")
  addSpec(S, tcFind, "find", @["find"],
          "Build local submodule overrides and link sibling repos")
  addSpec(S, tcAutoPull, "autopull", @["autopull"], "Pull all repos under discovered roots")
  addSpec(S, tcAutoPush, "autopush", @["autopush"], "Commit/push current repo")
  addSpec(S, tcExpand, "expand", @["expand"], "Propagate updated submodule across repos")
  addSpec(S, tcExtract, "extract", @["extract", "extract_submodules"],
          "Clone submodules to sibling repos")
  addSpec(S, tcExtractAll, "extract-all",
          @["extract-all", "extract_all", "extract_submodules_global"],
          "Extract submodules for all repos under roots")
  addSpec(S, tcExternalize, "externalize",
          @["externalize", "externalize-submodules", "relink-submodules"],
          "Externalize nested submodules to sibling repos")
  addSpec(S, tcRefresh, "refresh", @["refresh", "submodrefresh"],
          "Stash/pull submodule repos")
  addSpec(S, tcPushAll, "pushall", @["pushall", "autopushall"],
          "Add/commit/push repos under the selected root")
  addSpec(S, tcBranchMode, "branch", @["branch", "branch-mode", "branch_mode"],
          "Switch between main/nightly or promote nightly")
  addSpec(S, tcConflicts, "conflicts", @["conflicts", "conflict"],
          "Interactive merge conflict overview + resolver")
  addSpec(S, tcSyncConventions, "sync-conventions",
          @["sync-conventions", "syncconventions", "conventions-sync",
            "update-conventions", "updateconventions"],
          "Sync .iron/CONVENTIONS.md from Proto-RepoTemplate")
  addSpec(S, tcConfig, "config", @["config", "cfg"],
          "View or edit the persisted iron config")
  addSpec(S, tcVersion, "version", @["version", "-v", "--version"], "Show version")
  result = S

proc readCommandSpec*(c: ToolingCommand): ToolingCommandSpec {.role(parser).} =
  ## c: command enum to look up.
  var
    A: seq[ToolingCommandSpec]
    i: int
  A = readCommandSpecs()
  i = 0
  while i < A.len:
    if A[i].command == c:
      result = A[i]
      return
    inc i

proc buildHelp*(): string {.role(actor).} =
  ## returns CLI help text.
  var
    S: seq[ToolingCommandSpec]
    L: seq[string]
    i: int
  S = readCommandSpecs()
  L = @[
    "iron Tooling CLI",
    "",
    "Usage:",
    "  iron <command> [flags]",
    "  iron_cli <command> [flags]",
    "",
    "Commands:"
  ]
  i = 0
  while i < S.len:
    L.add("  " & alignLeft(S[i].name, 15) & S[i].summary)
    inc i
  L.add("")
  L.add("Flags:")
  L.add("  --verbose                              Show extra repo details")
  L.add("  --overwrite                            Overwrite scaffold/template files")
  L.add("  --repo <path> or --repo=<path>         Target repo for repo commands")
  L.add("  --root <path> or --root=<path>         Override root for clone/extract/conflicts")
  L.add("  --mode <main|nightly|promote>          Branch mode action")
  L.add("  --src <path> or --src=<path>           Source path for docs generation")
  L.add("  --docs-out <path> or --docs-out=<path> Markdown output for docs")
  L.add("  --pipeline <path> or --pipeline=<path> Pipeline JSON for show")
  L.add("  --replace                              Replace clone targets when extracting")
  L.add("  --dry-run                              Do not modify repositories")
  L.add("  --once                                 Render one show frame and exit")
  L.add("  --loops <int>                          Max show frames (0 = unbounded)")
  L.add("  --interval-ms <int>                    Show refresh interval in ms")
  L.add("  --owners <csv>                         Replace configured owners in iron config")
  L.add("  --owner <name>                         Alias for setting one owner")
  L.add("  --add-owner <name>                     Add one owner to iron config")
  L.add("  --remove-owner <name>                  Remove one owner from iron config")
  L.add("  --exclude-repos <csv>                  Replace excluded repos in iron config")
  L.add("  --add-exclude <repo>                   Add one excluded repo name/path")
  L.add("  --remove-exclude <repo>                Remove one excluded repo name/path")
  L.add("  --foreign-mode <update|skip>           Set foreign owner behavior in iron config")
  L.add("")
  L.add("Environment:")
  L.add("  IRON_ROOTS          Roots (Windows ';' or POSIX ':')")
  L.add("  IRON_VERBOSE=1      Enable verbose output")
  L.add("  IRON_ASSUME_YES=1   Auto-confirm ENTER prompts and menu confirmations")
  result = L.join("\n")
