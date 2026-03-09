# iron Tooling | CLI entrypoint
# Thin main module for the CLI binary.

import cli/level1/cli_runner

when isMainModule:
  quit(runCli())
