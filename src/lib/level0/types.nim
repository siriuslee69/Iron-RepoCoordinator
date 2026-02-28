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
    tcDocsInit,
    tcDocs,
    tcShow,
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
    srcPath*: string
    docsOut*: string
    pipelinePath*: string
    replace*: bool
    dryRun*: bool
    once*: bool
    loops*: int
    intervalMs*: int
    overwrite*: bool
  ToolingConfig* = object
    rootDir*: string
    verbose*: bool
  RepoInfo* = object
    name*: string
    path*: string
    hasGit*: bool
    hasSubmodules*: bool
    hasValkyrie*: bool
