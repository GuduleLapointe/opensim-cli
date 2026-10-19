# Developers

## Layout

- `bin/opensim`: the dispatcher, `opensim COMMAND`; the commands are the executables of `libexec/`
- `libexec/setup`: the quick setup
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
composer install
tests/lib/bashunit tests/
```

The person is a file of answers (`FE_INPUT_FD`); dialog is a fake that logs its arguments and answers from a file, as in the kit.
