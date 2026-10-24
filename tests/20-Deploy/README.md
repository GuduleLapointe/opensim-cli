# Deploy tests

Run the full test suite through the project test command:

```sh
composer test
```

It runs local application tests, then the package build, then deployment.
Bashunit marks dependent build and deployment tests as skipped when an
earlier check fails. Each platform file removes its ephemeral container in
Bashunit's `tear_down_after_script` hook, including when the file is selected
directly. The full suite uses Bashunit's default
alphabetical discovery. The numbered directories put local application tests
and the package build before deployment; platform files remain grouped by
operating system.

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

A targeted run retains persistent containers for inspection. Platform
containers are persistent by default and are reused on later runs. Their names
include the launching machine, user, and OS version. Set `DEPLOY_EPHEMERAL=1`
to use randomly named containers; the platform file's teardown removes them,
and persistent containers are left untouched.

The platform data lives in `platforms.tsv`: one row per platform, with its
container image and expected `/etc/os-release` ID and version. A platform also
has a corresponding `*-test.sh` entry point that declares the shared tests from
`deploy-test-helpers.sh`. Add both to extend the matrix. Set
`DEPLOY_PLATFORMS_FILE` to use a different data file with the same platform
keys.

Bashunit reports each operation as a separate test. Each enabled platform
creates and starts its own container, checks readiness and OS identity, then
runs `quick-install.sh` steps separately by default: dependencies, MariaDB and
SQL account setup, .NET, and OpenSim packages. Set
`DEPLOY_INSTALL_MODE=single` to run `quick-install.sh` once without a step
option, as in a normal installation, followed by separate checks for MariaDB,
.NET, and OpenSim. Use `DEPLOY_INSTALL_MODE=separate` to run each installation
step as its own command; this is the default and is useful for isolating a slow
or failing step. A fresh-container timing comparison can use
`DEPLOY_EPHEMERAL=1 DEPLOY_INSTALL_MODE=single`. Five `.deb` files are built
and staged locally after verifying the current source hashes for `bash-tools`,
`opensim-engine`, `opensim-rest-php`, and `opensim-helpers`. A setup smoke test
then runs the installed `opensim setup` interface with a stubbed engine
response, checking both that installer-saved SQL credentials in
`/root/.opensimrc` reach the engine and that credentials can be entered
interactively when the file is absent. It does not create a grid or simulator.
It does not exercise service commands. `BASHUNIT_PROFILE=true` reports slowest
tests at the end, including duration for a failed long-running step.

Platform containers stay running and persist across test runs, so subsequent
runs avoid package installation when their contents are current. They can be
inspected in Podman Desktop and removed manually when no longer needed with the
configured container engine. Platform containers are labelled by OS, machine,
and user. Titles stay short (for example, `debian-12 created`). If local tests
or the build fails, dependent deployment tests are skipped. A platform creation
or installation failure skips only that platform; other platforms continue.

Podman is preferred and Docker is the fallback. To select an engine explicitly,
set `DEPLOY_ENGINE=podman` or `DEPLOY_ENGINE=docker` in the caller's environment
or `tests/.env`. `CONTAINER_CONNECTION` and optional `MEMORY` are also read by the
existing `tests/bootstrap.sh`. No memory cap is applied unless `MEMORY` is set
in the environment or `tests/.env`. `DEPLOY_QUICK_INSTALL_TIMEOUT` sets the
per-platform install timeout in seconds (default: 900).

The platform image is checked explicitly and pulled from its configured source
if absent on the selected engine. `tests/bootstrap.sh` gives environment values
from the command line precedence over `~/.opensimrc` and both project `.env`
files, so `CONTAINER_CONNECTION=hal` targets Hal even when another connection
is saved elsewhere.

Set `DEPLOY_EPHEMERAL=1` in `tests/.env` to use temporary containers removed by
the platform file's teardown, even when that file is run on its own.
By default, deployment containers persist and are reused, so a successful
installation is not repeated when the staged package manifest and selected APT
suite are unchanged. Each quick-install phase is logged under
`tmp/deploy-logs/<container-name>/<phase>.log` on the test machine and
`/tmp/<container-name>/<phase>.log` inside the container. The host path is
printed if a phase fails. Test titles distinguish the start command from the
running-state check and name the expected operating-system ID and version.
During the matrix, you can inspect, stop, or remove a container in Podman
Desktop; if you stop or remove one, later checks for that platform will report
the resulting state.

The enabled matrix is listed in `platforms.tsv` (currently Debian 12 and
Ubuntu 26.04); commented rows are not discovered or reported as tests. Add a
platform row and matching test file to extend it. All tests use the shared
`tests/bootstrap.sh` environment initialization.

If the local build test was not selected, the first deployment prerequisite
builds and stages the same five current packages locally before contacting the
container engine. Containers install OpenSim packages from the official APT
repository. `DEPLOY_APT_DIST` and `DEPLOY_APT_COMPONENT` select a package
source; they default to `charm-tests/dev`. Test packages can be published from the local build with
`DEPLOY_PUBLISH_TEST_PACKAGES=1` and a local repository clone configured as
`APT_REPO_DIR` in `tests/.env`. No local `.deb` files are copied into the OS
containers. The installer also enables `main/stable` for shared package
dependencies. The test distribution is unsigned and trusted explicitly;
signed distributions use the repository signing key.
`CONTAINER_CONNECTION` applies to platform containers and never
redirects the local build. The remote image and container availability checks
use Bashunit's one-retry annotation. A check that only passes on retry is
marked as flaky; package mutations and installation tests are not retried.

Source-clone mode remains out of scope.
