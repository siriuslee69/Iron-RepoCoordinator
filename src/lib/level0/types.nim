# iron Tooling | base types
# Shared configuration and command definitions.

type
  ToolingCommand* = enum
    tcHelp,
    tcInit,
    tcClone,
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
    tcExternalize,
    tcFind,
    tcAutoPull,
    tcAutoPush,
    tcRefresh,
    tcPushAll,
    tcBranchMode,
    tcConflicts,
    tcSyncConventions,
    tcConfig,
    tcVersion
  ToolingOptions* = object
    repo*: string
    root*: string
    mode*: string
    cloneUrl*: string
    srcPath*: string
    docsOut*: string
    pipelinePath*: string
    replace*: bool
    dryRun*: bool
    once*: bool
    loops*: int
    intervalMs*: int
    overwrite*: bool
    configOwners*: string
    configAddOwner*: string
    configRemoveOwner*: string
    configForeignMode*: string
  ToolingConfig* = object
    rootDir*: string
    verbose*: bool
  RepoInfo* = object
    name*: string
    path*: string
    hasGit*: bool
    hasSubmodules*: bool
    hasiron*: bool
  ToolingCommandSpec* = object
    command*: ToolingCommand
    name*: string
    aliases*: seq[string]
    summary*: string
  ToolingCommandInput* = object
    args*: seq[string]
    commandToken*: string
    commandIndex*: int
    hasCommand*: bool
  ToolingCommandTruth* = object
    input*: ToolingCommandInput
    command*: ToolingCommand
    recognized*: bool
    cancelled*: bool
    message*: string
    suggestions*: seq[ToolingCommandSpec]
