#!/bin/bash
# The Claude Code hook of the checks, which lefthook runs as the job
# claude-code of claude-code.yml, with the input of Claude Code on stdin.
# The .claude/settings.json that setup.sh puts runs it by
# `lefthook run claude-code` before each `gh issue` and `gh pr` command, so
# lefthook runs this script at the version that lefthook.yml names. When
# that version is new, lefthook fetches it first and says so on stdout, so
# the command passes on only the lines from the JSON on.
#
# The hook checks the title, body and comment of the command, which never go
# into a commit, so no commit hook sees them. Such a text has no path, so
# each job of these checks that is on in the repository checks it, with
# prose.sh and the settings of the root of the repository. When a finding
# stops the text, the command doesn't run, and the findings go back to
# Claude Code, so that it rethinks the text. What the hook can't check, it
# says. It prints only the JSON that Claude Code reads, and exits 0 unless
# it can't print that JSON.
set -uo pipefail
unset CDPATH
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
input="$(cat)"
# Without jq, the hook can't print its JSON, so it fails, and Claude Code
# shows the first line of stderr.
"$here/install.sh" >&2 || exit 1
eval "$(MISE_LOCKED=1 MISE_TRUSTED_CONFIG_PATHS="$here/mise.toml" mise -C "$here" env -s bash)"

# lefthook runs the job in the root of the repository.
root="$(pwd -P)"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -d "$cwd" ] || cwd="$root"
fails=""
shows=""
notes=()
work=""
trap '[ -z "$work" ] || rm -rf "$work"' EXIT

# Prints the result as the JSON of a PreToolUse hook.
answer() {
  local note=""
  [ "${#notes[@]}" -gt 0 ] && note="lovaizu/repofiles: ${notes[*]}"
  jq -n --arg fails "$fails" --arg shows "$shows" --arg note "$note" '
    ([if $fails != "" then "The checks found these problems in the text that this command would keep, so the command didn'"'"'t run. Rethink the text, then run the command again. The line numbers count from the first line of each text.\n\n\($fails)" else empty end,
      if $shows != "" then "The checks found these in the text that this command keeps, which don'"'"'t stop it. Rethink each one too.\n\n\($shows)" else empty end,
      if $note != "" then $note else empty end] | join("\n\n")) as $context |
    (if $fails != "" then
      {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $context}}
    elif $context != "" then {hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $context}}
    else empty end)
    + (if $note != "" then {systemMessage: $note} else {} end)'
}

command="$(jq -r '.tool_input.command // empty' <<<"$input")"
# shfmt parses the command as Bash does, here-documents and quotes too,
# without running any of it. A command that it can't parse fails in Bash
# too, so the hook doesn't check it.
texts="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -c -f "$here/lib/command-texts.jq" 2>/dev/null)" || exit 0
[ "$texts" != "[]" ] || exit 0

# The jobs of these checks in the pre-commit hook of the repository that
# are on, the jobs that run prose.sh. The name of each is the language that
# it checks.
mapfile -t jobs < <(lefthook dump --format json 2>/dev/null | jq -r '.["pre-commit"].jobs // [] | .[] | select(.script == "prose.sh" and .skip != true) | .name')
if [ "${#jobs[@]}" -eq 0 ]; then
  notes+=("The pre-commit hook of lefthook.yml in $root has no job of these checks that is on, so the hook checked nothing. Fix: leave at least one language on in lefthook-repo.yml.")
  answer
  exit 0
fi

# prose.sh reads a file from the root, as each file gets the settings from
# its directory up to the root, so the copies go in a directory of the root.
i=0
files=()
whats=()
while IFS= read -r item; do
  what="$(jq -r .what <<<"$item")"
  file="$(jq -r '.file // empty' <<<"$item")"
  if [ -n "$file" ]; then
    case "$file" in /*) ;; *) file="$cwd/$file" ;; esac
    if [ ! -f "$file" ]; then
      notes+=("The hook didn't check $what, as $file isn't there before the command runs.")
      continue
    fi
  elif jq -e '.text == null' <<<"$item" >/dev/null; then
    notes+=("The hook didn't check $what, as the command makes it when it runs, such as from a variable. Write the text in the command, or in a file that exists before it runs.")
    continue
  fi
  [ -n "$work" ] || work="$(mktemp -d "$root/.claude-code.XXXXXX")" || exit 1
  i=$((i + 1))
  # GitHub reads a title as plain text, and a body or a comment as
  # Markdown.
  case "$what" in "the title of"*) ext=txt ;; *) ext=md ;; esac
  path="${work#"$root/"}/text-$i.$ext"
  if [ -n "$file" ]; then cp "$file" "$root/$path"; else jq -j .text <<<"$item" >"$root/$path"; fi
  files+=("$path")
  whats+=("$what")
done < <(jq -c '.[]' <<<"$texts")

for job in "${jobs[@]}"; do
  [ "${#files[@]}" -gt 0 ] || break
  out="$("$here/prose.sh" "$job" "${files[@]}" 2>&1)"
  status=$?
  for i in "${!files[@]}"; do out="${out//"${files[$i]}"/"${whats[$i]}"}"; done
  # The report of prose.sh speaks of a commit, and here it stops a command.
  out="${out//stop the commit/stop the command}"
  [ -n "$out" ] || continue
  if [ "$status" -eq 0 ]; then shows+="$out"$'\n\n'; else fails+="$out"$'\n\n'; fi
done
answer
exit 0
