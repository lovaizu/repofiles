#!/bin/bash
# Puts the files that lovaizu repositories share, those of files/, into the
# repository at the path given, or updates them there, at the version that
# this clone has checked out: a tag. Each file names that version, so the
# repository runs the checks of that tag, and updating it is running
# setup.sh again from a newer tag.
# setup.sh replaces only a file that it put, one that starts with the same
# first line, so it never overwrites a file of the repository's own. It
# writes a file only when its text changes, so a second run changes nothing.
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

# Prints file $1 of files/ at the version, with its placeholders filled in.
render() {
  local text
  text="$(git -C "$here" show "$commit:files/$1")"
  text="${text//\{\{version\}\}/$version}"
  printf '%s\n' "${text//\{\{commit\}\}/$commit}"
}

mapfile -t names < <(git -C "$here" ls-tree -r --name-only "$commit" -- files/ | sed 's|^files/||')
# Each file of the repository's own that is in the way stops setup.sh
# before it writes anything.
blocked=()
for name in "${names[@]}"; do
  [ -e "$target/$name" ] || continue
  [ "$(head -n 1 "$target/$name")" = "$(render "$name" | head -n 1)" ] || blocked+=("$name")
done
if [ "${#blocked[@]}" -gt 0 ]; then
  echo "setup.sh: $target holds files of its own where setup.sh puts the shared ones, so setup.sh put nothing: ${blocked[*]}." >&2
  echo "  Fix: move the settings of the repository out of each file, as the README of lovaizu/repofiles says, delete the file, and run setup.sh again." >&2
  exit 1
fi

for name in "${names[@]}"; do
  text="$(render "$name")"
  [ "$(cat "$target/$name" 2>/dev/null)" != "$text" ] || continue
  mkdir -p "$(dirname "$target/$name")"
  printf '%s\n' "$text" >"$target/$name"
  echo "setup.sh: put $name of $version."
done
