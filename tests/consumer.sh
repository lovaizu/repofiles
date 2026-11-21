#!/bin/bash
# Runs ci.sh and daily.sh, as the action does, and a commit, in a new
# repository that setup.sh sets up from a clone of this repository at a tag
# of its own, with settings of its own in lefthook-repo.yml and .vale.ini.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# The commits of the test need an identity, which a runner of CI lacks.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# The command that expect runs: ci.sh, as the action runs it, unless a case
# names another.
run=("$here/ci.sh")
# Fails the test when the command doesn't exit $1 with each text that the
# rest names, or prints a line that matches the extended regular expression
# $2, if any, which the case leaves out.
expect() {
  local code="$1" left="$2" out status want
  shift 2
  out="$("${run[@]}" 2>&1)"
  status=$?
  for want in "$@"; do
    grep -qF -- "$want" <<<"$out" || status="$status, without $want"
  done
  [ -z "$left" ] || ! grep -qE -- "$left" <<<"$out" || status="$status, with $left"
  if [ "$status" != "$code" ]; then
    echo "Failed: ${run[*]} should exit $code with $*, but it exited $status with:"
    echo "$out"
    failed=1
  fi
}

# lefthook fetches a remote by a branch or a tag, so this commit gets a tag
# of its own in a copy of this repository. Git fetches the URL that
# setup.sh writes from that copy.
git clone -q "$here" "$dir/repofiles"
git -C "$dir/repofiles" checkout -q "$(git -C "$here" rev-parse HEAD)"
# The cases set the tags, so they run the same on a branch and on a tag.
git -C "$dir/repofiles" tag -l | xargs -r git -C "$dir/repofiles" tag -d >/dev/null
git -C "$dir/repofiles" tag v9.9.9
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$dir/repofiles.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/lovaizu/repofiles
git init -q "$dir/consumer"
cd "$dir/consumer" || exit 1
"$dir/repofiles/setup.sh" . >/dev/null || { echo "Failed: setup.sh should set up the repository."; exit 1; }
cp "$here/tests/cases/english/fail-english.md" README.md
cp "$here/LICENSE" .
printf '# Use a tool, e.g. Vale.\nprint(1)\n' >tool.py
printf 'Read [the steps](setup.md).\n' >steps.md
# The repository turns off Japanese. The checks leave out the files that
# setup.sh put, LICENSE, a file with no extension, and tool.py, as they read
# only Markdown unless the repository names other files.
printf 'pre-commit:\n  jobs:\n    - name: japanese\n      skip: true\n' >lefthook-repo.yml
git add -A
expect 1 "Vale on (LICENSE|tool.py|lefthook|.github|.claude)" "japanese (skip)" "Vale on README.md:" "Google.Latin (error)" "lychee on steps.md:" "setup.md: File not found"
git rm -q --cached steps.md
rm steps.md
# A .vale.ini of the repository changes the checks.
printf '[*]\nGoogle.Latin = suggestion\n' >.vale.ini
expect 0 "" "Google.Latin (suggestion)"
# A commit runs the checks: a finding stops it, and a clean text goes in.
lefthook install >/dev/null
run=(git commit -q -m "Add the README")
rm .vale.ini
expect 1 "" "Google.Latin (error)"
printf '[*]\nGoogle.Latin = suggestion\n' >.vale.ini
git add .vale.ini
expect 0 ""
[ -n "$(git log --oneline 2>/dev/null)" ] || { echo "Failed: a clean commit should go in."; failed=1; }
# The daily check reads all the links of the files of the links job, and
# fails on a finding, with a report that names no commit. Nothing listens
# on port 9 of 127.0.0.1, so a link there leads nowhere with no network.
mkdir -p vendor
printf 'pre-commit:\n  jobs:\n    - name: japanese\n      skip: true\n    - name: links\n      exclude:\n        - "vendor/**"\n' >lefthook-repo.yml
printf '# Links\n\n[A site that is down](http://127.0.0.1:9/away), and [a file that moved](moved.md).\n' | tee away.md >vendor/away.md
git add -A
run=("$here/daily.sh" links)
expect 1 "vendor|stop the commit" "These links lead nowhere:" "lychee on away.md:" "Line 3, dead-link (error): http://127.0.0.1:9/away: " "Line 3, dead-link (error): moved.md: File not found"
# With no finding, it passes.
printf '# Links\n' >away.md
git add away.md
expect 0 ""
# With the links job off, it checks nothing.
printf 'pre-commit:\n  jobs:\n    - name: links\n      skip: true\n' >lefthook-repo.yml
expect 0 "" "daily.sh checks nothing"
# With each check off, ci.sh fails, as it would check nothing.
run=("$here/ci.sh")
printf 'pre-commit:\n  jobs:\n    - name: english\n      skip: true\n    - name: japanese\n      skip: true\n    - name: links\n      skip: true\n' >lefthook-repo.yml
expect 1 "" "has no job of lovaizu/repofiles that is on"
[ "$failed" -eq 0 ] && echo "The consumer cases passed."
exit "$failed"
