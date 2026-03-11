# iron Tooling | primary CLI entrypoint
# Thin main module for the `iron` binary.

import interfaces/frontend/cli/app_cli

when isMainModule:
  quit(runCli())
