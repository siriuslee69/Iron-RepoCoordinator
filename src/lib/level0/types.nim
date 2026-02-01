# Valkyrie Tooling | base types
# Shared configuration and command definitions.

type
  ToolingCommand* = enum
    tcHelp,
    tcStatus,
    tcScan,
    tcRepos,
    tcExpand,
    tcRefresh,
    tcPushAll,
    tcVersion
  ToolingConfig* = object
    rootDir*: string
    verbose*: bool
  RepoInfo* = object
    name*: string
    path*: string
    hasGit*: bool
    hasSubmodules*: bool
    hasValkyrie*: bool
