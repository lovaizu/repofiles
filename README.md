# Lovaizu repofiles

The files that lovaizu repositories share, as dotfiles are for a home directory. `setup.sh` puts them into a repository, or updates them there, at a version of this repository. With these files, a repository runs the checks of this repository at that version before each commit and in CI.

The shared files hold no setting of a repository. A repository keeps its own settings, such as the files of each check, its vocabulary, `.vale.ini` and `.textlintrc`, in files that `setup.sh` doesn't change.

## Set up a repository

Install [mise](https://mise.jdx.dev/installing-mise.html) and [lefthook](https://lefthook.dev). Clone this repository, check out the tag of the version to put, and run `setup.sh` with the path of the repository:

```sh
git clone https://github.com/lovaizu/repofiles
git -C repofiles checkout v1.0.0
repofiles/setup.sh ~/work/lovaizu/telldes
```

`setup.sh` puts these files, each at that version:

- `lefthook.yml`, which names this repository in `remotes`, at the tag, with `english.yml` and `japanese.yml` in `configs`. It extends `lefthook-repo.yml`, the lefthook settings of the repository.
- `.github/workflows/checks.yml`, which runs the action of this repository, at the commit of the tag, on every file.
- The hooks of `.claude/settings.json`, which check the text of an Issue or a pull request that Claude Code writes, as [Check what Claude Code writes](#check-what-claude-code-writes) says. `setup.sh` adds them to the settings of the repository, in place of those that it added before, and keeps the rest.

Then commit the files, and run `lefthook install` once in each clone of the repository. The first run installs the tools of `mise.toml` with the sha256 of `mise.lock`, and textlint and its rules with the integrity of `textlint/package-lock.json`, into `~/.cache/lovaizu-repofiles`.

`setup.sh` replaces only a file that it put, and writes a file only when it changes, so a second run with the same version changes nothing. Where the repository has a file of its own at the path of a shared file, `setup.sh` puts nothing and names that file.

To update a repository to a newer version, check out its tag in the clone of this repository, and run `setup.sh` again. The next commit fetches the new version of the checks.

### Move from lovaizu/checks

A repository that names lovaizu/checks in its `lefthook.yml` holds its own settings there. Move them first:

1. Move the jobs of `pre-commit` and any other setting of the repository from `lefthook.yml` to `lefthook-repo.yml`. Leave out `remotes`.
1. For each language that `configs` doesn't name, turn its job off in `lefthook-repo.yml` with `skip: true`.
1. Delete `lefthook.yml`, and the step `uses: lovaizu/checks@...` of the workflow that runs it.
1. Run `setup.sh`.

## Check what Claude Code writes

A Claude Code agent writes the title and body of each Issue and pull request, and each comment on them, with `gh`. These texts never go into a commit, so no commit hook checks them. Before Claude Code runs a `gh issue` or `gh pr` command, the hook checks its title, body and comment, and when a finding stops the text, the command doesn't run, and the agent gets the findings. The hook checks neither files, which the commit hook checks, nor commit messages, which the checks don't read.

The hook runs `lefthook run claude-code`, so lefthook runs the hook of this repository at the tag of `lefthook.yml`, and fetches a new tag on its first run. The [`if` field](https://code.claude.com/docs/en/hooks) of each hook starts it only for a `gh issue` or `gh pr` command. A text has no path, so each job that `lefthook-repo.yml` doesn't turn off checks it, with the settings in the root of the repository. GitHub reads a title as plain text, and a body or a comment as Markdown, and the checks read each in that format. When the command makes a text as it runs, such as from a variable, the hook says that it didn't check it. A finding at a lower level reaches the agent and doesn't stop the command.

## Release a version

A version is a tag of this repository, as each repository names its version by its tag in `lefthook.yml`, and by the commit of the tag in its workflow. To release one:

1. Merge the changes to `main`, with the tests passing.
1. Tag the commit of `main` with the next version, by [Semantic Versioning](https://semver.org), and push the tag:

   ```sh
   git tag v1.1.0 origin/main
   git push origin v1.1.0
   ```

1. Update each repository with `setup.sh` from that tag.

A change that a repository must follow, such as a new file of settings, is a major version, and the release says what to change.

## What it checks

The checks are for the text that people and agents read. They stop text that falls short of the standard, so that the writer looks at it again and rewrites it for its reader.

The checks of each language:

- `english` of `english.yml` checks the English, by [Vale](https://vale.sh) with the [Google developer documentation style](https://developers.google.com/style).
- `japanese` of `japanese.yml` checks the Japanese, by [textlint](https://textlint.org). It runs these rules:
  - [`textlint-rule-preset-ja-technical-writing`](https://github.com/textlint-ja/textlint-rule-preset-ja-technical-writing)
  - [`@textlint-ja/textlint-rule-preset-ai-writing`](https://github.com/textlint-ja/textlint-rule-preset-ai-writing)
  - [`textlint-rule-ja-hiragana-keishikimeishi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-keishikimeishi), [`textlint-rule-ja-hiragana-hojodoushi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-hojodoushi) and [`textlint-rule-ja-hiragana-fukushi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-fukushi)
  - [`textlint-rule-ja-space-between-half-and-full-width`](https://github.com/textlint-ja/textlint-rule-ja-space-between-half-and-full-width), with `space: never`
  - `ja-no-unneeded-comma` of this repository, in [`textlint/unneeded-comma.mjs`](textlint/unneeded-comma.mjs). It finds the comma `、` after the clause at the head of a sentence, where the clause can modify only one part of the rest. By default, the clause has at most 30 characters, and the sentence at most 60. The options `maxHead` and `maxSentence` change these.
  - [`textlint-rule-prh`](https://github.com/textlint-rule/textlint-rule-prh), when the repository names its dictionary
  - The filters [`textlint-filter-rule-allowlist`](https://github.com/textlint/textlint-filter-rule-allowlist) and [`textlint-filter-rule-comments`](https://github.com/textlint/textlint-filter-rule-comments)

Each tool reads a file in the format that its extension names. textlint reads Markdown and plain text, and a file of another format fails the check, with the extensions that textlint reads, so give the job `japanese` only those files. The checks read text in UTF-8 alone. A file in another encoding fails the check. A file with a null byte, such as an image, holds no text, so it passes. A check that a tool fails to run fails too, with all that the tool printed.

A finding at the level warning or error stops the commit. A finding at a lower level, suggestion in Vale and info in textlint, shows in the report and doesn't stop the commit. Each rule keeps the level that its tool gives it.

The report says what the checks are for before the findings, and again in short after them.

## Choose the files of each check

Each language has a job of its own in `lefthook.yml`, as which languages a repository holds, and in which files, is the case of each repository. Neither job has a glob of its own, so a job checks each staged file unless you give it its files with `glob` and `exclude` in `lefthook-repo.yml`. The settings of the checks take precedence over those of `lefthook-repo.yml`, so `lefthook-repo.yml` can add a setting to a job, and can't change one that the checks set, such as its script.

For a repository that holds only English, turn off the job `japanese` with `skip: true`. The job `english` checks each staged file, including the files that hold no prose, such as `LICENSE`, a lockfile and `.claude/settings.json`, and their findings stop the commit. Leave those files out with `exclude`. Which files to leave out is the case of your repository. For example:

```yaml
pre-commit:
  jobs:
    - name: english
      exclude:
        - LICENSE
        - "*.lock"
        - .claude/settings.json
    - name: japanese
      skip: true
```

For a repository that holds only Japanese, turn off the job `english`, and give the job `japanese` only the files of a format that textlint reads, such as Markdown. Each other file that you stage, such as `lefthook.yml` and `.textlintrc`, fails the check. For example:

```yaml
pre-commit:
  jobs:
    - name: english
      skip: true
    - name: japanese
      glob: "*.md"
```

With the default glob matcher of lefthook, `*.md` matches a Markdown file in any directory.

For a repository that holds both languages, give each job its files, or each job checks the files of the other language too. A file that holds both languages goes to both jobs only if you give it to both. For example, for English files in the root and Japanese files in `docs/ja`:

```yaml
glob_matcher: doublestar
pre-commit:
  jobs:
    - name: english
      glob: "*.md"
      exclude:
        - "notes/**"
    - name: japanese
      glob: "docs/ja/**/*.md"
```

With [`glob_matcher: doublestar`](https://lefthook.dev/configuration/glob_matcher/), `*.md` matches only the files in the root, and `docs/ja/**/*.md` matches the files in `docs/ja` and below. `ci.sh` fails when both jobs are off, as it would check nothing.

## Change a setting

Change a setting when the case of your repository needs it. The people of the repository decide it, not an agent that wants a finding to go away. Write only what you change: the checks lay your file over their defaults. The checks find the settings of each file from the directory of the file up to the root of the repository, and no further. So a settings file applies to each file in its directory and below, and a file with none gets the defaults alone. To leave out a file, use `exclude` of its job in `lefthook-repo.yml`.

### English

Write a `.vale.ini` of your own. Vale reads [`vale/.vale.ini`](vale/.vale.ini) as its defaults, and lays over them the nearest `.vale.ini`, `_vale.ini` or `vale.ini`. For example, to make a rule stop the commit, and to allow the words of your own vocabulary:

```ini
StylesPath = styles
Vocab = Team

[*]
Google.Passive = warning
```

Vale then reads `styles/config/vocabularies/Team/accept.txt`. To leave out a pattern, such as a path, name it in [`TokenIgnores`](https://vale.sh/docs/keys/tokenignores) or [`BlockIgnores`](https://vale.sh/docs/keys/blockignores). Vale applies them only to the formats of markup, such as Markdown.

### Japanese

Write a `.textlintrc` of your own, in JSON or YAML, or the field `textlint` of `package.json`. textlint reads only one settings file, so the checks merge yours into [`textlint/.textlintrc.json`](textlint/.textlintrc.json), and give textlint the result. For example, to show a rule without stopping the commit, to allow a word, and to name a dictionary of `prh`:

```yaml
rules:
  preset-ja-technical-writing:
    sentence-length:
      severity: info
  prh:
    rulePaths:
      - prh.yml
filters:
  allowlist:
    allow:
      - 御社
```

Your file changes only the part that it names:

- An object adds its keys to those of the defaults, and each value of a key that both have merges the same way.
- A key with no value, such as `rules:` with nothing under it, changes nothing.
- `true` turns on a rule and keeps the options of the defaults, including those of a preset.
- An array adds its items to those of the defaults.
- `false`, or any other value, takes the place of the default.
- A rule, a preset or a filter is the same by its short name, such as `prh`, and by the name of its package, such as `textlint-rule-prh`.
- The checks read a path in the options of `prh` and `allowlist` from the directory of your file.

A `.textlintrc.js` or `.textlintrc.cjs` fails the check, as JavaScript can't merge into the defaults. To leave out a part of a file, use the comments of `textlint-filter-rule-comments`, such as `<!-- textlint-disable -->`.

## Change the checks

- A tool: change its version in `mise.toml`, then run `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64`.
- textlint or a rule: change its version in `textlint/package.json`, then run `npm install --package-lock-only --ignore-scripts` in `textlint`.

`tests/run.sh` checks that each case in `tests/cases/english` and `tests/cases/japanese` passes, shows, or fails as its name says, and checks each thing that the checks must do with one case. `tests/setup.sh` runs `setup.sh` on a new repository, on one with its own `lefthook.yml`, and again at the same tag and at a newer one. `tests/consumer.sh` runs `ci.sh` and a commit in a repository that `setup.sh` sets up, with one language and with both, with its own globs, `.vale.ini` and `.textlintrc`. `tests/claude.sh` runs the hook by the command of `.claude/settings.json` in a repository that `setup.sh` sets up. `tests/run.sh` also checks the texts that `lib/command-texts.jq` finds in commands.
