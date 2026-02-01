# Valkyrie Tooling | CLI alias
# Entrypoint for the short "val" command.

import cli/level1/cli_runner

when isMainModule:
  quit(runCli())
