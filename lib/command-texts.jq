# Reads the syntax tree that `shfmt --to-json` makes of a Bash command, and
# prints the texts that the command would keep on GitHub: the title, body
# or comment of each `gh issue` and `gh pr` command. Each text is
# {what, text}, {what, file} when the text is in a file, or
# {what, text: null} when the command builds it in a way that only running
# it can show, such as from a variable.

def joined: if any(.[]; . == null) then null else join("") end;

# The value of one part of a word, as the shell would give it.
def part:
  if .Type == "Lit" then .Value
  # A $'' string gives its escapes, such as \n, as the characters that they name.
  elif .Type == "SglQuoted" and .Dollar then
    .Value | gsub("\\\\(?<c>[nt\\\\'\"])"; {"n": "\n", "t": "\t"}[.c] // .c)
  elif .Type == "SglQuoted" then .Value
  elif .Type == "DblQuoted" then
    [.Parts[]? | if .Type == "Lit" then .Value | gsub("\\\\(?<c>[\"\\\\$`])"; .c) else part end] | joined
  # `$(cat <<'EOF' ... EOF)` gives the body of the here-document, without the
  # newlines at its end, as a command substitution drops them.
  elif .Type == "CmdSubst" then
    if (.Stmts | length) == 1 and .Stmts[0].Cmd.Type == "CallExpr"
      and ([.Stmts[0].Cmd.Args[] | [.Parts[] | part] | joined] == ["cat"])
    then [.Stmts[0].Redirs[]? | select(.Op == "<<" or .Op == "<<-") | .Hdoc | [.Parts[]? | part] | joined]
      | if length == 1 and .[0] != null then .[0] | sub("\n+$"; "") else null end
    else null end
  else null end;
def word: [.Parts[]? | part] | joined;

# What the statement gives on stdin: a here-document or a here-string.
def stdin:
  [.Redirs[]? |
    if .Op == "<<" or .Op == "<<-" then .Hdoc | word
    elif .Op == "<<<" then (.Word | word) as $w | if $w == null then null else $w + "\n" end
  else empty end] | .[0];

# The values of the options in $long and $short, from args such as "-b",
# "x", "--body=x" and "-bx". $short holds the one-letter names.
def values($args; $long; $short):
  reduce range(0; $args | length) as $i ({next: false, out: []};
    $args[$i] as $a |
    if .next then .out += [$a] | .next = false
    elif $a == null then .
    elif any($long[]; . == $a) then .next = true
    elif any($long[]; . as $l | $a | startswith($l + "=")) then .out += [$a | sub("^[^=]*="; "")]
    elif ($a | test("^-[a-zA-Z]+$")) and any($short[]; . as $s | $a | endswith($s)) then .next = true
    elif ($a | test("^-[a-zA-Z]")) and any($short[]; . as $s | $a | startswith("-" + $s)) then .out += [$a[2:]]
    else . end) | .out;

def file_text($what; $file; $stdin):
  if $file == "-" then {what: $what, text: $stdin}
  elif $file == null then {what: $what, text: null}
  else {what: $what, file: $file} end;

[.. | objects | select((.Cmd | type) == "object" and .Cmd.Type == "CallExpr") |
  stdin as $stdin |
  [.Cmd.Args[] | word] as $args |
  select($args[0] == "gh" and any(["issue", "pr"][]; . == $args[1])
    and any(["create", "comment", "edit", "review", "close", "merge"][]; . == $args[2])) |
  "gh \($args[1]) \($args[2])" as $cmd |
  $args[3:] as $rest |
  (values($rest; ["--title"]; ["t"])[] | {what: "the title of \($cmd)", text: .}),
  # Only close takes a comment as a value. For review, --comment is a switch.
  (if $args[2] == "close" then [["--body", "--comment"], ["b", "c"]] else [["--body"], ["b"]] end) as $body |
  (values($rest; $body[0]; $body[1])[] | {what: "the body of \($cmd)", text: .}),
  (values($rest; ["--body-file"]; ["F"])[] | file_text("the body of \($cmd)"; .; $stdin))]
