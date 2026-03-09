# iron Tooling | primary CLI entrypoint
# Thin main module for the `iron` binary.

import cli/level1/cli_runner

when isMainModule:
  quit(runCli())
