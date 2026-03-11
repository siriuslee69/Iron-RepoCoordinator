# ==================================================
# | iron Repo Coordinator Submodule Sync     |
# |------------------------------------------------|
# | Compare nested submodule clones against        |
# | sibling repos, then externalize them via       |
# | local links and .local.gitmodules.toml.        |
# ==================================================

import std/[os, strutils]
import ../level0/repo_utils
import submodule_links
include ../level0/metaPragmas


type
  SubmoduleExternalizeReport* = object
    ok*: bool
    repos*: int
    cloned*: int
    linked*: int
    updated*: int
    conflicts*: int
    skipped*: int
    lines*: seq[string]


proc addLine(ls: var seq[string], l: string) {.role(helper).} =
  ## ls: line buffer.
  ## l: line to append.
  ls.add(l)

proc resolveRootDir(repo: string, rootOverride: string): string {.role(parser).} =
  ## repo: parent repository path.
  ## rootOverride: optional sibling root override.
  if rootOverride.strip().len > 0:
    return normalizePathValue(rootOverride)
  result = normalizePathValue(parentDir(repo))

proc buildLocalEntry(m: SubmoduleInfo, siblingPath: string): SubmoduleInfo {.role(truthBuilder).} =
  ## m: submodule metadata.
  ## siblingPath: external sibling repo path.
  var n: SubmoduleInfo = m
  n.url = normalizePathValue(siblingPath)
  result = n

proc ensureSiblingRepo(repo: string, rootDir: string, m: SubmoduleInfo,
                       report: var SubmoduleExternalizeReport): string {.role(actor).} =
  ## repo: parent repository path.
  ## rootDir: root directory for sibling repos.
  ## m: submodule metadata.
  ## report: report object.
  var
    nestedPath: string
    siblingPath: string
    canonicalUrl: string
    dirty: int
    names: seq[string]
    name: string
    existingSibling: string
  nestedPath = joinPath(repo, m.path)
  existingSibling = preferredExistingSiblingRepo(rootDir, m, repo, nestedPath, report.lines)
  if existingSibling.len > 0:
    canonicalUrl = canonicalRemoteForSubmodule(m, existingSibling, nestedPath)
    if canonicalUrl.len > 0:
      discard setRepoOrigin(existingSibling, canonicalUrl)
    return existingSibling
  names = candidateLocalNames(m)
  for n in names:
    siblingPath = joinPath(rootDir, n)
    if samePath(siblingPath, repo) or samePath(siblingPath, nestedPath):
      continue
    if dirExists(siblingPath):
      if isGitRepo(siblingPath):
        return siblingPath
      inc report.conflicts
      addLine(report.lines, "  Existing non-repo blocks sibling path: " & siblingPath)
      return ""
  name = ""
  if names.len > 1:
    for i in 1 ..< names.len:
      siblingPath = joinPath(rootDir, names[i])
      if samePath(siblingPath, repo) or samePath(siblingPath, nestedPath) or dirExists(siblingPath):
        continue
      name = names[i]
      break
  if name.len == 0:
    for n in names:
      siblingPath = joinPath(rootDir, n)
      if samePath(siblingPath, repo) or samePath(siblingPath, nestedPath) or dirExists(siblingPath):
        continue
      name = n
      break
  if name.len == 0:
    inc report.conflicts
    addLine(report.lines, "  No safe sibling path available for " & m.path)
    return ""
  siblingPath = joinPath(rootDir, name)
  if dirExists(nestedPath) and isGitRepo(nestedPath):
    if cloneRepoToPath(nestedPath, siblingPath) != 0:
      canonicalUrl = canonicalRemoteForSubmodule(m, "", nestedPath)
      if canonicalUrl.len == 0 or cloneRepoToPath(canonicalUrl, siblingPath) != 0:
        report.ok = false
        addLine(report.lines, "  Failed to create sibling repo for " & m.path)
        return ""
    if not looksLikeLocalPath(m.url):
      discard setRepoOrigin(siblingPath, m.url)
    dirty = dirtyItemCount(nestedPath)
    if dirty > 0:
      copyWorktreeToRepo(nestedPath, siblingPath)
      addLine(report.lines, "  Copied nested worktree changes into sibling repo.")
    inc report.cloned
    addLine(report.lines, "  Created sibling repo: " & siblingPath)
    return siblingPath
  canonicalUrl = m.url.strip()
  if canonicalUrl.len > 0 and not looksLikeLocalPath(canonicalUrl):
    if cloneRepoToPath(canonicalUrl, siblingPath) != 0:
      report.ok = false
      addLine(report.lines, "  Failed to clone missing sibling repo: " & canonicalUrl)
      return ""
    discard setRepoOrigin(siblingPath, canonicalUrl)
    inc report.cloned
    addLine(report.lines, "  Cloned sibling repo: " & siblingPath)
    return siblingPath
  inc report.skipped
  addLine(report.lines, "  No sibling repo found or created for " & m.path)
  result = ""

proc processRepo(repo: string, rootOverride: string, verbose: bool,
                 report: var SubmoduleExternalizeReport) {.role(helper).} =
  ## repo: parent repository path.
  ## rootOverride: optional sibling root override.
  ## verbose: verbose toggle.
  ## report: report object.
  var
    gm: string
    gl: string
    ms: seq[SubmoduleInfo]
    locals: seq[SubmoduleInfo]
    nestedPath: string
    siblingPath: string
    rootDir: string
    decision: string
    linkReport: SubmoduleLinkReport
    merged: seq[SubmoduleInfo]
  gm = joinPath(repo, ".gitmodules")
  if not dirExists(joinPath(repo, ironDir)):
    return
  if not fileExists(gm):
    return
  ms = readSubmodules(gm)
  if ms.len == 0:
    return
  inc report.repos
  rootDir = resolveRootDir(repo, rootOverride)
  addLine(report.lines, "==> " & repo)
  if verbose:
    addLine(report.lines, "  Root: " & rootDir)
  for m in ms:
    nestedPath = joinPath(repo, m.path)
    siblingPath = preferredExistingSiblingRepo(rootDir, m, repo, nestedPath, report.lines)
    if siblingPath.len > 0 and dirExists(nestedPath) and isGitRepo(nestedPath):
      decision = choosePreferredRepo(nestedPath, siblingPath, m.url, report.lines)
      if decision == "nested":
        inc report.conflicts
        addLine(report.lines, "  Conflict: nested checkout kept for manual review: " & m.path)
        continue
    siblingPath = ensureSiblingRepo(repo, rootDir, m, report)
    if siblingPath.len == 0:
      continue
    locals.add(buildLocalEntry(m, siblingPath))
  if locals.len == 0:
    addLine(report.lines, "  No submodules externalized.")
    return
  discard ensureLocalIgnoreRules(repo)
  gl = joinPath(repo, LocalModulesFile)
  merged = mergeSubmodules(readSubmodules(gl), locals)
  writeLocalModules(gl, merged)
  if applyLocalConfig(repo, merged) != 0:
    report.ok = false
    addLine(report.lines, "  Failed to update local git config.")
    return
  linkReport = linkConfiguredSubmodules(repo, locals, true)
  if not linkReport.ok:
    report.ok = false
  report.linked = report.linked + linkReport.linked
  report.updated = report.updated + linkReport.updated
  report.skipped = report.skipped + linkReport.skipped
  for line in linkReport.lines:
    addLine(report.lines, "  " & line)

proc externalizeSubmodulesInRepo*(repoPath: string, rootOverride: string,
                                  verbose: bool = false): SubmoduleExternalizeReport {.role(orchestrator).} =
  ## repoPath: target repository path.
  ## rootOverride: optional sibling root override.
  ## verbose: verbose toggle.
  var
    report: SubmoduleExternalizeReport
    repo: string
  report.ok = true
  repo = normalizePathValue(repoPath)
  if repo.len == 0:
    repo = normalizePathValue(getCurrentDir())
  if repo.len == 0 or not isGitRepo(repo):
    report.ok = false
    addLine(report.lines, "Target is not a git repo: " & repo)
    return report
  processRepo(repo, rootOverride, verbose, report)
  result = report

proc externalizeSubmodulesFromRoots*(rootOverride: string,
                                     verbose: bool = false): SubmoduleExternalizeReport {.role(orchestrator).} =
  ## rootOverride: optional sibling root override.
  ## verbose: verbose toggle.
  var
    report: SubmoduleExternalizeReport
    repos: seq[string]
  report.ok = true
  repos = collectReposFromRoots()
  if repos.len == 0:
    report.ok = false
    addLine(report.lines, "No repos found.")
    return report
  if not confirmEnter("Externalize submodule repos under roots?"):
    report.ok = false
    addLine(report.lines, "Externalize cancelled by user.")
    return report
  addLine(report.lines, "Found " & $repos.len & " repos.")
  for repo in repos:
    if not isGitRepo(repo):
      continue
    processRepo(repo, rootOverride, verbose, report)
  addLine(report.lines, "Repos processed: " & $report.repos)
  addLine(report.lines, "Sibling repos created: " & $report.cloned)
  addLine(report.lines, "Submodule links created: " & $report.linked)
  addLine(report.lines, "Canonical URLs updated: " & $report.updated)
  addLine(report.lines, "Conflicts: " & $report.conflicts)
  addLine(report.lines, "Skipped: " & $report.skipped)
  result = report
