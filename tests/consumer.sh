#!/bin/bash
# Runs ci.sh, as the action does, and a commit, in a new repository that
# setup.sh sets up from a clone of this repository at a tag of its own.
# The repository turns off a language with skip: true, and gives each job
# its files by glob, in lefthook-repo.yml. It changes the settings of the
# tools in their own files, which the checks lay over their defaults. A run
# that checks no file would pass, and that's what this test catches.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
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
git -C "$dir/repofiles" tag v9.9.9
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$dir/repofiles.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/lovaizu/repofiles
git init -q "$dir/consumer"
cd "$dir/consumer" || exit 1
"$dir/repofiles/setup.sh" . >/dev/null || { echo "Failed: setup.sh should set up the repository."; exit 1; }
# Cases with findings, as tests/run.sh knows them, and a file that the
# globs leave out. The English README names a Japanese key, which the
# Japanese rules would read as a sentence of Japanese.
mkdir -p docs/ja
cp "$here/tests/cases/english/fail-english.md" README.md
printf '\nPress the key ⌘英かな to switch the input method to English, and press it again to go back to the Japanese input method of macOS.\n' >>README.md
cp "$here/tests/cases/japanese/fail-japanese.md" docs/ja/guide.md
cp "$here/tests/cases/english/fail-english.md" left-out.txt
# Files that hold no prose, which a job with no glob checks too.
cp "$here/LICENSE" "$here/mise.lock" .
git add -A

# With no lefthook-repo.yml, both jobs check each file, and textlint fails
# on each file of a format that it doesn't read.
expect 1 "" "english ❯" "japanese ❯" "Vale on README.md" "Vale on LICENSE" "textlint on docs/ja/guide.md" "textlint didn't check" "lefthook.yml" "with glob or exclude in lefthook-repo.yml"
# With the Japanese job off, only the English one runs, and Vale checks
# each file, the shared files and the README with its Japanese key too.
# The repository leaves out the files that hold no prose, as the README
# says.
cat >lefthook-repo.yml <<YAML
pre-commit:
  jobs:
    - name: english
      exclude:
        - LICENSE
        - "*.lock"
    - name: japanese
      skip: true
YAML
git add lefthook-repo.yml
expect 1 "japanese ❯|Vale on (LICENSE|mise.lock|lefthook.yml|lefthook-repo.yml|.github/workflows/checks.yml)" "japanese (skip)" Google.Latin "Vale on README.md" "Vale on left-out.txt"

# With both languages, the repository gives each job its files. With
# doublestar, *.md matches the files in the root alone, and
# docs/ja/**/*.md matches the files right in docs/ja too.
cat >lefthook-repo.yml <<YAML
glob_matcher: doublestar
pre-commit:
  jobs:
    - name: english
      glob: "*.md"
    - name: japanese
      glob: "docs/ja/**/*.md"
YAML
git add lefthook-repo.yml
expect 1 "textlint on README.md" Google.Latin "Vale on README.md" "textlint on docs/ja/guide.md" "no-mix-dearu-desumasu (error)"
expect 1 left-out.txt
expect 1 "Vale on docs/ja/guide.md"

# The settings of the repository change only what they name.
printf '[*]\nGoogle.Latin = suggestion\n' >.vale.ini
printf 'rules:\n  preset-ja-technical-writing:\n    no-mix-dearu-desumasu:\n      severity: info\n' >.textlintrc
git add .vale.ini .textlintrc
expect 0 left-out.txt "Google.Latin (suggestion)" "no-mix-dearu-desumasu (info)"

# A commit runs the same checks, once lefthook installs its hooks: a
# finding that stops the check stops the commit, and a clean text goes in.
lefthook install >/dev/null
run=(git commit -q -m "Add the guide")
git rm -q -f .vale.ini
expect 1 "" "Google.Latin (error)" "Vale on README.md"
printf '[*]\nGoogle.Latin = suggestion\n' >.vale.ini
git add .vale.ini
expect 0 left-out.txt
[ -n "$(git log --oneline 2>/dev/null)" ] || { echo "Failed: a clean commit should go in."; failed=1; }

# With both languages off, no job of the checks runs, and ci.sh must fail.
run=(bash "$here/ci.sh")
printf 'pre-commit:\n  jobs:\n    - name: english\n      skip: true\n    - name: japanese\n      skip: true\n' >lefthook-repo.yml
expect 1 left-out.txt "has no job of lovaizu/repofiles that is on" "leave at least one language on in lefthook-repo.yml"
[ "$failed" -eq 0 ] && echo "The consumer cases passed."
exit "$failed"
