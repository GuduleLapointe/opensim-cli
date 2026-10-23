# Deploy tests

Run the full test suite through the project test command:

```sh
composer test
```

It runs local application tests, then the package build, then deployment.
Bashunit marks dependent build and deployment tests as skipped when an
earlier check fails. Ephemeral containers are removed by the final cleanup phase, after
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

A targeted run leaves its container and shared package volume for inspection. Platform containers
are persistent by default and are reused on later runs. Their names include the launching machine,
user, and OS version. Set `DEPLOY_EPHEMERAL=1` to use randomly named containers; those are removed
by the final cleanup, and persistent containers are left untouched.

The platform data lives in `platforms.tsv`: one row per platform, with its
container image and expected `/etc/os-release` ID and version. A platform also
has a corresponding `*-test.sh` entry point that declares the shared tests from
`deploy-test-helpers.sh`. Add both to extend the matrix. Set
`DEPLOY_PLATFORMS_FILE` to use a different data file with the same platform
keys.

Bashunit reports each operation as a separate test. A shared `package builder`
group first creates or reuses a named package volume and a visible, persistent
Debian 12 builder container. It installs `dpkg-scanpackages` once, streams the
current package set only when its manifest changes, and creates `Packages.gz`
in the shared volume. Each enabled platform then creates and starts its own
container, checks readiness and OS identity, verifies the shared package set,
then runs `quick-install.sh` phases separately: dependencies, MariaDB and SQL
account setup, .NET, and OpenSim packages. The five `.deb` files are
staged by the local build after verifying the current source hashes for
`bash-tools`, `opensim-engine`, `opensim-rest-php`, and `opensim-helpers`. A
setup smoke test then runs the installed `opensim setup` interface with the
installer's `/root/.opensimrc` and a stubbed engine response, checking that the
saved SQL credentials reach the engine without creating a grid or simulator.
It does not exercise service commands. `BASHUNIT_PROFILE=true` reports slowest
tests at the end, including duration for a failed long-running step.

Platform containers stay running after the matrix by default. The package builder and its named volume stay
running and persist across test runs so subsequent runs avoid re-indexing and
package transfer. They can be inspected in Podman Desktop and removed manually
when no longer needed: `podman rm -f opensim-cli-test-build` followed by
`podman volume rm opensim-cli-test-packages` (use the configured engine and
Podman connection). Platform containers are labelled by OS, machine, and user. Titles
stay short (for example, `debian-12 created`). If local tests, the build, or
shared builder setup fails, dependent deployment tests are skipped. A platform
creation or installation failure skips only that platform; other platforms
continue.

Podman is preferred and Docker is the fallback. To select an engine explicitly,
set `DEPLOY_ENGINE=podman` or `DEPLOY_ENGINE=docker` in the caller's environment
or `tests/.env`. `CONTAINER_CONNECTION` and optional `MEMORY` are also read by the
existing `tests/bootstrap.sh`. No memory cap is applied unless `MEMORY` is set
in the environment or `tests/.env`. `DEPLOY_QUICK_INSTALL_TIMEOUT` sets the
per-platform install timeout in seconds (default: 900).

Set `DEPLOY_EPHEMERAL=1` in `tests/.env` to use temporary containers that the final cleanup removes.
By default, deployment containers persist and are reused, so a successful installation is not repeated
when the staged package manifest is unchanged. Each quick-install phase is logged
under `tmp/deploy-logs/<container-name>/<phase>.log` on the test machine and
`/tmp/<container-name>/<phase>.log` inside the container. The host path is printed
if a phase fails.
During the matrix, you can inspect, stop, or remove a container in Podman
Desktop; if you stop or remove one, later checks for that platform will report
the resulting state.

The enabled matrix is listed in `platforms.tsv` (currently Debian 12 and
Ubuntu 26.04); commented rows are not discovered or reported as tests. Add a
platform row and matching test file to extend it. All tests use the shared
`tests/bootstrap.sh` environment initialization.

Source-clone mode remains out of scope.
