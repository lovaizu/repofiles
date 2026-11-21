#!/bin/bash
# The checks that the action runs on every file of the repository in the
# current directory. lefthook fetches the remotes of lefthook.yml only when
# it installs the hooks, so ci.sh installs them first. A run with no job
# would pass and check nothing, so ci.sh fails when pre-commit has no job
# that runs prose.sh, other than those that the repository turns off with
# skip: true.
set -euo pipefail
lefthook install
jobs="$(lefthook dump --format json | jq '[.["pre-commit"].jobs // [] | .[] | select(.script == "prose.sh" and .skip != true)] | length')"
if [ "$jobs" -eq 0 ]; then
  echo "ci.sh: the pre-commit hook of lefthook.yml has no job of lovaizu/repofiles that is on, so ci.sh would check nothing." >&2
  echo "  Fix: run setup.sh of lovaizu/repofiles on the repository, and leave at least one language on in lefthook-repo.yml." >&2
  exit 1
fi
lefthook run pre-commit --all-files --no-auto-install
