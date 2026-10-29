## Changelog

### Unreleased

- fix: duplicate build-tools package in require and require-dev

### 3.0.0-beta.4

- magicoli/container-tools => ^0.1.0@alpha
- magicoli/opensim-engine => ^3.0@beta
- magicoli/bash-tools => ^1.0
- magicoli/build-tools => ^0.1.11

### 3.0.0-beta.2

- fix (containers): map OpenSim user to bind mount owner
- fix (install): request all OpenSim packages on every install
- feature (cli): restore console, grid, web and archive commands
- feature (cli): add backups and reviewable user ban plans
- magicoli/build-tools 0.1.9 => 0.1.11
- magicoli/container-tools dev-master 0ed55d9 => 0.1.0-alpha.2

### 3.0.0-beta.1

- feature (install): apply confirmed setup and transfer private inputs
- feature (setup): accept existing region files through the cli
- feature (setup): apply a private prepared configuration from the cli
- feature (install): prepare setup through the local engine before podman creation
- feature (setup): save collected answers before provisioning
- feature (cli): restore instance port reports
- feature (installer): configure apt sources
- feature (installer): prefill Podman setup from config
- feature (installer): install OpenSim in Podman
- feature (installer): support SSH installs
- fix (install): retain prepared database credentials through container setup
- fix (tests): report Podman connection failures in deployment checks
- fix (tests): validate persistent deployments across platforms
- fix (tests): load environment with project overrides
- doc: record validated setup port selection
- doc: track validated existing region staging and remaining migration work
- doc: record validated region move planning
- doc: extend container plan for existing regions and sqlite
- doc: record staged container setup plan
- doc (installer): document SSH installation
- doc (readme): list administrator access requirement
- doc (readme): simplify runtime requirements
- doc (contributing): add repository agent instructions
- doc (readme): update current features and install instructions
- refactor (tests): route container tests through container-tools
- test (install): prepare podman setup through the real engine
- test: isolate cli checks from the installed system layout
- test (tests): clarify command failure reporting
- update (installer): default Podman image to Ubuntu 26.04
- update (packaging): require podman-compose for cli
- dev swith to dev mode (sibling packkages from local sources, not suitable for release)

### 3.0.0-dev.1

Complete rewrite of opensim terminal tools, using new opensim-engine 3.x API

- new quick-install.sh: allow simple download and install all required packages
    - configurable sources : from git repo, local .deb package or official projet apt repo
    - configurable mode: full install or separate main packages, dotnet, opensim engine...
- rewrite opensim CLI, wrapper for all OpenSim controls:
    - status
    - start|stop|restart
    - console|screen
    - setup
- enhance opensim CLI: no more duplicate features, act as a wrapper, all features are provided globally by opensim-engine API, in a standadized way for all the apps of the ecosystem
- new extensive test suite
- work in progress, see README for upcoming features

**Enabled features**:

- `quick-install.sh`: automated installation script
    - apt official repo (linux, stable by default)
    - from local git clone
    - from local deb packages
    - multi-platform testing on podman containers
    - apt .deb package (tested on debian 12 and 13, ubuntu 24.04 and 26.04, should work on other debian variants)
    - zip (universal)
- status
- start [--simulators] [target...]
- stop|restart [--simulators] [now] [target...]
- console|screen <instance>
- setup
- install-dotnet install the .NET runtime OpenSim needs (as root)
