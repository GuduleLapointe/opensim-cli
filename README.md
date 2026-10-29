# OpenSim CLI

![Stable](https://img.shields.io/github/release/GuduleLapointe/opensim-cli?label=stable&color=green&include_prerelease) ![GitHub Tag](https://img.shields.io/github/tag/GuduleLapointe/opensim-cli?label=latest&include_prereleases) ![GitHub commits since latest release](https://img.shields.io/github/commits-since/GuduleLapointe/opensim-cli/latest?label=dev) ![PHP](https://img.shields.io/badge/PHP-8.2+-7884bf) ![Bash](https://img.shields.io/badge/bash-5+) [![License](https://img.shields.io/badge/license-AGPL--3.0-552b55)](LICENSE) ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/GuduleLapointe/opensim-cli/total) [![Donate](https://img.shields.io/badge/-Donate-yellow)](https://magiiic.org/donate/)

The command line to set up and manage OpenSimulator, in bash. It asks the questions and shows the results; the rules and the work are the [OpenSim engine](https://github.com/GuduleLapointe/opensim-engine)'s. It needs nothing else of the OpenSim ecosystem: not the core, not the helpers, not the modules.

**Under construction.** The quick setup asks what to set up and a few answers, checks them with the engine and shows the setup they stand for. Besides it: status, ports, start, stop, restart, console and install-dotnet. `dev/build.sh` makes the Debian package and the zip into `dist/`. The package installs the bash completion (`share/bash-completion/opensim`).

## Quick install

This will install OpenSimulator, OpenSim Engine and all required packages from official apt repository.

```
curl -fsSL https://raw.githubusercontent.com/GuduleLapointe/opensim-cli/refs/heads/dev/kickstart.sh -o kickstart.sh
chmod +x kickstart.sh
./kickstart.sh --setup
```

See `./kickstart.sh --help` for other options.

See our [wiki](https://github.com/GuduleLapointe/opensim-cli/wiki) for detailed instructions.

To run the installer on an SSH server, download it locally first, then run `./kickstart.sh --remote root@server --setup`.

## Requirements

- Bash 5+ (standard on Linux, `brew install bash` on macOS)
- PHP CLI 8.2+ with cURL, intl, mbstring, MySQL and XML extensions
- `jq`
- MySQL or MariaDB server and client
- Root access or `sudo`
- `ssh` and `scp` (SSH installs)
- `dialog` (optional; plain prompts are supported)

Fully tested on:

- Ubuntu 24.04 and 26.04
- Debian 12 and 13
- macOS 13.7.8 and later

## Features

### First installation: `kickstart.sh`

- [x] apt official repo (linux, stable by default)
- [x] from local git clone
- [x] from local deb packages
- [x] remote shortcut to install on a distant server
- [ ] advanced/expert install
- [ ] support Homebrew (macos)

### Command-line interface (CLI): `bin/opensim`

#### Commands

- [x] status
- [x] start [--simulators] [target...]
- [x] stop|restart [--simulators] [now] [target...]
- [x] enable|disable <instance...>
- [x] enable|disable <grid> search [<url prefix>]
- [x] enable|disable <grid> economy [beta|gloebit] [<url prefix>]
- [x] enable|disable <grid> profiles
- [x] console|screen <instance>
- [ ] command <instance> <text>|-
- [x] ports [instance...] [--ufw] [--private-address ADDRESS]

`opensim ports` lists configured listeners and their TCP/UDP protocol. `--ufw` prints public firewall rules and comments for private/console ports.

#### Grids

- [x] setup

`opensim setup --prepare setup.json` collects answers without applying the setup and saves them in a private file. Use `--config setup.json` to prefill a later setup or `--apply setup.json` to apply the confirmed configuration without further questions. Preparation and application require an engine that supports these modes.

To stage an existing region without a replacement region or database:

```bash
opensim setup --region-config /path/to/Region.ini --prepare setup.json
opensim setup --apply setup.json
```

This preserves the region's UUID and original settings and leaves the simulator disabled. Database/file restoration and source shutdown come before enabling it.

- [ ] import [grid] FILE [--grid] [--simulator] [--users] [--apply]
- [x] web [grid] [show|check]
- [x] web [grid] snippet <caddy|nginx|apache>
- [x] next <grid> location [X,Y] [COUNT] [-e X,Y]
- [x] ban [grid] <name|uuid>... [--output DIR]

#### Archives and backups

- [x] save iar [GRID [SIM]] [options] [--keep N] FIRST LAST PATH [PASSWORD] [FILE]
- [x] load iar [GRID [SIM]] [-m|--merge] FIRST LAST PATH [PASSWORD] [FILE]
- [x] save oar [GRID [REGION|SIM]] [options] [--keep N] [FILE]
- [x] load oar [GRID [SIM|REGION]] [--merge] [options] [FILE]
- [x] backup [GRID [SIM]] [--logs] [--archives] [--output DIR] [--keep N]

#### This machine

- [x] next port [-e PORT] [MIN] [COUNT]
- [ ] profile list|add|default|remove
- [ ] oar pack|info|check|unpack
- [x] rest --url http://HOST:PORT --user USER (-- <command> | - | --repl)
- [x] install-dotnet install the .NET runtime OpenSim needs (as root)

### Builds

- [x] apt .deb package (tested on debian 12 and 13, ubuntu 24.04 and 26.04, should work on other debian variants)
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
