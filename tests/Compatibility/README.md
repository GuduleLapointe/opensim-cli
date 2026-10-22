# Compatibility tests

Run the tests through Bashunit, using its normal recursive test discovery:

```sh
composer test
./lib/bashunit tests/Compatibility
```

The first command runs the full suite; the second runs only the compatibility
tests. `composer test` invokes the Bashunit submodule under `lib/bashunit`. The
project `.bashunitrc` uses ordered wrappers for local tests, package build, then
compatibility; wrappers source the existing test files. Bashunit loads
`tests/bootstrap.sh` for both commands, keeping environment setup in one place.

The platform matrix lives in `platforms.tsv`: one row per platform, with its
container image and expected `/etc/os-release` ID and version. Add a row there
to repeat this same suite on another platform. Set `COMPAT_PLATFORMS_FILE` to
use a different matrix file.

Bashunit reports each operation as a separate test, grouped by platform:
create, start, check that the container is running, check shell readiness,
verify the operating system ID and version, then remove it before moving to the
next platform. Titles stay short (for example, `debian-12 created`). If local
tests or the build failed, the compatibility gate skips container work. If a
platform's creation or startup fails, its dependent checks are skipped and the
other platforms continue.

Podman is preferred and Docker is the fallback. To select an engine explicitly,
set `COMPAT_ENGINE=podman` or `COMPAT_ENGINE=docker` in the caller's environment
or `tests/.env`. `CONTAINER_CONNECTION` and `MEMORY` are also read by the
existing `tests/bootstrap.sh`.

Containers are removed after their platform finishes, so they appear only
briefly in Podman Desktop. Set `COMPAT_KEEP=1` in `tests/.env` to leave them
running for inspection. This keeps completed containers while the next
platform is tested.

The default matrix covers Debian 12 and 13, plus Ubuntu 24.04 and 26.04. All
tests use the shared `tests/bootstrap.sh` environment initialization.

This step does not install OpenSim packages or run Bashunit inside the
containers. The planned package step should copy the locally built `.deb` files
into each container and invoke `quick-install.sh` with `OPENSIM_KIT_DEBS`
pointing at that copied directory. Source-clone mode remains out of scope.
