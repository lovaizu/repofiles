# Reads the syntax tree that `shfmt --to-json` makes of a Bash command, and
# prints the texts that each `gh issue` and `gh pr` command would keep: the
# values of --title or -t, --body or -b, and --body-file or -F. Each is
# {what, text}, {what, file}, or {what, text: null} when only running the
# command can show it, such as from a variable, or from the commits of
# --fill or the template of --template of a create command.

def joined: if any(.[]; . == null) then null else join("") end;
# The value of one part of a word, as the shell gives it. A
# `$(cat <<'EOF' ... EOF)` gives the body of its here-document, without
# the newlines at its end.
def part:
  if .Type == "Lit" or .Type == "SglQuoted" then .Value
  elif .Type == "DblQuoted" then
    [.Parts[]? | if .Type == "Lit" then .Value | gsub("\\\\(?<c>[\"\\\\$`])"; .c) else part end] | joined
  elif .Type == "CmdSubst" and ([.Stmts[0].Cmd.Args[]?.Parts[]?.Value] == ["cat"]) then
    [.Stmts[0].Redirs[]? | select(.Op == "<<") | .Hdoc | [.Parts[]? | part] | joined] | .[0] // null | if . == null then null else sub("\n+$"; "") end
  else null end;
def word: [.Parts[]? | part] | joined;

[.. | objects | select(.Type? == "CallExpr") | [.Args[]? | word] as $args |
  select($args[0] == "gh" and ($args[1] == "issue" or $args[1] == "pr")) |
  "gh \($args[1]) \($args[2])" as $cmd |
  range(3; $args | length) as $i | ($args[$i] // "") as $a |
  if $args[2] == "create" and ($a | test("^(--fill(-first|-verbose)?|-f|--template(=.*)?|-T.*)$")) then
    {what: "the body of \($cmd)", text: null}
  else
    ($a | capture("^(?<flag>--title|--body|--body-file|-t|-b|-F)(=(?<value>.*))?$") //
      capture("^(?<flag>-[tbF])(?<value>.+)$")) as $m |
    (if $m.value != null then $m.value else $args[$i + 1] end) as $value |
    if $m.flag == "--title" or $m.flag == "-t" then {what: "the title of \($cmd)", text: $value}
    elif $m.flag == "--body" or $m.flag == "-b" then {what: "the body of \($cmd)", text: $value}
    elif $value == null then {what: "the body of \($cmd)", text: null}
    else {what: "the body of \($cmd)", file: $value} end
  end]
