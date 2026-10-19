# opensim-cli

The command line to set up and manage OpenSimulator, in bash. It asks the questions and shows the results; the rules and the work are the [OpenSim engine](https://github.com/GuduleLapointe/opensim-engine)'s. It needs nothing else of the OpenSim ecosystem: not the core, not the helpers, not the modules.

**Under construction.** Only the first screen of the quick setup is there: it asks what to set up and a few answers, checks them with the engine and shows the setup they stand for. It does not create anything yet.

## Requirements

- bash 5, `jq`, `php-cli`
- [bash-tools](https://github.com/magicoli/bash-tools) (`bash-helpers` in the PATH, or its clone beside this one)
- the engine (`opensim-api` in the PATH, in `/usr/share/opensim-engine/bin`, or its clone beside this one)

## Usage

```bash
bin/opensim setup
```

```
What do you want to set up?
  1) A grid: its Robust and a first simulator
  2) A standalone: one simulator that is the whole grid
```

then, for a grid, the name of the grid, its login URI, the hypergrid (yes by default) and the avatar that owns it (name, password, email); for a standalone, the same with the name of the simulator, which is the grid. Everything else is proposed by the engine.

## Settings

`~/.opensimrc` is read first, it is a bash file: it can set the `PATH` (which `php`, which tools), `OPENSIM_API` (where the engine is), anything the tools need. The `.env` of this project is read by bash-tools.
