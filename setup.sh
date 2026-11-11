#!/bin/bash
# Puts the files of files/ into the repository at the path given, or updates
# them there, at the tag that this clone has checked out. Each file names
# that tag, so the repository runs the checks of that version. setup.sh
# replaces only a file that starts with the same first line as its own, so
# it never overwrites a file of the repository.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <path>" >&2
  echo "Puts the files that lovaizu repositories share into the repository at <path>, at the tag that $here has checked out." >&2
  exit 2
fi
target="$1"
if ! version="$(git -C "$here" describe --tags --exact-match HEAD 2>/dev/null)"; then
  echo "setup.sh: $here hasn't checked out a tag, so setup.sh doesn't know which version to put. Fix: run git -C $here checkout <tag>." >&2
  exit 1
fi
commit="$(git -C "$here" rev-parse HEAD)"

# Prints file $1 of files/ at the tag, with the version filled in.
render() {
  local text
  text="$(git -C "$here" show "$commit:files/$1")"
  text="${text//\{\{version\}\}/$version}"
  printf '%s\n' "${text//\{\{commit\}\}/$commit}"
}

mapfile -t names < <(git -C "$here" ls-tree -r --name-only "$commit" -- files/ | sed 's|^files/||')
blocked=()
for name in "${names[@]}"; do
  [ ! -e "$target/$name" ] || [ "$(head -n 1 "$target/$name")" = "$(render "$name" | head -n 1)" ] || blocked+=("$name")
done
if [ "${#blocked[@]}" -gt 0 ]; then
  echo "setup.sh: these files are the repository's own, so setup.sh put nothing: ${blocked[*]}. Fix: move their settings out, the lefthook settings to lefthook-repo.yml, delete the files, and run setup.sh again." >&2
  exit 1
fi
for name in "${names[@]}"; do
  text="$(render "$name")"
  [ "$(cat "$target/$name" 2>/dev/null)" != "$text" ] || continue
  mkdir -p "$(dirname "$target/$name")"
  printf '%s\n' "$text" >"$target/$name"
  echo "setup.sh: put $name of $version."
done
