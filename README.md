# Lovaizu repofiles

The files that lovaizu repositories share, as dotfiles are for a home directory. With them, each repository runs the same checks of its prose before each commit, in CI, and before Claude Code posts an Issue or a pull request. The checks stop text that falls short, so that the writer rethinks it for its reader.

`setup.sh` puts the files into a repository at a version of this one, and a repository updates them by running it again at a newer version. A repository keeps its own settings in files that `setup.sh` doesn't write.

## Set up or update a repository

Install [mise](https://mise.jdx.dev/installing-mise.html) and [lefthook](https://lefthook.dev). Then, in a clone of this repository, check out the tag of the version, and run `setup.sh` with the path of the repository:

```sh
git -C repofiles checkout v1.0.0
repofiles/setup.sh ~/work/lovaizu/telldes
```

`setup.sh` puts `lefthook.yml`, `.github/workflows/checks.yml` and `.claude/settings.json`, each with that version. It never overwrites a file that it didn't put, and names any such file. Commit the files, and run `lefthook install` once in each clone of the repository.

To update, check out the newer tag, and run `setup.sh` again.

## Settings of a repository

`lefthook-repo.yml` holds the lefthook settings of the repository: the files of each check, and the checks that it turns off. For example, to leave out `LICENSE` and to turn off the Japanese check:

```yaml
pre-commit:
  jobs:
    - name: english
      exclude:
        - LICENSE
    - name: japanese
      skip: true
```

A `.vale.ini` or `.textlintrc` in the repository changes the rules of the check of its directory and below. The docs of [Vale](https://vale.sh/docs/vale-ini) and [textlint](https://textlint.org/docs/configuring) say how to write each file. The checks lay the settings of the file over their own, so write only what you change.

## What the checks check

A finding at the level warning or error stops the text, and a lower one only shows.

- `english` checks English by [Vale](https://vale.sh) with the [Google developer documentation style](https://developers.google.com/style).
- `japanese` checks Japanese by [textlint](https://textlint.org), with these rules:
  - [`textlint-rule-preset-ja-technical-writing`](https://github.com/textlint-ja/textlint-rule-preset-ja-technical-writing)
  - [`@textlint-ja/textlint-rule-preset-ai-writing`](https://github.com/textlint-ja/textlint-rule-preset-ai-writing)
  - [`textlint-rule-ja-hiragana-keishikimeishi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-keishikimeishi), [`textlint-rule-ja-hiragana-hojodoushi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-hojodoushi) and [`textlint-rule-ja-hiragana-fukushi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-fukushi)
  - [`textlint-rule-ja-space-between-half-and-full-width`](https://github.com/textlint-ja/textlint-rule-ja-space-between-half-and-full-width), with `space: never`
  - `ja-no-unneeded-comma` of [`textlint/unneeded-comma.mjs`](textlint/unneeded-comma.mjs), which finds a comma `、` that a short sentence doesn't need
  - [`textlint-rule-prh`](https://github.com/textlint-rule/textlint-rule-prh), when the repository names its dictionary
  - The filters [`textlint-filter-rule-allowlist`](https://github.com/textlint/textlint-filter-rule-allowlist) and [`textlint-filter-rule-comments`](https://github.com/textlint/textlint-filter-rule-comments)

The Claude Code hook gives the title, body and comment of each `gh issue` and `gh pr` command to these checks before the command runs, and stops the command on a finding that stops the text.

## Release a version

A version is a tag of this repository. Merge the changes to `main` with the tests passing, then tag that commit by [Semantic Versioning](https://semver.org), and push the tag:

```sh
git tag v1.1.0 origin/main
git push origin v1.1.0
```

After a change of a tool in `mise.toml`, run `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64`, so that each platform has its sha256 in `mise.lock`.
