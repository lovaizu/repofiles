#!/bin/bash
# Runs setup.sh, from a clone of this repository at a tag, on repositories
# like those that use it: one with no shared file yet, one with settings of
# its own in a file where setup.sh puts a shared one, and one that setup.sh
# has set up, at the same tag and at a newer one.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# The commits of the test need an identity, which a runner of CI lacks.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# Runs the command after $1 and $2, and fails the test when it doesn't exit
# $1 with each text that $2 holds, one on each line.
expect() {
  local code="$1" wants="$2" out status want
  shift 2
  out="$("$@" 2>&1)"
  status=$?
  while IFS= read -r want; do
    [ -z "$want" ] || grep -qF -- "$want" <<<"$out" || status="$status, without $want"
  done <<<"$wants"
  if [ "$status" != "$code" ]; then
    echo "Failed: $* should exit $code with $wants, but it exited $status with:"
    echo "$out"
    failed=1
  fi
}
# Fails the test unless file $1 holds each text after $1.
holds() {
  local file="$1" want
  shift
  for want in "$@"; do
    grep -qF -- "$want" "$file" 2>/dev/null || { echo "Failed: $file should hold $want, but it holds:"; cat "$file"; failed=1; }
  done
}
# Prints the state of the files in directory $1, but those of .git.
state() {
  (cd "$1" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -l --time-style=+%s.%N && find . -path ./.git -prune -o -type f -print | sort | xargs cat)
}

git clone -q "$here" "$dir/repofiles"
git -C "$dir/repofiles" checkout -q "$(git -C "$here" rev-parse HEAD)"
setup="$dir/repofiles/setup.sh"
commit="$(git -C "$here" rev-parse HEAD)"

# Without a path, setup.sh prints how to use it.
expect 2 "Usage: $setup <path>" "$setup"
expect 0 "Usage: $setup <path>" "$setup" --help
# setup.sh puts nothing where it isn't the root of a repository.
git init -q "$dir/repo"
mkdir "$dir/repo/docs"
expect 1 "isn't the root of a Git repository" "$setup" "$dir/repo/docs"
expect 1 "isn't the root of a Git repository" "$setup" "$dir/none"
# A clone that hasn't checked out a tag has no version to put.
expect 1 "hasn't checked out a tag" "$setup" "$dir/repo"
[ -z "$(ls -A "$dir/repo/docs")" ] && [ ! -e "$dir/repo/lefthook.yml" ] ||
  { echo "Failed: setup.sh should put nothing without a tag."; failed=1; }

git -C "$dir/repofiles" tag v9.9.9
# A repository with none of the shared files gets each of them, at the tag
# and its commit.
expect 0 "put lefthook.yml of v9.9.9
put .github/workflows/checks.yml of v9.9.9
put .claude/settings.json of v9.9.9" "$setup" "$dir/repo"
[ "$(jq -c '[.hooks.PreToolUse[] | .matcher, (.hooks[] | .if, (.command | contains("lefthook run claude-code")))]' "$dir/repo/.claude/settings.json")" = '["Bash","Bash(gh issue *)",true,"Bash(gh pr *)",true]' ] ||
  { echo "Failed: .claude/settings.json should run lefthook run claude-code before each gh issue and gh pr command, but it holds:"; cat "$dir/repo/.claude/settings.json"; failed=1; }
holds "$dir/repo/lefthook.yml" "ref: v9.9.9" "git_url: https://github.com/lovaizu/repofiles" "- lefthook-repo.yml"
holds "$dir/repo/.github/workflows/checks.yml" "uses: lovaizu/repofiles@$commit # v9.9.9"
grep -q '{{' "$dir/repo/lefthook.yml" "$dir/repo/.github/workflows/checks.yml" &&
  { echo "Failed: setup.sh should fill in each placeholder."; failed=1; }
# A second run changes nothing, not even the time of a file.
before="$(state "$dir/repo")"
expect 0 "" "$setup" "$dir/repo"
[ -z "$("$setup" "$dir/repo" 2>&1)" ] || { echo "Failed: a second run of setup.sh should print nothing."; failed=1; }
[ "$(state "$dir/repo")" = "$before" ] || { echo "Failed: a second run of setup.sh should change nothing."; failed=1; }
# A newer tag updates the version in each file, and leaves the files of
# the repository's own as they are.
printf 'pre-commit:\n  jobs:\n    - name: japanese\n      skip: true\n' >"$dir/repo/lefthook-repo.yml"
printf '[*]\nGoogle.Latin = suggestion\n' >"$dir/repo/.vale.ini"
cp "$dir/repo/lefthook-repo.yml" "$dir/repo/.vale.ini" "$dir/"
git -C "$dir/repofiles" commit -q --allow-empty -m "A newer version"
git -C "$dir/repofiles" tag v9.9.10
expect 0 "put lefthook.yml of v9.9.10" "$setup" "$dir/repo"
holds "$dir/repo/lefthook.yml" "ref: v9.9.10"
holds "$dir/repo/.github/workflows/checks.yml" "uses: lovaizu/repofiles@$(git -C "$dir/repofiles" rev-parse HEAD) # v9.9.10"
cmp -s "$dir/lefthook-repo.yml" "$dir/repo/lefthook-repo.yml" && cmp -s "$dir/.vale.ini" "$dir/repo/.vale.ini" ||
  { echo "Failed: setup.sh should leave lefthook-repo.yml and .vale.ini as they are."; failed=1; }

# A repository that holds its own settings in lefthook.yml, as one of
# lovaizu/checks does, keeps them: setup.sh puts nothing, and says which
# file is in the way.
git init -q "$dir/old"
printf 'remotes:\n  - git_url: https://github.com/lovaizu/checks\n    ref: v0.2.0\n' >"$dir/old/lefthook.yml"
cp "$dir/old/lefthook.yml" "$dir/old.yml"
expect 1 "holds files of its own where setup.sh puts the shared ones, so setup.sh put nothing: lefthook.yml.
its lefthook settings to lefthook-repo.yml" "$setup" "$dir/old"
cmp -s "$dir/old.yml" "$dir/old/lefthook.yml" && [ ! -e "$dir/old/.github" ] ||
  { echo "Failed: setup.sh should change nothing in a repository with a lefthook.yml of its own."; failed=1; }

# setup.sh adds its hooks to .claude/settings.json of the repository's own,
# in place of those that it put before, and keeps the rest. Settings that
# already hold the hooks stay as they are, with their format.
git init -q "$dir/own"
mkdir "$dir/own/.claude"
cat >"$dir/own/.claude/settings.json" <<'JSON'
{"permissions": {"allow": ["Bash(make *)"]},
 "hooks": {"PreToolUse": [
   {"matcher": "Bash", "hooks": [{"type": "command", "command": "lefthook run claude-code --old"}, {"type": "command", "command": "own.sh"}]},
   {"matcher": "Write", "hooks": [{"type": "command", "command": "lefthook run claude-code --old"}]}],
  "Stop": [{"hooks": [{"type": "command", "command": "stop.sh"}]}]}}
JSON
expect 0 "put .claude/settings.json of v9.9.10" "$setup" "$dir/own"
got="$(jq -c '[.permissions.allow[], (.hooks.PreToolUse[] | .matcher, (.hooks[] | .if // .command)), .hooks.Stop[0].hooks[0].command]' "$dir/own/.claude/settings.json")"
[ "$got" = '["Bash(make *)","Bash","own.sh","Bash","Bash(gh issue *)","Bash(gh pr *)","stop.sh"]' ] ||
  { echo "Failed: setup.sh should keep the settings of the repository and put its hooks in place of the old ones, but it gave: $got"; failed=1; }
printf '{"hooks": {"PreToolUse": %s}}\n' "$(jq -c .hooks.PreToolUse "$dir/repo/.claude/settings.json")" >"$dir/own/.claude/settings.json"
before="$(state "$dir/own")"
expect 0 "" "$setup" "$dir/own"
[ "$(state "$dir/own")" = "$before" ] || { echo "Failed: setup.sh should leave settings that hold its hooks as they are."; failed=1; }
printf '{"hooks": \n' >"$dir/own/.claude/settings.json"
rm "$dir/own/lefthook.yml"
expect 1 ".claude/settings.json isn't a JSON object" "$setup" "$dir/own"
[ ! -e "$dir/own/lefthook.yml" ] || { echo "Failed: setup.sh should put nothing when it can't read .claude/settings.json."; failed=1; }

[ "$failed" -eq 0 ] && echo "The cases of setup.sh passed."
exit "$failed"
