# opensim-cli

The command line to set up and manage OpenSimulator, in bash. It asks the questions and shows the results; the rules and the work are the [OpenSim engine](https://github.com/GuduleLapointe/opensim-engine)'s. It needs nothing else of the OpenSim ecosystem: not the core, not the helpers, not the modules.

**Under construction.** Only the first screen of the quick setup is there: it asks what to set up and a few answers, checks them with the engine and shows the setup they stand for. It does not create anything yet.

## Requirements

- bash 5, `jq`, `php-cli` and `dialog` (`brew install dialog`, `apt install dialog`)
- the dependencies, installed with `composer install`: [bash-tools](https://github.com/magicoli/bash-tools) and the [engine](https://github.com/GuduleLapointe/opensim-engine) (the packages link them in `vendor/magicoli/` instead)

## Usage

```bash
bin/opensim setup
```

```
Type: Grid | Standalone | Speculoos (soon) | OSGrid (soon)
```

then one form with every question, the engine's proposals filled in:

```
Grid name        Amy
Login URI        http://Amy.local:8002
Hypergrid        yes
Avatar name
Password
Password again
Email
```

For a standalone the name is the simulator's, which is the grid. What the engine refuses comes back with the form, answers kept. Back returns to the type, Quit leaves. Without a terminal (a script) the questions are plain lines, a number edits an answer (`:back`, `:quit`).

## Settings

`~/.opensimrc` is read first, it is a bash file: it can set the `PATH` (which `php`, which tools) or anything the tools need. The `.env` of this project is read by bash-tools. 