#!/bin/bash
# The daily check that the action runs when its input daily names it, on the
# repository in the current directory. links checks the links to other sites
# of the files that the links job of lefthook.yml reads, and lists each
# finding in an Issue: the Issue that it opened before, while it's open, or
# a new one. The README says why it leaves the Issue open when it finds
# nothing. lefthook fetches the remotes of lefthook.yml only when it
# installs the hooks, so daily.sh installs them first.
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
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
: >"$work/links.jsonl"
status=0
REPOFILES_LINKS_REPORT="$work/links.jsonl" lefthook run pre-commit --all-files --no-auto-install --job links || status=$?

if [ -s "$work/links.jsonl" ]; then
  title="Fix the links to other sites that lead nowhere"
  blob="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/blob/$GITHUB_SHA"
  # ?plain=1 shows the lines of a Markdown file, so that #L3 leads to one.
  jq -rs --arg blob "$blob" --arg sha "${GITHUB_SHA:0:7}" '
    "The daily check found these links to other sites that lead nowhere, on \($sha):\n\n"
    + (sort_by(.file, .line) | map("- [`\(.file)`, line \(.line)](\($blob)/\(.file)?plain=1#L\(.line)): \(.message)") | join("\n"))
    + "\n\nFix or delete each link. A link that only a reader with access can follow, such as one to a private repository, goes in `exclude` of the `lychee.toml` of the repository. Each run that finds a link that leads nowhere writes its list here. Close this Issue when the links lead somewhere."' \
    "$work/links.jsonl" >"$work/body.md"
  number="$(gh issue list --app github-actions --state open --json number,title | jq -r --arg title "$title" '[.[] | select(.title == $title)][0].number // empty')"
  if [ -n "$number" ]; then
    gh issue edit "$number" --body-file "$work/body.md"
  else
    gh issue create --title "$title" --body-file "$work/body.md"
  fi
fi
exit "$status"
