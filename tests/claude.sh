#!/bin/bash
# Runs the Claude Code hook, by the command of the .claude/settings.json that
# setup.sh puts, in a repository that setup.sh sets up from a clone of this
# repository at a tag of its own.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# The commits of the test need an identity, which a runner of CI lacks.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# Runs the hook on the Bash command $1, as Claude Code does, and prints what
# it printed.
run() {
  jq -n --arg cwd "$PWD" --arg command "$1" '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' | sh -c "$hook" 2>&1
}
# Runs the hook on the Bash command $1, as Claude Code does, and fails the
# test unless it denies the command with text $2, or, with no $2, prints
# nothing.
expect() {
  local out
  out="$(run "$1")"
  if [ -z "${2:-}" ]; then
    [ -z "$out" ] || { echo "Failed: the hook should pass $1, but it printed:"; echo "$out"; failed=1; }
  elif [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" != deny ] || ! grep -qF -- "$2" <<<"$out"; then
    echo "Failed: the hook should deny $1 with $2, but it printed:"; echo "$out"; failed=1
  fi
}

git clone -q "$here" "$dir/repofiles"
git -C "$dir/repofiles" checkout -q "$(git -C "$here" rev-parse HEAD)"
# The cases set the tags, so they run the same on a branch and on a tag.
git -C "$dir/repofiles" tag -l | xargs -r git -C "$dir/repofiles" tag -d >/dev/null
git -C "$dir/repofiles" tag v9.9.9
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$dir/repofiles.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/lovaizu/repofiles
git init -q "$dir/repo"
cd "$dir/repo" || exit 1
# Claude Code gives each hook the root of the project.
export CLAUDE_PROJECT_DIR="$dir/repo"
"$dir/repofiles/setup.sh" . >/dev/null
hook="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' .claude/settings.json)"
# Each form of a command that posts a text, which the checks read as they
# read the plain one.
posts=(
  "gh pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'"
  "git push && gh pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'"
  "echo 1 | GH_REPO=a/b gh issue comment 1 --body 'Use a tool, e.g. Vale.'"
  "url=\$(gh pr create -R a/b --title 'Add it' --body 'Use a tool, e.g. Vale.')"
  "gh -R a/b pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'"
  "'g'h \"pr\" create --title 'Add it' --body 'Use a tool, e.g. Vale.'"
  "g\$'h' issue create --title 'Add it' --body 'Use a tool, e.g. Vale.'"
)
# With no way to fetch the version, lefthook can't run the job. The hook
# still passes a command that holds no gh issue or gh pr, as it posts no
# text, even one that isn't Bash.
for command in 'R=/path/to/repofiles; $R/ci.sh 2>&1 | tail -60' 'S=/path/to/scratchpad; mkdir -p $S; git diff > $S/d1' 'gh run list' "echo 'a' )"; do
  out="$(GIT_CONFIG_COUNT=0 run "$command")"
  status=$?
  [ "$status" -eq 0 ] && [ -z "$out" ] || { echo "Failed: the hook should pass $command at once, but it exited $status with:"; echo "$out"; failed=1; }
done
# It stops each command that posts a text, and one that may and isn't Bash,
# with exit 2, which Claude Code reads as a denial, and with the error
# output of lefthook.
for command in "${posts[@]}" "gh pr create --title 'Add it' --body 'B' )" "g\\
h pr create --title 'Add it' --body 'B'"; do
  out="$(GIT_CONFIG_COUNT=0 run "$command")"
  status=$?
  [ "$status" -eq 2 ] && grep -qF "lefthook run claude-code failed" <<<"$out" && grep -qF "Error: hook claude-code doesn't exist in the config" <<<"$out" ||
    { echo "Failed: the hook should stop $command with exit 2 and the error output of lefthook, but it exited $status with:"; echo "$out"; failed=1; }
done
lefthook install >/dev/null

for command in "${posts[@]}"; do
  expect "$command" "Google.Latin (error)"
done

expect "gh pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'" "Vale on the body of gh pr create:"
expect "gh issue create --title 'Add it' --body \"\$(cat <<'EOF'
この設定はすべてのファイルに効きます。この設定はルートに置くものである。
EOF
)\"" "no-mix-dearu-desumasu (error)"
expect "gh pr edit 1 --title 'Use e.g. this'" "Vale on the title of gh pr edit:"
# The checks read a title as a heading: it gets the findings of a heading,
# and needs no period.
expect "gh issue create --title '結果を画面で見れるようにしたい' --body '結果を画面で確認できます。'" "no-dropping-the-ra (error)"
expect "gh pr edit 1 --title 'Add Title Case Support Here'" "Google.Headings (warning)"
expect "gh issue create --title '結果を画面で確認したい' --body '結果を画面で確認できます。'"
expect "gh pr create --title 'Check a title as a heading' --body 'Use a tool, such as Vale.'"
expect "gh pr create -t 'Add it' -b 'Use a tool, e.g. Vale.'" "Vale on the body of gh pr create:"
expect "gh pr create -t 'Use e.g. this' --fill" "the commits of --fill"
expect "gh pr create --title 'Add it' --body 'B' )" "couldn't read it as Bash"
printf 'Use a tool, such as Vale.\n' >notes.md
expect "gh pr create --title 'Add it' --body 'Use a tool, such as Vale.'"
expect "gh issue comment 1 -F notes.md"
# A command that only sets a variable holds no text to check, and the hook
# passes it, gh or not.
expect 'today=$(date); echo "$today"'
expect 'body=$(cat notes.md); gh pr list'
expect 'gh issue comment 1 --body "$text"' "The hook can't read the body of gh issue comment, as the command makes it when it runs"
expect "gh issue comment 1 --body-file missing.md" "missing.md isn't there before the command runs"
# GitHub reads a relative link of a text from the page of the text, so the
# hook doesn't give the texts to the links check.
expect "gh pr create --title 'Add it' --body 'Read [the steps](setup.md).'"
[ -z "$(find . -maxdepth 1 -name '.claude-code.*')" ] || { echo "Failed: the hook should delete the copies of the texts."; failed=1; }

# The hook runs prose.sh with the bash on PATH, as the pre-commit jobs do
# with runner: bash. /bin/bash of macOS is bash 3.2, which has no mapfile.
mkdir "$dir/bin"
printf '#!/bin/sh\necho "$*" >>"%s"\nexec "%s" "$@"\n' "$dir/bash.log" "$(command -v bash)" >"$dir/bin/bash"
chmod +x "$dir/bin/bash"
PATH="$dir/bin:$PATH" expect "gh pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'" "Google.Latin (error)"
grep -q "prose.sh english " "$dir/bash.log" || { echo "Failed: the hook should run prose.sh with the bash on PATH, but that bash ran only:"; cat "$dir/bash.log"; failed=1; }

# A repository names the jobs that check the texts, and the hook runs only
# those: textlint would stop the length of the English sentence, and the
# Japanese one.
printf 'claude-code:\n  jobs:\n    - name: claude-code\n      args: english\n' >lefthook-repo.yml
expect "gh pr create --title 'Add it' --body \"\$(cat <<'EOF'
This body runs well past the length that a Japanese sentence may have, as an English sentence often does, and only Vale checks it.

この設定はすべてのファイルに効きます。この設定はルートに置くものである。
EOF
)\""
rm lefthook-repo.yml

# A newer tag that setup.sh puts changes the version that the hook runs.
# lefthook fetches it first, and the hook still prints only its JSON.
git -C "$dir/repofiles" commit -q --allow-empty -m "A newer version"
git -C "$dir/repofiles" tag v9.9.10
"$dir/repofiles/setup.sh" . >/dev/null
expect "gh pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'" "Google.Latin (error)"
[ -d "$(git rev-parse --git-path info/lefthook-remotes/repofiles-v9.9.10)" ] || { echo "Failed: the hook should fetch v9.9.10."; failed=1; }

[ "$failed" -eq 0 ] && echo "The cases of the hook passed."
exit "$failed"
