# opensim-cli

The command line to set up and manage OpenSimulator, in bash. It asks the questions and shows the results; the rules and the work are the [OpenSim engine](https://github.com/GuduleLapointe/opensim-engine)'s. It needs nothing else of the OpenSim ecosystem: not the core, not the helpers, not the modules.

**Under construction.** The quick setup asks what to set up and a few answers, checks them with the engine and shows the setup they stand for. Besides it: status, start, stop, restart, console and install-dotnet. `dev/build.sh` makes the Debian package and the zip into `dist/`. The package installs the bash completion (`share/bash-completion/opensim`).

## Quick install

This will install OpenSimulator, OpenSim Engine and all required packages from official apt repository.

```
curl -o https://raw.githubusercontent.com/GuduleLapointe/opensim-cli/refs/heads/dev/quick-install.sh
chmod +x quick-install.sh
./quick-install.sh --setup
```

See `./quick-install.sh --help` for other options.

## Requirements

- bash 5, `jq`, `php-cli` and `dialog` (`brew install dialog`, `apt install dialog`)
- the dependencies, installed with `composer install`: [bash-tools](https://github.com/magicoli/bash-tools) and the [engine](https://github.com/GuduleLapointe/opensim-engine) (the packages link them in `vendor/magicoli/` instead)

## Features

Commands:

- [x] status
- [x] start [--simulators] [target...]
- [x] stop|restart [--simulators] [now] [target...]
- [ ] enable|disable <instance...>
- [ ] enable|disable <grid> search [<url prefix>]
- [ ] enable|disable <grid> economy [beta|gloebit] [<url prefix>]
- [ ] enable|disable <grid> profiles
- [x] console|screen <instance>
- [ ] command <instance> <text>|-
- [ ] ports [instance...] [--publish|--ufw]

Grids

- [x] setup
- [ ] import [grid] FILE [--grid] [--simulator] [--users] [--apply]
- [ ] web [grid] [show|check]
- [ ] web [grid] snippet <caddy|nginx|apache>
- [ ] next <grid> location [X,Y] [COUNT] [-e X,Y]
- [ ] ban [grid] <name|uuid>... [--output DIR]

Archives and backups

- [ ] save iar [GRID [SIM]] [options] [--keep N] FIRST LAST PATH [PASSWORD] [FILE]
- [ ] load iar [GRID [SIM]] [-m|--merge] FIRST LAST PATH [PASSWORD] [FILE]
- [ ] save oar [GRID [REGION|SIM]] [options] [--keep N] [FILE]
- [ ] load oar [GRID [REGION|SIM]] [--merge] [options] [FILE]
- [ ] backup [GRID [SIM]] [--logs] [--archives] [--output DIR] [--keep N]

This machine

- [ ] next port [-e PORT] [MIN] [COUNT]
- [ ] profile list|add|default|remove
- [ ] oar pack|info|check|unpack
- [ ] rest --url http://HOST:PORT --user USER (-- <command> | - | --repl)
- [x] install-dotnet install the .NET runtime OpenSim needs (as root)

Builds

- [x] apt (tested on debian 12 and 13, ubuntu 24.04 and 26.04, should work on other debian variants)
- [x] zip (universal)
- [ ] homebrew

## Usage

```bash
bin/opensim setup
```

```
Type: Grid | Standalone | Speculoos (soon) | OSGrid (soon)
```

then one form with every question, the engine's proposals filled in (Enter moves to the next field, the last one leads to OK):

```
Grid name        Amy
Login URI        Amy.local:8002
Avatar name
Password
Password again
Email
```

For a standalone the first field is `Region name`: the region is the simulator and the grid. What the engine refuses comes back with the form, answers kept (`Error: Email invalid`). Then the options, as check boxes (Hypergrid, checked; search, currency, OSSL will join it). Back goes one step back, Quit leaves. The setup the answers stand for is listed, every value the engine defines, by section:

```
* Grid name: Amy (amy)
* Login URI: http://Amy.local:8002
* Hypergrid: yes
...

* Simulator: Welcome (amy.welcome)
...
```

Without a terminal (a script) the questions are plain lines, a number edits an answer (`:back`, `:quit`).

## Settings

`~/.opensimrc` is read first, it is a bash file: it can set the `PATH` (which `php`, which tools) or anything the tools need. The `.env` of this project is read by bash-tools.

## User permissions

The files of the grids belong to the user the instances run as (`SystemUser` of `opensim.conf`). When it is not you, every command runs as that user with `sudo -u`, checked before the first question: you need to be allowed to.
