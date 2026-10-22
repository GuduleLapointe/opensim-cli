# Compatibility tests

Run the tests through Bashunit, using its normal recursive test discovery:

```sh
composer test
./lib/bashunit/bashunit tests/Compatibility
```

The first command runs the full suite in local, build, then compatibility
order; the second runs only the compatibility tests. `composer test` invokes
the Bashunit executable from its submodule under `lib/bashunit`. A direct run
without paths discovers all files below `tests/`. Bashunit loads
`tests/bootstrap.sh` for both commands, keeping environment setup in one place.

The platform matrix lives in `platforms.tsv`: one row per platform, with its
container image and expected `/etc/os-release` ID and version. Add a row there
to repeat this same suite on another platform. Set `COMPAT_PLATFORMS_FILE` to
use a different matrix file.

Bashunit reports each operation as a separate test, grouped by platform:
create, start, check that the container is running, check shell readiness, and
verify the operating system ID and version. Containers stay running while the
rest of the matrix is tested, then each is removed in a final cleanup test.
They are labelled with the platform and run ID in Podman Desktop. Titles stay
short (for example, `debian-12 created`). If local tests or the build failed,
the compatibility gate skips container work. If a platform's creation or
startup fails, its dependent checks are skipped and the other platforms
continue.

Podman is preferred and Docker is the fallback. To select an engine explicitly,
set `COMPAT_ENGINE=podman` or `COMPAT_ENGINE=docker` in the caller's environment
or `tests/.env`. `CONTAINER_CONNECTION` and `MEMORY` are also read by the
existing `tests/bootstrap.sh`.

Set `COMPAT_KEEP=1` in `tests/.env` to leave containers running after the
compatibility matrix finishes. By default, the final cleanup tests remove them.
During the matrix, you can inspect, stop, or remove a container in Podman
Desktop; if you stop or remove one, later checks for that platform will report
the resulting state.

The default matrix covers Debian 12 and 13, plus Ubuntu 24.04 and 26.04. All
tests use the shared `tests/bootstrap.sh` environment initialization.

This step does not install OpenSim packages or run Bashunit inside the
containers. The planned package step should copy the locally built `.deb` files
into each container and invoke `quick-install.sh` with `OPENSIM_KIT_DEBS`
pointing at that copied directory. Source-clone mode remains out of scope.
