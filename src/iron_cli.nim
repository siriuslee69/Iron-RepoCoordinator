# iron Tooling | CLI entrypoint
# Thin main module for the CLI binary.

import interfaces/frontend/cli/app_cli

when isMainModule:
  quit(runCli())
