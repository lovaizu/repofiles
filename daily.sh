#!/bin/bash
# The daily check that the action runs when its input daily names it, on the
# repository in the current directory. links checks all the links of the
# files that the links job of lefthook.yml reads, and fails on a
# finding, as the README says. lefthook fetches the remotes of lefthook.yml
# only when it installs the hooks, so daily.sh installs them first.
set -euo pipefail

if [ "${1:-}" != links ]; then
  echo "daily.sh: the input daily of the action must be links, not '${1:-}'." >&2
  exit 1
fi
lefthook install
jobs="$(lefthook dump --format json | jq '[.["pre-commit"].jobs // [] | .[] | select(.name == "links" and .script == "prose.sh" and .skip != true)] | length')"
if [ "$jobs" -eq 0 ]; then
  echo "daily.sh: the repository turns off the links job in lefthook-repo.yml, so daily.sh checks nothing."
  exit 0
fi
REPOFILES_LINKS_DAILY=1 lefthook run pre-commit --all-files --no-auto-install --job links
