# ==================================================
# | Valkyrie Repo Coordination Backend Core        |
# |------------------------------------------------|
# | Core context placeholders for repo utilities.  |
# ==================================================


type
  RepoCoordinatorContext* = object
    name*: string
    root*: string
    status*: string

proc initRepoCoordinator*(n, r: string): RepoCoordinatorContext =
  ## n: coordinator name tag.
  ## r: default root path for scans.
  var c: RepoCoordinatorContext
  c.name = n
  c.root = r
  c.status = "ready"
  result = c

proc describeRepoCoordinator*(c: RepoCoordinatorContext): string =
  ## c: coordinator context to describe.
  var t: string = "Coordinator " & c.name & " (" & c.root & ") is " & c.status
  result = t
