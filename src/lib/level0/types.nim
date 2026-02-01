# Valkyrie Tooling | base types
# Shared configuration and command definitions.

type
  ToolingCommand* = enum
    tcHelp,
    tcStatus,
    tcScan,
    tcRepos,
    tcVersion
  ToolingConfig* = object
    rootDir*: string
    verbose*: bool
