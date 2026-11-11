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
# Runs the hook on the Bash command $1, as Claude Code does, and fails the
# test unless it denies the command with text $2, or, with no $2, prints
# nothing.
expect() {
  local out
  out="$(jq -n --arg cwd "$PWD" --arg command "$1" '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' | sh -c "$hook" 2>&1)"
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
"$dir/repofiles/setup.sh" . >/dev/null
hook="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' .claude/settings.json)"
# Without lefthook install, and with no way to fetch the version, lefthook
# can't run the job, and the hook stops the command with exit 2, which
# Claude Code reads as a denial.
out="$(jq -n --arg cwd "$PWD" '{cwd: $cwd, tool_name: "Bash", tool_input: {command: "gh pr create --title A --body B"}}' | env -u GIT_CONFIG_COUNT sh -c "$hook" 2>&1)"
status=$?
[ "$status" -eq 2 ] && [ "$out" = "The text of this command wasn't checked, as lefthook couldn't run the checks. Fix: install lefthook, and run lefthook install in this repository." ] ||
  { echo "Failed: the hook should exit 2 with one line when lefthook can't run the job, but it exited $status with:"; echo "$out"; failed=1; }
lefthook install >/dev/null

expect "gh pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'" "Vale on the body of gh pr create:"
expect "gh issue create --title 'Add it' --body \"\$(cat <<'EOF'
この設定はすべてのファイルに効きます。この設定はルートに置くものである。
EOF
)\"" "no-mix-dearu-desumasu (error)"
expect "gh pr edit 1 --title 'Use e.g. this'" "Vale on the title of gh pr edit:"
printf 'Use a tool, such as Vale.\n' >notes.md
expect "gh pr create --title 'Add it' --body 'Use a tool, such as Vale.'"
expect "gh issue comment 1 -F notes.md"
expect 'gh issue comment 1 --body "$text"' "The hook can't read the body of gh issue comment, as the command makes it when it runs"
expect "gh issue comment 1 --body-file missing.md" "missing.md isn't there before the command runs"
[ -z "$(find . -maxdepth 1 -name '.claude-code.*')" ] || { echo "Failed: the hook should delete the copies of the texts."; failed=1; }

# A newer tag that setup.sh puts changes the version that the hook runs.
# lefthook fetches it first, and the hook still prints only its JSON.
git -C "$dir/repofiles" commit -q --allow-empty -m "A newer version"
git -C "$dir/repofiles" tag v9.9.10
"$dir/repofiles/setup.sh" . >/dev/null
expect "gh pr create --title 'Add it' --body 'Use a tool, e.g. Vale.'" "Google.Latin (error)"
[ -d "$(git rev-parse --git-path info/lefthook-remotes/repofiles-v9.9.10)" ] || { echo "Failed: the hook should fetch v9.9.10."; failed=1; }

[ "$failed" -eq 0 ] && echo "The cases of the hook passed."
exit "$failed"
