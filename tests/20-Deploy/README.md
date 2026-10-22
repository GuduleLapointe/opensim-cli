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

A targeted run leaves its container running for inspection. The full suite's
cleanup runs only after the local, build, and deployment groups have all
finished. `DEPLOY_KEEP=1` skips that final cleanup.

The platform data lives in `platforms.tsv`: one row per platform, with its
container image and expected `/etc/os-release` ID and version. A platform also
has a corresponding `*-test.sh` entry point that declares the shared tests from
`deploy-test-helpers.sh`. Add both to extend the matrix. Set
`DEPLOY_PLATFORMS_FILE` to use a different data file with the same platform
keys.

Bashunit reports each operation as a separate test, grouped by platform:
create, start, check that the container is running, check shell readiness, and
verify the operating system ID and version. Containers stay running while the
rest of the matrix is tested, then each is removed by the final full-suite
cleanup test in `tests/zz-cleanup-test.sh`.
They are labelled with the platform and run ID in Podman Desktop. Titles stay
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

This step does not install OpenSim packages or run Bashunit inside the
containers. The planned package step should copy the locally built `.deb` files
into each container and invoke `quick-install.sh` with `OPENSIM_KIT_DEBS`
pointing at that copied directory. Source-clone mode remains out of scope.
