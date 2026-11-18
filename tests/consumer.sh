#!/bin/bash
# Runs ci.sh, as the action does, and a commit, in a new repository that
# setup.sh sets up from a clone of this repository at a tag of its own,
# with settings of its own in lefthook-repo.yml and .vale.ini.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# The commits of the test need an identity, which a runner of CI lacks.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# The command that expect runs: ci.sh, as the action runs it, unless a case
# names another.
run=(bash "$here/ci.sh")
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
# The daily check reads the links to other sites of the files of the links
# job, and lists them in an Issue by gh, which a stub stands for: it logs
# each call with the body that it gets, and answers the list of the open
# Issues with $dir/issues.json. Nothing listens on port 9 of 127.0.0.1, so
# a link there leads nowhere with no network.
mkdir -p "$dir/bin" vendor
cat >"$dir/bin/gh" <<STUB
#!/bin/bash
echo "gh \$*" >>"$dir/gh.log"
case "\$1 \$2" in
  "issue list") cat "$dir/issues.json" ;;
  *) for arg; do [ "\$prev" != --body-file ] || cat "\$arg" >>"$dir/gh.log"; prev="\$arg"; done ;;
esac
STUB
chmod +x "$dir/bin/gh"
export GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=lovaizu/consumer GITHUB_SHA=0123456789abcdef
printf 'pre-commit:\n  jobs:\n    - name: japanese\n      skip: true\n    - name: links\n      exclude:\n        - "vendor/**"\n' >lefthook-repo.yml
printf '# Links\n\n[A site that is down](http://127.0.0.1:9/away), and [a file that moved](moved.md).\n' | tee away.md >vendor/away.md
git add -A
run=(env PATH="$dir/bin:$PATH" bash "$here/daily.sh" links)
title="Fix the links to other sites that lead nowhere"
# Fails the test unless the log of the stub holds each text after $1, and
# no line that matches the extended regular expression $1, if any. Then
# empties the log.
logged() {
  local left="$1" want
  shift
  touch "$dir/gh.log"
  for want in "$@"; do
    grep -qF -- "$want" "$dir/gh.log" || { echo "Failed: gh should get $want, but got:"; cat "$dir/gh.log"; failed=1; }
  done
  [ -z "$left" ] || ! grep -qE -- "$left" "$dir/gh.log" || { echo "Failed: gh shouldn't get $left, but got:"; cat "$dir/gh.log"; failed=1; }
  rm "$dir/gh.log"
}
printf '[]\n' >"$dir/issues.json"
expect 0 ""
logged "vendor|moved.md" "gh issue create --title $title --body-file" "- [\`away.md\`, line 3](https://github.com/lovaizu/consumer/blob/0123456789abcdef/away.md?plain=1#L3): http://127.0.0.1:9/away: Network error"
# It updates the open Issue that it opened before, and opens no other.
printf '[{"number": 3, "title": "Another Issue"}, {"number": 7, "title": "%s"}]\n' "$title" >"$dir/issues.json"
expect 0 ""
logged "issue create" "gh issue edit 7 --body-file" "http://127.0.0.1:9/away"
# With no finding, it leaves the Issues as they are.
printf '# Links\n' >away.md
git add away.md
expect 0 ""
logged "issue"
# With the links job off, it checks nothing.
printf 'pre-commit:\n  jobs:\n    - name: links\n      skip: true\n' >lefthook-repo.yml
expect 0 "" "daily.sh checks nothing"
# With each check off, ci.sh fails, as it would check nothing.
run=(bash "$here/ci.sh")
printf 'pre-commit:\n  jobs:\n    - name: english\n      skip: true\n    - name: japanese\n      skip: true\n    - name: links\n      skip: true\n' >lefthook-repo.yml
expect 1 "" "has no job of lovaizu/repofiles that is on"
[ "$failed" -eq 0 ] && echo "The consumer cases passed."
exit "$failed"
