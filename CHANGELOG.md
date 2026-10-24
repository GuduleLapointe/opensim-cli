## Changelog

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
