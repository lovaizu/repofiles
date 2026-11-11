#!/bin/bash
# Runs the Claude Code hook, by the command of the .claude/settings.json
# that setup.sh puts, in a repository that setup.sh sets up from a clone of
# this repository at a tag of its own. Claude Code gives the hook its input
# on stdin, and reads the JSON on stdout.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# Runs the hook with the Bash command $1, and fails the test when the hook
# doesn't exit $2 with each text that the rest names, or prints a line that
# matches the extended regular expression $3, if any. A hook that prints
# anything prints only JSON.
expect() {
  local command="$1" code="$2" left="$3" out status want
  shift 3
  out="$(jq -n --arg cwd "$PWD" --arg command "$command" '{session_id: "test", hook_event_name: "PreToolUse", cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' | sh -c "$hook" 2>&1)"
  status=$?
  for want in "$@"; do
    grep -qF -- "$want" <<<"$out" || status="$status, without $want"
  done
  [ -z "$left" ] || ! grep -qE -- "$left" <<<"$out" || status="$status, with $left"
  [ "$code" -ne 0 ] || [ -z "$out" ] || jq -e . >/dev/null 2>&1 <<<"$out" || status="$status, with output that isn't JSON"
  if [ "$status" != "$code" ]; then
    echo "Failed: the hook should exit $code on $command with $*, but it exited $status with:"
    echo "$out"
    failed=1
  fi
}

git clone -q "$here" "$dir/repofiles"
git -C "$dir/repofiles" checkout -q "$(git -C "$here" rev-parse HEAD)"
git -C "$dir/repofiles" tag v9.9.9
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$dir/repofiles.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/lovaizu/repofiles
git init -q "$dir/repo"
cd "$dir/repo" || exit 1
"$dir/repofiles/setup.sh" . >/dev/null || { echo "Failed: setup.sh should set up the repository."; exit 1; }
# The command of each hook, one for gh issue and one for gh pr.
hook="$(jq -r '[.hooks.PreToolUse[].hooks[].command] | unique | if length == 1 then .[0] else error("the hooks should run one command") end' .claude/settings.json)" ||
  { echo "Failed: .claude/settings.json should run the same command for gh issue and gh pr."; exit 1; }
lefthook install >/dev/null
fail_en="$(cat "$here/tests/cases/english/fail-english.md")"
pass_en="$(cat "$here/tests/cases/english/pass-english.md")"
fail_ja="$(cat "$here/tests/cases/japanese/fail-japanese.md")"

# With both languages on, each job checks each text, with the settings of
# the root. A finding that stops the text stops the command, and the
# findings name the text. A clean text passes with no output, and a command
# with no text of an Issue or a pull request isn't checked.
expect "gh pr create --title 'Add the hook' --body '$fail_en'" 0 "" '"permissionDecision": "deny"' "Vale on the body of gh pr create:" "Google.Latin (error)" "These findings stop the command:"
expect "gh issue create --title 'Add the hook' --body '$fail_ja'" 0 "" '"permissionDecision": "deny"' "textlint on the body of gh issue create:" "no-mix-dearu-desumasu (error)"
expect "gh pr edit 1 --title 'Use e.g. this'" 0 "" '"permissionDecision": "deny"' "Vale on the title of gh pr edit:"
printf '%s\n' "$pass_en" >notes.md
expect "gh issue comment 1 --body-file notes.md" 0 "."
expect "gh pr view 1 && git commit -m 'Use e.g. this.'" 0 "."
# With the Japanese job off, only Vale checks the text. A setting of the
# repository changes the level of a finding, and a finding at a lower level
# reaches the agent and doesn't stop the command.
printf 'pre-commit:\n  jobs:\n    - name: japanese\n      skip: true\n' >lefthook-repo.yml
printf '[*]\nGoogle.Latin = suggestion\n' >.vale.ini
expect "gh pr create --title 'Add the hook' --body '$fail_en'" 0 "deny|textlint" '"additionalContext"' "Google.Latin (suggestion)" "don't stop the command"
# What the hook can't check, it says, to the user and to the agent.
expect 'gh issue comment 1 --body "$text"' 0 deny '"systemMessage"' "didn't check the body of gh issue comment, as the command makes it when it runs"
expect "gh issue comment 1 --body-file missing.md" 0 deny '"systemMessage"' "missing.md isn't there before the command runs"
# The hook leaves no copy of a text in the repository.
[ -z "$(find . -maxdepth 1 -name '.claude-code.*')" ] || { echo "Failed: the hook should delete the copies of the texts."; failed=1; }

# A newer tag that setup.sh puts changes the version that the hook runs.
# lefthook fetches it on the first run, and the hook still gives only JSON.
git -C "$dir/repofiles" commit -q --allow-empty -m "A newer version"
git -C "$dir/repofiles" tag v9.9.10
"$dir/repofiles/setup.sh" . >/dev/null
rm .vale.ini
expect "gh pr create --title 'Add the hook' --body '$fail_en'" 0 "" '"permissionDecision": "deny"' "Google.Latin (error)"
[ -d "$(git rev-parse --git-path info/lefthook-remotes/repofiles-v9.9.10)" ] || { echo "Failed: the hook should fetch the version v9.9.10."; failed=1; }
# Without the hook in the lefthook config, the hook fails, and Claude Code
# shows the error to the user.
printf 'pre-commit:\n  jobs:\n    - run: "true"\n' >lefthook.yml
expect "gh pr create --title 'Add the hook' --body '$fail_en'" 1 "" "hook claude-code doesn't exist"

[ "$failed" -eq 0 ] && echo "The cases of the hook passed."
exit "$failed"
