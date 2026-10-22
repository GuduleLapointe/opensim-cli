# Developers

## Layout

- `bin/opensim`: the dispatcher, `opensim COMMAND`; the commands are the executables of `libexec/`
- `libexec/setup`: the quick setup
- `lib/bashunit`: Bashunit test runner, pinned as a Git submodule
- `src/lib/common`: what the commands share (bash-tools and the engine from `vendor/magicoli/`, the rc file); `src/lib/ui`: the questions (`ui_menu`, `ui_form`), dialog or plain, ported from `libexec/setup-frontend.sh` of the kit with the same conventions (`OPENSIM_SETUP_UI`, `FE_TTY`, `FE_INPUT_FD`, `FE_SCREEN`, Back and Quit)
- `tests/`: bashunit tests, with a stand-in for the engine (`tests/fixtures/opensim-api`)

## Rules

- The engine owns the rules and the work: the questions, their defaults, their validation, the setup they make. A command asks the engine (`opensim-api POST /setups/quick`), never decides. What a question is called and how it is asked is this tool's.
- The engine is reached through `opensim-api`, and the answers go through its standard input (a password is not an argument).
- Dependencies are composer's (or the packages' links in `vendor/magicoli/`): nothing is searched in the PATH or beside the project. `OPENSIM_API` names another engine, which is how the tests use a stand-in.
- Scripts source `src/lib/common` (it sources bash-tools, reads `~/.opensimrc` through the engine's `lib/rc-helpers`) and use the functions of bash-tools (`die`, `require`, `debug`...).
- All the questions of a setup are one form, never one question at a time. A label is the shortest word that says it.
- Dependencies stay `bash`, `jq`, `php-cli`, bash-tools and the engine.

## Tests

```bash
git clone --recurse-submodules https://github.com/GuduleLapointe/opensim-cli.git
composer install
composer test
```

For an existing clone, initialize Bashunit with
`git submodule update --init --recursive`. The submodule is pinned to release 0.50.1. Run only the
compatibility suite with `./lib/bashunit/bashunit tests/Compatibility`.

The person is a file of answers (`FE_INPUT_FD`); dialog is a fake that logs its arguments and answers from a file, as in the kit.

## Commit message format

```
type (scope): short subject

- detail
- detail

Optional additional context.
```

- **type**: lowercase, no trailing period, type of change (e.g. `feature`, `fix`, `update`, `refactor`, `test`, `doc`)
- **scope**: area of the change — e.g. `api`, `lsl`, `build`, `tests`, `config`
- **subject**: imperative, lowercase, no trailing period
- **details**: bullet list with `-`, one item per logical change
- Omit details for trivial single-change commits
- Prefix with `(untested)` when the change has not been verified yet; reword after a successful test

## Version releases

Tag: 1.2.3 (no v prefix).

Changelog:

```
### 1.2.3 Main change if applicable
- new ...
- new ...
- fix ...
- update ...
```

Commit message and tag message strictly identical to changelog, with the version prefixed with "v" (needed by some parsing tools)

```
v1.2.3 Main change if applicable
- new ...
- new ...
- fix ...
- update ...
```

- **subject** first line begins exactly with "v" + the version number to allow automated workflows and maintenance scripts. An option description of the main change might be added if relevant
- **details** a list of the main changes since the previous version release commit
- create a version release only when the version is fully tested and approved: bumping the version number in files does not mean the version must be released yet
- Be concise, full explanation can be found in git history
- Omit small patches and fixes, focus on essential features
- Make sure to update all relevant files (.version, README.md, composer.json... ) and update CHANGELOG.md with the exact same description
- Replace `dev-dev` requires with released constraints (e.g. `^1.0`) and run `composer update` so that `composer.lock` no longer points to local paths, otherwise the release cannot be installed on another machine. Switch back to `dev-dev` after the release
- after commit, add a tag named with the bare version number ("1.2.3"), with the exact same message as the commit (starting with "v1.2.3")
