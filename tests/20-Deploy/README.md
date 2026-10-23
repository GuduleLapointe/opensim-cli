# Deploy tests

Run the full test suite through the project test command:

```sh
composer test
```

It runs local application tests, then the package build, then deployment.
Bashunit marks dependent build and deployment tests as skipped when an
earlier check fails. Containers are removed by the final cleanup phase, after
all test groups have finished. The full suite uses Bashunit's default
alphabetical discovery. The numbered directories put local application tests
and the package build before deployment, and cleanup sorts last; platform
files remain grouped by operating system.

To run only deployment tests:

```sh
./lib/bashunit/bashunit tests/20-Deploy
```

`composer test` invokes the Bashunit executable from its submodule under
`lib/bashunit`. A direct run without paths discovers all files below `tests/`.
Bashunit loads `tests/bootstrap.sh` for each invocation, keeping environment
setup in one place.

Each platform has its own Bashunit file, so it can also be selected directly:

```sh
./lib/bashunit/bashunit tests/20-Deploy/debian-12-test.sh
./lib/bashunit/bashunit tests/20-Deploy/debian-13-test.sh
./lib/bashunit/bashunit tests/20-Deploy/ubuntu-24.04-test.sh
./lib/bashunit/bashunit tests/20-Deploy/ubuntu-26.04-test.sh
```

A targeted run leaves its container and shared package volume for inspection. The full suite's
cleanup runs only after the local, build, and deployment groups have all
finished. `DEPLOY_KEEP=1` skips that final cleanup.

The platform data lives in `platforms.tsv`: one row per platform, with its
container image and expected `/etc/os-release` ID and version. A platform also
has a corresponding `*-test.sh` entry point that declares the shared tests from
`deploy-test-helpers.sh`. Add both to extend the matrix. Set
`DEPLOY_PLATFORMS_FILE` to use a different data file with the same platform
keys.

Bashunit reports each operation as a separate test, grouped by platform:
prepare the shared package volume, create and start the container, check that it
is running and shell-ready, and verify the operating system ID and version.
The build stage verifies the current source hashes for `bash-tools`,
`opensim-engine`, `opensim-rest-php`,
and `opensim-helpers`, then stages those packages beside the fresh
`opensim-cli` package under Bashunit's temporary run directory. The five `.deb`
files and `quick-install.sh` are streamed once into a named volume on the
container host, then that volume is mounted into each platform. This also shares
`Packages.gz`: `quick-install.sh` rebuilds it only when a package is newer. A
checksum test confirms the initial copy before the script runs with
`OPENSIM_KIT_DEBS` pointing to the shared package directory. The suite stops
after verifying that the five packages are installed; it does not run
`opensim setup` or exercise service commands.

Containers stay running while the rest of the matrix is tested, then each is
removed by the final full-suite cleanup test in `tests/zz-cleanup-test.sh`,
which also removes the shared package volume. They are labelled with the
platform and run ID in Podman Desktop. Titles stay
short (for example, `debian-12 created`). If local tests or the build failed,
the deployment gate skips container work. If a platform's creation or
startup fails, its dependent checks are skipped and the other platforms
continue.

Podman is preferred and Docker is the fallback. To select an engine explicitly,
set `DEPLOY_ENGINE=podman` or `DEPLOY_ENGINE=docker` in the caller's environment
or `tests/.env`. `CONTAINER_CONNECTION` and `MEMORY` are also read by the
existing `tests/bootstrap.sh`.

Set `DEPLOY_KEEP=1` in `tests/.env` to leave containers running after the
deployment matrix finishes. By default, the final cleanup tests remove them.
During the matrix, you can inspect, stop, or remove a container in Podman
Desktop; if you stop or remove one, later checks for that platform will report
the resulting state.

The default matrix covers Debian 12 and 13, plus Ubuntu 24.04 and 26.04. All
tests use the shared `tests/bootstrap.sh` environment initialization.

Source-clone mode remains out of scope.
