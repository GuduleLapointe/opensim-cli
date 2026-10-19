# Developers

## Layout

- `bin/opensim`: the dispatcher, `opensim COMMAND`; the commands are the executables of `libexec/`
- `libexec/setup`: the quick setup
- `src/lib/common`: what the commands share (bash-tools, the engine, the rc file); `src/lib/ask`: the questions (`ask`, `ask_secret`, `choose`)
- `tests/`: bashunit tests, with a stand-in for the engine (`tests/fixtures/opensim-api`)

## Rules

- The engine owns the rules and the work: the questions, their defaults, their validation, the setup they make. A command asks the engine (`opensim-api POST /setups/quick`), never decides. What a question is called and how it is asked is this tool's.
- The engine is reached through `opensim-api`, and the answers go through its standard input (a password is not an argument).
- Scripts source `src/lib/common` (it sources bash-tools, reads `~/.opensimrc` through the engine's `lib/rc-helpers`, finds the engine) and use the functions of bash-tools (`yesno`, `die`, `require`, `debug`...).
- Dependencies stay `bash`, `jq`, `php-cli`, bash-tools and the engine.

## Tests

```bash
tests/lib/bashunit tests/
```

The answers of a person are lines on the standard input. `readvar` of bash-tools names the question after the variable and cannot hide what is typed: `ask`, `ask_secret` and `choose` do, they could go to bash-tools.
