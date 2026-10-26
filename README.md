# opensim-cli

The command line to set up and manage OpenSimulator, in bash. It asks the questions and shows the results; the rules and the work are the [OpenSim engine](https://github.com/GuduleLapointe/opensim-engine)'s. It needs nothing else of the OpenSim ecosystem: not the core, not the helpers, not the modules.

**Under construction.** The quick setup asks what to set up and a few answers, checks them with the engine and shows the setup they stand for. Besides it: status, ports, start, stop, restart, console and install-dotnet. `dev/build.sh` makes the Debian package and the zip into `dist/`. The package installs the bash completion (`share/bash-completion/opensim`).

## Quick install

This will install OpenSimulator, OpenSim Engine and all required packages from official apt repository.

```
curl -fsSL https://raw.githubusercontent.com/GuduleLapointe/opensim-cli/refs/heads/dev/quick-install.sh -o quick-install.sh
chmod +x quick-install.sh
./quick-install.sh --setup
```

See `./quick-install.sh --help` for other options.

To run the installer on an SSH server, download it locally first, then run `./quick-install.sh --remote root@server --setup`.

For a Podman install, run the downloaded script as a file. It creates a persistent Ubuntu 26.04 container by default; choose another image with `--image` or `OPENSIM_CONTAINER_IMAGE`. Podman uses `CONTAINER_CONNECTION` if set, or `--connection=local` to force the local engine. Run `opensim setup` from the container terminal after installation.

## Requirements

- Bash 5+
- PHP CLI 8.2+ with cURL, intl, mbstring, MySQL and XML extensions
- `jq`
- MySQL or MariaDB server and client
- Root access or `sudo`
- `container-tools` and Podman (Podman installs); `podman-compose` (Compose support)
- `ssh` and `scp` (SSH installs)
- `dialog` (optional; plain prompts are supported)

## Features

### First installation: `quick-install.sh`

- [x] apt official repo (linux, stable by default)
- [x] from local git clone
- [x] from local deb packages
- [x] multi-platform testing through `container-tools` on Podman
- [ ] install as podman container
    - [x] create, start, stop and destroy preconfigured containers
    - [ ] use a single image with passed specific settings and mounts
    - [ ] map required tcp and udp ports (prerequisite: enable `opensim ports`)
    - [ ] hot change of required tcp and udp ports
    - [ ] enable terminal maintenance through ssh
- [ ] install as docker container
- [x] remote shortcut to install on a distant server
- [ ] advanced/expert install
- [ ] support Homebrew (macos)
- [ ] support [Alpine container](https://hub.docker.com/r/soupbowl/opensimulator)

### Command-line interface (CLI): `bin/opensim`

#### Commands

- [x] status
- [x] start [--simulators] [target...]
- [x] stop|restart [--simulators] [now] [target...]
- [ ] enable|disable <instance...>
- [ ] enable|disable <grid> search [<url prefix>]
- [ ] enable|disable <grid> economy [beta|gloebit] [<url prefix>]
- [ ] enable|disable <grid> profiles
- [x] console|screen <instance>
- [ ] command <instance> <text>|-
- [x] ports [instance...] [--publish|--ufw] [--private-address ADDRESS]

`opensim ports` lists configured listeners and their TCP/UDP protocol. `--publish`
prints Podman/Docker mappings; `--ufw` prints public firewall rules and comments
for private/console ports. Private mappings bind to `127.0.0.1` unless overridden.

#### Grids

- [x] setup

`opensim setup --prepare setup.json` collects answers without applying the setup
and saves them in a private file. Use `--config setup.json` to prefill a later setup or `--apply setup.json` to apply the confirmed configuration without further questions. Preparation and application require an engine that supports these modes.

`quick-install.sh --podman` uses this questionnaire before creating the target container. From a downloaded script, it installs the local CLI, engine and container tools first; a source checkout reuses its Composer dependencies. The proposed grid hostname comes from the selected Podman server; an explicit `login_uri` in the setup configuration takes precedence. Cancelling the questionnaire creates no target container. Add `--setup` to apply the confirmed settings after installation without repeating the questionnaire. Use `--region-config /path/to/Region.ini` to stage an existing region; its database and files must still be restored before activation.

To stage an existing region without a replacement region or database:

```bash
opensim setup --region-config /path/to/Region.ini --prepare setup.json
opensim setup --apply setup.json
```

This preserves the region's UUID and original settings and leaves the simulator disabled. Database/file restoration and source shutdown come before enabling it.

- [ ] import [grid] FILE [--grid] [--simulator] [--users] [--apply]
- [ ] web [grid] [show|check]
- [ ] web [grid] snippet <caddy|nginx|apache>
- [ ] next <grid> location [X,Y] [COUNT] [-e X,Y]
- [ ] ban [grid] <name|uuid>... [--output DIR]

#### Archives and backups

- [ ] save iar [GRID [SIM]] [options] [--keep N] FIRST LAST PATH [PASSWORD] [FILE]
- [ ] load iar [GRID [SIM]] [-m|--merge] FIRST LAST PATH [PASSWORD] [FILE]
- [ ] save oar [GRID [REGION|SIM]] [options] [--keep N] [FILE]
- [ ] load oar [GRID [REGION|SIM]] [--merge] [options] [FILE]
- [ ] backup [GRID [SIM]] [--logs] [--archives] [--output DIR] [--keep N]

#### This machine

- [ ] next port [-e PORT] [MIN] [COUNT]
- [ ] profile list|add|default|remove
- [ ] oar pack|info|check|unpack
- [ ] rest --url http://HOST:PORT --user USER (-- <command> | - | --repl)
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
