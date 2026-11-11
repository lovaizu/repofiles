#!/bin/bash
# The Claude Code hook, which lefthook runs as the job claude-code before
# each `gh issue` and `gh pr` command, with the input of Claude Code on
# stdin. It gives the title, body and comment of the command, which never
# go into a commit, to prose.sh of each job that checks them, and denies the
# command when a check fails. A text that the hook can't read before the
# command runs fails too, as the checks never pass what they didn't check.
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
input="$(cat)"
"$here/install.sh" >&2 || exit 1
eval "$(MISE_LOCKED=1 MISE_TRUSTED_CONFIG_PATHS="$here/mise.toml" mise -C "$here" env -s bash)"

# A command that shfmt can't read holds texts that the hook can't find.
if ! texts="$(jq -r '.tool_input.command // empty' <<<"$input" | shfmt --to-json 2>/dev/null | jq -c -f "$here/lib/command-texts.jq")"; then
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "The command didn'"'"'t run: the hook couldn'"'"'t read it as Bash, so it couldn'"'"'t check the texts that it would keep on GitHub. Write it as plain Bash, with each text in the command or in a file that exists before it runs."}}'
  exit 0
fi
# The jobs that check the texts: those that the repository names in args of
# the job claude-code in its lefthook-repo.yml, as only it knows the
# languages of its Issues and pull requests, or else each job that is on.
if [ "$#" -gt 0 ]; then
  jobs=("$@")
else
  mapfile -t jobs < <(lefthook dump --format json | jq -r '.["pre-commit"].jobs // [] | .[] | select(.script == "prose.sh" and .skip != true) | .name')
fi
cwd="$(jq -r '.cwd // empty' <<<"$input")"
# prose.sh reads the settings from the directory of a file up to the root,
# where lefthook runs the job, so the copies go in a directory there.
work="$(mktemp -d "$PWD/.claude-code.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT
files=()
whats=()
reason=""
while IFS= read -r item; do
  what="$(jq -r .what <<<"$item")"
  file="$(jq -r '.file // empty' <<<"$item")"
  # GitHub reads a title as plain text, and a body as Markdown.
  case "$what" in "the title"*) path="${work##*/}/${#files[@]}.txt" ;; *) path="${work##*/}/${#files[@]}.md" ;; esac
  if [ -n "$file" ]; then
    [ "${file#/}" != "$file" ] || file="$cwd/$file"
    cp "$file" "$path" 2>/dev/null || { reason+="The hook can't read $what, as $file isn't there before the command runs. Write the text in the command, or in a file that exists before it runs."$'\n\n'; continue; }
  elif ! jq -je '.text // error' <<<"$item" >"$path" 2>/dev/null; then
    reason+="The hook can't read $what, as the command makes it when it runs, such as from a variable, the commits of --fill, or a template. Write the text in the command, or in a file that exists before it runs."$'\n\n'
    continue
  fi
  files+=("$path")
  whats+=("$what")
done < <(jq -c '.[]' <<<"$texts")

for job in "${jobs[@]}"; do
  [ "${#files[@]}" -gt 0 ] || break
  out="$("$here/prose.sh" "$job" "${files[@]}" 2>&1)" && continue
  for i in "${!files[@]}"; do out="${out//"${files[$i]}"/"${whats[$i]}"}"; done
  reason+="$out"$'\n\n'
done
[ -z "$reason" ] || jq -n --arg reason "The command didn't run: the checks stopped the text that it would keep on GitHub. The line numbers count from the first line of each text.

$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
