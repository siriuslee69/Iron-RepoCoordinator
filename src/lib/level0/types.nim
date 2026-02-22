# Valkyrie Tooling | base types
# Shared configuration and command definitions.

type
  ToolingCommand* = enum
    tcHelp,
    tcHealth,
    tcStatus,
    tcScan,
    tcRepos,
    tcTest,
    tcExpand,
    tcExtract,
    tcExtractAll,
    tcFind,
    tcAutoPull,
    tcAutoPush,
    tcRefresh,
    tcPushAll,
    tcBranchMode,
    tcVersion
  ToolingOptions* = object
    repo*: string
    root*: string
    mode*: string
    replace*: bool
    dryRun*: bool
  ToolingConfig* = object
    rootDir*: string
    verbose*: bool
  RepoInfo* = object
    name*: string
    path*: string
    hasGit*: bool
    hasSubmodules*: bool
    hasValkyrie*: bool
