module more.repos;

import std.array;
import std.path;
import std.file;

import core.stdc.stdlib : alloca;

import more.fields;
import more.path;

immutable gitDir = ".git";

/**
   Checks to see if the given path is inside a git repo.
   It does this by checking for the '.git' directory in the given directory and every
   parent directory.
   Returns: The path to the root of the git repo, or null if not inside a git repo.
 */
string insideGitRepo(string path = getcwd()) nothrow @nogc
{
  auto pathBuffer = cast(char*)alloca(path.length + 1 + gitDir.length);

  char[] addGitDir(size_t s) nothrow @nogc
  {
    if(pathBuffer[s-1] == dirSeparator[0]) {
      pathBuffer[s..s+gitDir.length] = gitDir;
      return pathBuffer[0..s+gitDir.length];
    } else {
      pathBuffer[s] = dirSeparator[0];
      pathBuffer[s+1..s+1+gitDir.length] = gitDir;
      return pathBuffer[0..s+1+gitDir.length];
    }
  }

  pathBuffer[0..path.length] = path;
  auto gitPath = addGitDir(path.length);

  while(true) {
    auto currentDir = gitPath[0..$-gitDir.length-1];

    if(exists(gitPath)) {
      return path[0..currentDir.length];
    }

    auto newCheckPath = parentDir(currentDir);
    if(newCheckPath.length == currentDir.length) {
      return null;
    }

    gitPath = addGitDir(newCheckPath.length);
  }
}

struct Repo
{
  string localPath;
  //string keyPath; // 

  string globMatcher;

  void setupGlobMatcher()
  {
    this.globMatcher = localPath;
  }
  bool contains(string file) {
    if(globMatcher is null) {
      setupGlobMatcher();
    }
    return globMatch(globMatcher, file);
  }
}

struct RepoSet
{
  Appender!(Repo[]) repos;
  
  bool pathBelongsToKnownRepo(string path, ref Repo foundRepo) {
    foreach(repo; repos.data) {
      if(repo.contains(path)) {
        foundRepo = repo;
        return true;
      }
    }
    return false;
  }
}
RepoSet knownRepos;


/**
Find Repo Algorithm:
  1. Check if you are inside a git repository, if you are get out.
  2. search the given directory for sub directories with the same name as the repo.
     If the repo name matches, it checks if it is a repo, if it is, then the repo is found.
  3. It checks for a file named "repos".  If it exists it reads the file and searches to
     see if it contains the definition for the repo.
  4. It goes through every parent directory checking the sub directories again for the repo name.
 */
Repo findRepo(string repoName, string path = null)
{
  if(path.length <= 0) {
    path = getcwd();
  } else {
    
  }

  Repo currentRepo;



  if(knownRepos.pathBelongsToKnownRepo(path, currentRepo)) {
    path = currentRepo.localPath;
  }



  return Repo();
/+
  

  foreach(entry; dirEntries(path, SpanMode.shallow)) {
    if(
  }
+/
}
