# ==================================================
# | iron Repo Coordinator Backend Core      |
# |------------------------------------------------|
# | Core context placeholders for repo utilities.  |
# ==================================================


include ../../lib/level0/metaPragmas
type
  RepoCoordinatorContext* = object
    name*: string
    root*: string
    status*: string

proc initRepoCoordinator*(n, r: string): RepoCoordinatorContext {.role(truthBuilder).} =
  ## n: coordinator name tag.
  ## r: default root path for scans.
  var c: RepoCoordinatorContext
  c.name = n
  c.root = r
  c.status = "ready"
  result = c

proc describeRepoCoordinator*(c: RepoCoordinatorContext): string {.role(actor).} =
  ## c: coordinator context to describe.
  var t: string = "Coordinator " & c.name & " (" & c.root & ") is " & c.status
  result = t
