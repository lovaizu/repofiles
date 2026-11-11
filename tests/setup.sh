#!/bin/bash
# Runs setup.sh from a clone of this repository at a tag, on a new
# repository, again at the same tag and at a newer one, and on a repository
# with a lefthook.yml of its own.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# The commits of the test need an identity, which a runner of CI lacks.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# Fails the test unless the command after $1 and $2 exits $1 and prints $2.
expect() {
  local code="$1" want="$2" out status
  shift 2
  out="$("$@" 2>&1)"
  status=$?
  [ "$status" -eq "$code" ] && grep -qF -- "$want" <<<"$out" ||
    { echo "Failed: $* should exit $code with $want, but it exited $status with:"; echo "$out"; failed=1; }
}

git clone -q "$here" "$dir/repofiles"
git -C "$dir/repofiles" checkout -q "$(git -C "$here" rev-parse HEAD)"
setup="$dir/repofiles/setup.sh"
git init -q "$dir/repo"

expect 2 "Usage: $setup <path>" "$setup"
expect 1 "hasn't checked out a tag" "$setup" "$dir/repo"

# Each file of files/ goes in, with the tag and its commit.
git -C "$dir/repofiles" tag v9.9.9
expect 0 "put .claude/settings.json of v9.9.9" "$setup" "$dir/repo"
grep -q "ref: v9.9.9" "$dir/repo/lefthook.yml" &&
  grep -q "uses: lovaizu/repofiles@$(git -C "$here" rev-parse HEAD) # v9.9.9" "$dir/repo/.github/workflows/checks.yml" &&
  ! grep -rq '{{' "$dir/repo/lefthook.yml" "$dir/repo/.github" "$dir/repo/.claude" ||
  { echo "Failed: setup.sh should put each file with the version filled in."; failed=1; }

# A second run changes nothing.
git -C "$dir/repo" add -A
[ -z "$("$setup" "$dir/repo" 2>&1)" ] && git -C "$dir/repo" diff --quiet ||
  { echo "Failed: a second run of setup.sh should change nothing."; failed=1; }

# A newer tag updates the version, and the files of the repository stay.
printf 'pre-commit: {}\n' >"$dir/repo/lefthook-repo.yml"
git -C "$dir/repofiles" commit -q --allow-empty -m "A newer version"
git -C "$dir/repofiles" tag v9.9.10
expect 0 "put lefthook.yml of v9.9.10" "$setup" "$dir/repo"
grep -q "ref: v9.9.10" "$dir/repo/lefthook.yml" && [ "$(cat "$dir/repo/lefthook-repo.yml")" = "pre-commit: {}" ] ||
  { echo "Failed: setup.sh should update the version and leave lefthook-repo.yml."; failed=1; }

# setup.sh never overwrites a file that it didn't put, and names it.
git init -q "$dir/own"
printf 'remotes: []\n' >"$dir/own/lefthook.yml"
expect 1 "these files are the repository's own, so setup.sh put nothing: lefthook.yml." "$setup" "$dir/own"
[ "$(cat "$dir/own/lefthook.yml")" = "remotes: []" ] && [ ! -e "$dir/own/.claude" ] ||
  { echo "Failed: setup.sh should change nothing in a repository with a lefthook.yml of its own."; failed=1; }

[ "$failed" -eq 0 ] && echo "The cases of setup.sh passed."
exit "$failed"
