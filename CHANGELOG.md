## Changelog

### Unreleased

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
