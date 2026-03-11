# ==================================================
# | iron Repo Coordinator Push-All Helper     |
# |------------------------------------------------|
# | Commit and push repos under the selected root. |
# ==================================================

import std/[algorithm, os, osproc, strutils, terminal]
import ../level0/repo_utils
import commit_message_builder
include ../level0/metaPragmas


type
  PushAllReport* = object
    ok*: bool
    repos*: int
    committed*: int
    pushed*: int
    lines*: seq[string]

  PushAllRepoTruth = object
    path: string
    owner: string
    remoteUrl: string
    isGit: bool
    isSubmodule: bool
    hasRemote: bool
    hasChanges: bool
    hasAheadCommits: bool

  PushAllTruthState = object
    root: string
    configRoot: string
    configPath: string
    config: CoordinatorConfig
    repos: seq[string]
    repoTruths: seq[PushAllRepoTruth]
    detectedOwners: seq[tuple[owner: string, count: int]]

const
  ColorRepo = "\e[36m"
  ColorCommit = "\e[33m"
  ColorReset = "\e[0m"


proc addLine(L: var seq[string], t: string) {.role(helper).} =
  ## L: line buffer.
  ## t: line to append.
  L.add(t)

proc supportsColor(): bool {.role(parser).} =
  ## returns whether stdout can render ANSI colors.
  result = isatty(stdout)

proc colorizeText(t: string, c: string): string {.role(helper).} =
  ## t: text to colorize.
  ## c: ANSI color prefix.
  if t.len == 0 or not supportsColor():
    return t
  result = c & t & ColorReset

proc readRepoName(r: string): string {.role(parser).} =
  ## r: repo path to summarize.
  result = lastPathPart(r)
  if result.len == 0:
    result = r

proc formatRepoLabel(r: string): string {.role(helper).} =
  ## r: repo path to render in pushall output.
  var
    name: string
  name = readRepoName(r)
  if name == r:
    return colorizeText(name, ColorRepo)
  result = colorizeText(name, ColorRepo) & " (" & r & ")"

proc formatCommitLabel(msg: string): string {.role(helper).} =
  ## msg: commit message to render in pushall output.
  if msg.len == 0:
    return "No changes"
  result = colorizeText(msg, ColorCommit)

proc formatRepoOutcome(repo: string, detail: string): string {.role(helper).} =
  ## repo: repo path for the outcome.
  ## detail: status or message to append.
  result = formatRepoLabel(repo) & " | " & detail

proc ownerRootRepoExcluded*(repoPath: string, owner: string): bool {.role(parser).} =
  ## repoPath: repo path to test against the selected owner name.
  ## owner: selected owner/user string.
  var
    repoName: string
    ownerName: string
  repoName = readRepoName(repoPath).strip().toLowerAscii()
  ownerName = owner.strip().toLowerAscii()
  if repoName.len == 0 or ownerName.len == 0:
    return false
  result = repoName == ownerName

proc readPushAllPromptInput*(t: string): tuple[confirmed: bool, confirmAll: bool] {.role(parser).} =
  ## t: raw interactive pushall confirmation input.
  var
    v: string
  v = t.strip().toLowerAscii()
  if v.len == 0:
    return (true, false)
  if v == "all":
    return (true, true)
  result = (false, false)

proc confirmPushAllAction(msg: string, autoConfirmAll: var bool): bool {.role(actor).} =
  ## msg: prompt text.
  ## autoConfirmAll: sticky pushall confirmation state for remaining repos.
  var
    input: string
    decision: tuple[confirmed: bool, confirmAll: bool]
  if isTruthyEnv("IRON_ASSUME_YES"):
    echo msg & " [auto-confirmed by IRON_ASSUME_YES]"
    return true
  if autoConfirmAll:
    echo msg & " [auto-confirmed by all]"
    return true
  if not isatty(stdin):
    echo msg & " (non-interactive; aborting)"
    return false
  stdout.write(msg &
      " Press ENTER to continue, type 'all' to continue remaining commits/pushes, anything else aborts: ")
  stdout.flushFile()
  try:
    input = stdin.readLine()
  except EOFError:
    echo ""
    return false
  except IOError:
    echo ""
    return false
  decision = readPushAllPromptInput(input)
  if decision.confirmAll:
    autoConfirmAll = true
  result = decision.confirmed

proc noteAutoConfirmEnabled(L: var seq[string], previous: bool, current: bool) {.role(actor).} =
  ## L: report line buffer.
  ## previous: prior sticky confirmation state.
  ## current: current sticky confirmation state.
  if not previous and current:
    addLine(L, "Auto-confirming remaining commit and push prompts for this run.")

proc emitCommitTruth(L: var seq[string], t: CommitMessageTruthState) {.role(actor).} =
  ## L: report line buffer.
  ## t: commit message truth state to show before prompting.
  for line in renderCommitTruthLines(t):
    echo "  " & line
    addLine(L, "  " & line)

proc runCmd(c: string): tuple[text: string, code: int] {.role(actor).} =
  ## c: command to execute.
  var
    tText: string
    tCode: int
  (tText, tCode) = execCmdEx(c)
  result = (tText, tCode)

proc runGit(r: string, a: string): tuple[text: string, code: int] {.role(actor).} =
  ## r: repo path.
  ## a: git arguments to execute.
  var
    c: string
  c = "git -c submodule.recurse=false -C " & quoteShell(r) & " " & a
  result = runCmd(c)

proc isGitRepo(r: string): bool {.role(parser).} =
  ## r: repo path to validate.
  var
    t: tuple[text: string, code: int]
  t = runGit(r, "rev-parse --is-inside-work-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc isSubmoduleRepo(r: string): bool {.role(parser).} =
  ## r: repo path to check for submodule context.
  var
    t: tuple[text: string, code: int]
  t = runGit(r, "rev-parse --show-superproject-working-tree")
  result = t.code == 0 and t.text.strip().len > 0

proc hasRemote(r: string): bool {.role(parser).} =
  ## r: repo path to check for remotes.
  var
    t: tuple[text: string, code: int]
  t = runGit(r, "remote")
  result = t.code == 0 and t.text.strip().len > 0

proc hasChanges(r: string): bool {.role(parser).} =
  ## r: repo path to check for local changes.
  var
    t: tuple[text: string, code: int]
  t = runGit(r, "status --porcelain --ignore-submodules=dirty")
  result = t.code == 0 and t.text.strip().len > 0

proc hasAheadCommits(r: string): bool {.role(parser).} =
  ## r: repo path to check for local commits ahead of origin.
  var
    t: tuple[text: string, code: int]
    line: string
  t = runGit(r, "status --porcelain --branch --ignore-submodules=dirty")
  if t.code != 0:
    return false
  for raw in t.text.splitLines():
    line = raw.strip()
    if line.startsWith("##") and line.contains("ahead"):
      return true
  result = false

proc needsPushWork(r: string): bool {.role(helper).} =
  ## r: repo path to check for local commit or push work.
  result = hasChanges(r) or hasAheadCommits(r)

proc getChangedFiles(r: string): seq[string] {.role(helper).} =
  ## r: repo path to list changed files.
  var
    t: tuple[text: string, code: int]
    lines: seq[string]
    p: string
  t = runGit(r, "status --porcelain --ignore-submodules=dirty")
  if t.code != 0 or t.text.strip().len == 0:
    return @[]
  lines = t.text.splitLines()
  for s in lines:
    if s.len < 4:
      continue
    p = s[3 .. ^1].strip()
    if p.len > 0:
      result.add(p)

proc runAddCommit(r: string, m: string): int {.role(actor).} =
  ## r: repo path to commit.
  ## m: commit message.
  var
    c1: string
    c2: string
    ec: int
  c1 = "git -c submodule.recurse=false -C " & quoteShell(r) & " add -A ."
  c2 = "git -c submodule.recurse=false -C " & quoteShell(r) & " commit -m " & quoteShell(m)
  ec = execCmd(c1)
  if ec != 0:
    return ec
  result = execCmd(c2)

proc runPush(r: string): int {.role(actor).} =
  ## r: repo path to push.
  var
    c: string
  c = "git -c submodule.recurse=false -C " & quoteShell(r) &
      " push --recurse-submodules=no"
  result = execCmd(c)

proc runFetch(r: string): int {.role(actor).} =
  ## r: repo path to fetch.
  var
    c: string
  c = "git -c submodule.recurse=false -C " & quoteShell(r) &
      " fetch --no-recurse-submodules"
  result = execCmd(c)

proc removeIndexLock(r: string): bool {.role(actor).} =
  ## r: repo path where a stale index.lock may exist.
  var
    p: string
  p = joinPath(r, ".git", "index.lock")
  if not fileExists(p):
    return true
  try:
    removeFile(p)
    return true
  except OSError:
    return false

proc trackedFileCount(r: string): int {.role(helper).} =
  ## r: repo path to count tracked files for duplicate selection.
  var
    t: tuple[text: string, code: int]
  t = runGit(r, "ls-files")
  if t.code != 0:
    return 0
  for line in t.text.splitLines():
    if line.strip().len > 0:
      inc result

proc readHeadEpoch(r: string): int64 {.role(parser).} =
  ## r: repo path to read the current commit timestamp.
  var
    t: tuple[text: string, code: int]
    raw: string
  t = runGit(r, "show -s --format=%ct HEAD")
  if t.code != 0:
    return 0
  raw = t.text.strip()
  try:
    result = parseBiggestInt(raw)
  except ValueError:
    result = 0

proc choosePreferredRepo(A: seq[string], u: string): string {.role(helper).} =
  ## A: candidate repos with the same remote.
  ## u: normalized remote URL.
  var
    remoteTail: string
    repo: string
    name: string
    best: string
    score: int
    bestScore: int
    files: int
    bestFiles: int
    ts: int64
    bestTs: int64
  bestScore = low(int)
  bestFiles = low(int)
  bestTs = low(int64)
  remoteTail = extractRepoTail(u)
  for rawRepo in A:
    repo = normalizePathValue(rawRepo)
    name = lastPathPart(repo).toLowerAscii()
    score = 0
    if remoteTail.len > 0 and name == remoteTail:
      score = score + 100
    files = trackedFileCount(repo)
    ts = readHeadEpoch(repo)
    if score > bestScore or
       (score == bestScore and files > bestFiles) or
       (score == bestScore and files == bestFiles and ts > bestTs):
      best = repo
      bestScore = score
      bestFiles = files
      bestTs = ts
  result = best

proc addOwnerCount(C: var seq[tuple[owner: string, count: int]], o: string) {.role(helper).} =
  ## C: owner count list.
  ## o: owner to increment.
  var
    i: int
  if o.len == 0:
    return
  i = 0
  while i < C.len:
    if C[i].owner == o:
      C[i].count = C[i].count + 1
      return
    inc i
  C.add((o, 1))

proc readRootChoice(here: string, parent: string): tuple[root: string, repos: seq[string], configRoot: string] {.role(parser).} =
  ## here: current directory.
  ## parent: parent directory.
  var
    rsHere: seq[string]
    rsParent: seq[string]
    hereIsRepo: bool
    parentIsRepo: bool
  hereIsRepo = isGitRepo(here)
  parentIsRepo = parent.len > 0 and dirExists(parent) and isGitRepo(parent)
  rsHere = collectRepos(@[here])
  if parent.len > 0 and dirExists(parent):
    rsParent = collectRepos(@[parent])
  if hereIsRepo or rsHere.len > 0:
    result.root = here
    result.repos = rsHere
  else:
    result.root = parent
    result.repos = rsParent
  if hereIsRepo:
    result.configRoot = here
    return
  if parentIsRepo:
    result.configRoot = parent

proc readRepoTruth(r: string): PushAllRepoTruth {.role(parser).} =
  ## r: repo path to perceive.
  result.path = normalizePathValue(r)
  result.isGit = isGitRepo(result.path)
  if not result.isGit:
    return
  result.isSubmodule = isSubmoduleRepo(result.path)
  result.hasRemote = hasRemote(result.path)
  if not result.hasRemote:
    return
  result.remoteUrl = normalizeRemoteUrl(readOriginUrl(result.path))
  result.owner = resolveRepoOwner(result.path)
  result.hasChanges = hasChanges(result.path)
  result.hasAheadCommits = hasAheadCommits(result.path)

proc buildPushAllTruthState(): PushAllTruthState {.role(truthBuilder).} =
  ## discovers repo state and the persisted config used by pushall.
  var
    here: string
    parent: string
    rootChoice: tuple[root: string, repos: seq[string], configRoot: string]
    i: int
    truth: PushAllRepoTruth
  here = normalizePathValue(getCurrentDir())
  parent = normalizePathValue(parentDir(getCurrentDir()))
  result.configPath = readGlobalCoordinatorConfigPath()
  if here.len == 0 or not dirExists(here):
    return
  rootChoice = readRootChoice(here, parent)
  result.root = rootChoice.root
  result.repos = rootChoice.repos
  result.configRoot = rootChoice.configRoot
  result.config = readCoordinatorConfig(result.configRoot)
  i = 0
  while i < result.repos.len:
    truth = readRepoTruth(result.repos[i])
    result.repoTruths.add(truth)
    if truth.isGit and not truth.isSubmodule and truth.hasRemote and
        not repoExcluded(result.config, truth.path) and
        not ownerRootRepoExcluded(truth.path, truth.owner):
      addOwnerCount(result.detectedOwners, truth.owner)
    inc i
  result.detectedOwners.sort(proc(a, b: tuple[owner: string, count: int]): int =
    result = system.cmp(b.count, a.count)
  )

proc confirmFetchPush(autoConfirmAll: var bool): bool {.role(actor).} =
  ## Ask user to confirm fetch+push.
  result = confirmPushAllAction("Fetch and push repos under the selected root?", autoConfirmAll)

proc promptManualOwner(): string {.role(actor).} =
  ## asks the user for an owner string.
  result = promptText("Enter owner: ").strip().toLowerAscii()
  if result.len == 0:
    return ""
  if not confirmEnter("Use owner `" & result & "`?"):
    result = ""

proc configureOwner(S: var PushAllTruthState, R: var PushAllReport): string {.role(helper).} =
  ## S: push truth state.
  ## R: report accumulator.
  var
    options: seq[string]
    idx: int
    owner: string
    i: int
  if not isatty(stdin):
    R.ok = false
    addLine(R.lines, "No owners configured in " & S.configPath & ".")
    addLine(R.lines, "Run `iron config` interactively to set one.")
    return ""
  i = 0
  while i < S.detectedOwners.len:
    if S.detectedOwners[i].owner.len > 0:
      options.add(S.detectedOwners[i].owner & " (" & $S.detectedOwners[i].count & ")")
    inc i
  options.add("Enter owner manually")
  idx = promptOptionsDefault("Select owner to save in iron config:", options, 0)
  if idx < 0:
    R.ok = false
    addLine(R.lines, "Owner selection cancelled.")
    return ""
  if idx == options.len - 1:
    owner = promptManualOwner()
  else:
    owner = S.detectedOwners[idx].owner
  if owner.len == 0:
    R.ok = false
    addLine(R.lines, "No owner selected.")
    return ""
  S.config.owners = @[owner]
  S.configPath = writeGlobalCoordinatorConfig(S.config)
  addLine(R.lines, "Saved owner `" & owner & "` to " & S.configPath & ".")
  result = owner

proc hasOwnerCount(A: seq[tuple[owner: string, count: int]], o: string): bool {.role(parser).} =
  ## A: owner count list.
  ## o: owner name to test.
  var
    i: int
  i = 0
  while i < A.len:
    if A[i].owner == o:
      return true
    inc i

proc readConfiguredOwnerOptions(S: PushAllTruthState): seq[tuple[owner: string, count: int]] {.role(parser).} =
  ## S: push truth state with detected owners and config.
  var
    i: int
    owner: string
  i = 0
  while i < S.detectedOwners.len:
    if ownerAllowed(S.config, S.detectedOwners[i].owner):
      result.add(S.detectedOwners[i])
    inc i
  i = 0
  while i < S.config.owners.len:
    owner = S.config.owners[i]
    if hasOwnerCount(result, owner):
      inc i
      continue
    result.add((owner, 0))
    inc i

proc resolveTargetOwner(S: var PushAllTruthState, R: var PushAllReport): string {.role(actor).} =
  ## S: push truth state to resolve against config and repo owners.
  ## R: report accumulator.
  var
    options: seq[string]
    owners: seq[tuple[owner: string, count: int]]
    idx: int
    i: int
  if not ownersConfigured(S.config):
    result = configureOwner(S, R)
    return
  owners = readConfiguredOwnerOptions(S)
  if owners.len == 0:
    result = configureOwner(S, R)
    return
  if owners.len == 1:
    result = owners[0].owner
    addLine(R.lines, "Using configured owner: " & result)
    return
  i = 0
  while i < owners.len:
    if owners[i].count > 0:
      options.add(owners[i].owner & " (" & $owners[i].count & ")")
    else:
      options.add(owners[i].owner)
    inc i
  idx = promptOptionsDefault("Select owner to push:", options, 0)
  if idx < 0:
    R.ok = false
    addLine(R.lines, "Owner selection cancelled.")
    return ""
  result = owners[idx].owner

proc buildOwnerRepos(S: PushAllTruthState, owner: string, R: var PushAllReport,
                     skips: var seq[string]): seq[string] {.role(truthBuilder).} =
  ## S: push truth state.
  ## owner: selected owner to push.
  ## R: report log collector.
  ## skips: skip summary lines.
  var
    remoteUrls: seq[string]
    remoteRepos: seq[seq[string]]
    truth: PushAllRepoTruth
    i: int
    idx: int
    preferred: string
  i = 0
  while i < S.repoTruths.len:
    truth = S.repoTruths[i]
    if not truth.isGit:
      skips.add(formatRepoOutcome(truth.path, "Not a git repo"))
      inc i
      continue
    if truth.isSubmodule:
      skips.add(formatRepoOutcome(truth.path, "Submodule repo"))
      inc i
      continue
    if not truth.hasRemote:
      skips.add(formatRepoOutcome(truth.path, "No remotes"))
      inc i
      continue
    if repoExcluded(S.config, truth.path):
      skips.add(formatRepoOutcome(truth.path, "Excluded by config"))
      inc i
      continue
    if ownerRootRepoExcluded(truth.path, owner):
      skips.add(formatRepoOutcome(truth.path, "Owner root repo excluded by default"))
      inc i
      continue
    if truth.owner != owner:
      skips.add(formatRepoOutcome(truth.path, "Owner mismatch (" & truth.owner & ")"))
      inc i
      continue
    if truth.remoteUrl.len == 0:
      skips.add(formatRepoOutcome(truth.path, "Missing origin URL"))
      inc i
      continue
    idx = remoteUrls.find(truth.remoteUrl)
    if idx < 0:
      remoteUrls.add(truth.remoteUrl)
      remoteRepos.add(@[truth.path])
    else:
      remoteRepos[idx].add(truth.path)
    inc i
  i = 0
  while i < remoteUrls.len:
    preferred = choosePreferredRepo(remoteRepos[i], remoteUrls[i])
    if preferred.len > 0:
      result.add(preferred)
      if remoteRepos[i].len > 1:
        addLine(R.lines, "Duplicate remote detected for " & remoteUrls[i] &
              "; using " & formatRepoLabel(preferred))
        for repo in remoteRepos[i]:
          if normalizePathValue(repo) != preferred:
            skips.add(formatRepoOutcome(repo, "Duplicate remote, preferred " & readRepoName(preferred)))
    inc i

proc readPassRepos(A: seq[string]): seq[string] {.role(parser).} =
  ## A: candidate repo paths.
  var
    i: int
  i = 0
  while i < A.len:
    if needsPushWork(A[i]):
      result.add(A[i])
    inc i

proc runRepoPush(repo: string, R: var PushAllReport, success: var seq[string],
                 fails: var seq[string], autoConfirmAll: var bool) {.role(actor).} =
  ## repo: repo path to process.
  ## R: report accumulator.
  ## success: success summary lines.
  ## fails: failure summary lines.
  ## autoConfirmAll: sticky pushall confirmation state for remaining repos.
  var
    files: seq[string]
    msg: string
    msgTruth: CommitMessageTruthState
    previousAutoConfirmAll: bool
  addLine(R.lines, "==> " & formatRepoLabel(repo))
  files = getChangedFiles(repo)
  if files.len > 0:
    addLine(R.lines, "  Changed files: " & files.join(", "))
  if hasChanges(repo):
    if not removeIndexLock(repo):
      addLine(R.lines, "  Could not remove stale index.lock.")
      R.ok = false
      fails.add(formatRepoOutcome(repo, "Stale index.lock"))
      return
    msgTruth = buildCommitMessageTruthState(repo)
    emitCommitTruth(R.lines, msgTruth)
    msg = buildAutomaticCommitMessage(msgTruth)
    addLine(R.lines, "  Commit summary: " &
        formatCommitLabel(readCommitMessageHeadline(msg)))
    previousAutoConfirmAll = autoConfirmAll
    if not confirmPushAllAction(
        "Commit changes in " & formatRepoLabel(repo) & "? Summary: " &
        formatCommitLabel(readCommitMessageHeadline(msg)),
        autoConfirmAll):
      addLine(R.lines, "  Commit cancelled by user.")
      fails.add(formatRepoOutcome(repo, "Commit cancelled"))
      return
    noteAutoConfirmEnabled(R.lines, previousAutoConfirmAll, autoConfirmAll)
    if runAddCommit(repo, msg) != 0:
      addLine(R.lines, "  Commit failed.")
      R.ok = false
      fails.add(formatRepoOutcome(repo, "Commit failed"))
      return
    R.committed = R.committed + 1
  if runFetch(repo) != 0:
    addLine(R.lines, "  Fetch failed.")
    R.ok = false
    fails.add(formatRepoOutcome(repo, "Fetch failed"))
    return
  previousAutoConfirmAll = autoConfirmAll
  if not confirmPushAllAction("Push " & formatRepoLabel(repo) & " to origin?", autoConfirmAll):
    addLine(R.lines, "  Push cancelled by user.")
    fails.add(formatRepoOutcome(repo, "Push cancelled"))
    return
  noteAutoConfirmEnabled(R.lines, previousAutoConfirmAll, autoConfirmAll)
  if runPush(repo) != 0:
    addLine(R.lines, "  Push failed.")
    R.ok = false
    fails.add(formatRepoOutcome(repo, "Push failed"))
    return
  R.pushed = R.pushed + 1
  success.add(formatRepoOutcome(repo,
      formatCommitLabel(readCommitMessageHeadline(msg))))

proc runPushPasses(A: seq[string], R: var PushAllReport,
                   autoConfirmAll: var bool) {.role(orchestrator).} =
  ## A: owner-filtered repo list.
  ## R: report accumulator.
  ## autoConfirmAll: sticky pushall confirmation state for remaining repos.
  var
    passRepos: seq[string]
    success: seq[string]
    fails: seq[string]
    remaining: int
    i: int
  passRepos = readPassRepos(A)
  if passRepos.len == 0:
    addLine(R.lines, "No repos have local changes or ahead commits.")
  else:
    addLine(R.lines, "Processing " & $passRepos.len &
            " repos with local changes or ahead commits.")
    i = 0
    while i < passRepos.len:
      runRepoPush(normalizePathValue(passRepos[i]), R, success, fails, autoConfirmAll)
      inc i
  remaining = 0
  i = 0
  while i < A.len:
    if needsPushWork(A[i]):
      inc remaining
    inc i
  if remaining > 0:
    R.ok = false
    addLine(R.lines, "Repos still needing push after this run: " & $remaining)
  else:
    addLine(R.lines, "No repos remain after this run.")
  addLine(R.lines, "Successful repos: " & $success.len)
  for repo in success:
    addLine(R.lines, "  " & repo)
  addLine(R.lines, "Failed repos: " & $fails.len)
  for repo in fails:
    addLine(R.lines, "  " & repo)

proc pushAllFromParent*(v: bool = false): PushAllReport {.role(orchestrator).} =
  ## v: verbose toggle (currently informational only).
  var
    S: PushAllTruthState
    ownerRepos: seq[string]
    skips: seq[string]
    owner: string
    autoConfirmAll: bool
  discard v
  result.ok = true
  S = buildPushAllTruthState()
  if S.root.len == 0 or not dirExists(S.root):
    result.ok = false
    addLine(result.lines, "Root directory not found.")
    return
  if S.repos.len == 0:
    result.ok = false
    addLine(result.lines, "No repos found under " & S.root & ".")
    return
  addLine(result.lines, "Found " & $S.repos.len & " repos under " & S.root & ".")
  addLine(result.lines, "Global config: " & S.configPath)
  if not fileExists(S.configPath):
    S.configPath = ensureGlobalCoordinatorConfig()
    addLine(result.lines, "Created config file at " & S.configPath & ".")
  if not confirmFetchPush(autoConfirmAll):
    result.ok = false
    addLine(result.lines, "Fetch/push cancelled by user.")
    return
  noteAutoConfirmEnabled(result.lines, false, autoConfirmAll)
  owner = resolveTargetOwner(S, result)
  if owner.len == 0:
    if result.lines.len == 0:
      result.ok = false
      addLine(result.lines, "No owner selected.")
    return
  ownerRepos = buildOwnerRepos(S, owner, result, skips)
  result.repos = ownerRepos.len
  if ownerRepos.len == 0:
    result.ok = false
    addLine(result.lines, "No repos found for owner: " & owner)
    return
  runPushPasses(ownerRepos, result, autoConfirmAll)
  addLine(result.lines, "Skipped repos: " & $skips.len)
  for owner in skips:
    addLine(result.lines, "  " & owner)
  addLine(result.lines, "Committed repos: " & $result.committed)
  addLine(result.lines, "Pushed repos: " & $result.pushed)
