# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

switch("path", "src")
switch("path", "submodules/Jormungandr-RepoCoordinator/src")
