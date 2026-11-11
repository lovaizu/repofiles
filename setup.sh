#!/bin/bash
# Puts the files that lovaizu repositories share, those of files/, into the
# repository at the path given, or updates them there, at the version that
# this clone has checked out: a tag. Each file names that version, so the
# repository runs the checks of that tag, and updating it is running
# setup.sh again from a newer tag.
# setup.sh replaces only a file that it put, one that starts with the same
# first line, so it never overwrites a file of the repository's own. Into
# .claude/settings.json, which holds settings of the repository too, it
# merges only its own hooks. It writes a file only when its text changes,
# so a second run changes nothing.
set -euo pipefail
unset CDPATH
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 <path>

Puts the files that lovaizu repositories share into the repository at
<path>, or updates them there, at the version of lovaizu/repofiles that
$here has checked out.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") usage >&2; exit 2 ;;
esac
[ "$#" -eq 1 ] || { usage >&2; exit 2; }

if ! target="$(cd "$1" 2>/dev/null && pwd -P)" ||
  [ "$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" != "$target" ]; then
  echo "setup.sh: $1 isn't the root of a Git repository, so setup.sh put nothing." >&2
  echo "  Fix: give the path of the directory that holds the .git of the repository." >&2
  exit 1
fi
# The version is the tag that this clone has checked out, and the files
# come from that commit, not from the working tree, so that they're the
# files of that version.
if ! version="$(git -C "$here" describe --tags --exact-match HEAD 2>/dev/null)"; then
  echo "setup.sh: $here hasn't checked out a tag of lovaizu/repofiles, so setup.sh doesn't know which version to put." >&2
  echo "  Fix: run git -C $here fetch --tags, then git -C $here checkout <tag>, such as the newest tag that git -C $here tag --sort=-v:refname lists first." >&2
  exit 1
fi
commit="$(git -C "$here" rev-parse 'HEAD^{commit}')"
# jq merges the hooks into .claude/settings.json, from the tools of the
# checks.
"$here/install.sh" >&2
eval "$(MISE_LOCKED=1 MISE_TRUSTED_CONFIG_PATHS="$here/mise.toml" mise -C "$here" env -s bash)"

# Prints file $1 of files/ at the version, with its placeholders filled in.
render() {
  local text
  text="$(git -C "$here" show "$commit:files/$1")"
  text="${text//\{\{version\}\}/$version}"
  printf '%s\n' "${text//\{\{commit\}\}/$commit}"
}

# Prints settings file $1 with the hooks of template $2 in place of those
# that setup.sh put before: each hook that runs `lefthook run claude-code`.
# Settings that already hold the hooks of the template stay as they are,
# with the format of the repository.
settings() {
  jq --argjson template "$2" '
    def ours: (.command // "") | contains("lefthook run claude-code");
    def groups($keep): [.hooks.PreToolUse[]? | .hooks |= map(select(ours == $keep)) | select(.hooks | length > 0)];
    if groups(true) == $template.hooks.PreToolUse then empty
    else .hooks.PreToolUse = groups(false) + $template.hooks.PreToolUse end' "$1"
}

mapfile -t names < <(git -C "$here" ls-tree -r --name-only "$commit" -- files/ | sed 's|^files/||')
# Each file of the repository's own that is in the way stops setup.sh
# before it writes anything, and so do settings that jq can't read.
if [ -e "$target/.claude/settings.json" ] && ! jq -e 'type == "object"' "$target/.claude/settings.json" >/dev/null 2>&1; then
  echo "setup.sh: $target/.claude/settings.json isn't a JSON object, so setup.sh can't add its hooks to it, and put nothing." >&2
  echo "  Fix: correct the JSON of the file, and run setup.sh again." >&2
  exit 1
fi
blocked=()
for name in "${names[@]}"; do
  [ -e "$target/$name" ] && [ "$name" != .claude/settings.json ] || continue
  [ "$(head -n 1 "$target/$name")" = "$(render "$name" | head -n 1)" ] || blocked+=("$name")
done
if [ "${#blocked[@]}" -gt 0 ]; then
  echo "setup.sh: $target holds files of its own where setup.sh puts the shared ones, so setup.sh put nothing: ${blocked[*]}." >&2
  echo "  Fix: move the settings of the repository out of each file, its lefthook settings to lefthook-repo.yml, which lefthook.yml extends, then delete the file, and run setup.sh again." >&2
  exit 1
fi

for name in "${names[@]}"; do
  text="$(render "$name")"
  if [ "$name" = .claude/settings.json ] && [ -e "$target/$name" ]; then
    text="$(settings "$target/$name" "$text")"
    [ -n "$text" ] || continue
  fi
  [ "$(cat "$target/$name" 2>/dev/null)" != "$text" ] || continue
  mkdir -p "$(dirname "$target/$name")"
  printf '%s\n' "$text" >"$target/$name"
  echo "setup.sh: put $name of $version."
done
