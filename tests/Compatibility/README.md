# Compatibility tests

Run the tests through Bashunit, using its normal recursive test discovery:

```sh
./tests/lib/bashunit
./tests/lib/bashunit tests/Compatibility
```

The first command runs the full suite; the second runs only the compatibility
tests. Bashunit loads `tests/bootstrap.sh` for both commands, so the shared
environment setup stays in that one file.

The platform matrix lives in `platforms.tsv`: one row per platform, with its
container image and expected `/etc/os-release` ID and version. Add a row there
to repeat this same suite on another platform. Set `COMPAT_PLATFORMS_FILE` to
use a different matrix file.

Bashunit reports each operation as a separate test, repeated for every row:
create, start, check that the container is running, check shell readiness, and
verify the operating system ID and version. Test titles identify the platform,
operation, and container. If creation or startup fails, dependent tests for
that platform are reported as skipped; other platforms continue. Containers
are removed after this test file finishes.

Podman is preferred and Docker is the fallback. To select an engine explicitly,
set `COMPAT_ENGINE=podman` or `COMPAT_ENGINE=docker` in the caller's environment
or `tests/.env`. `CONTAINER_CONNECTION` and `MEMORY` are also read by the
existing `tests/bootstrap.sh`.

The default matrix covers Debian 12 and 13, plus Ubuntu 24.04 and 26.04. All
tests use the shared `tests/bootstrap.sh` environment initialization.

This step does not install OpenSim packages or run Bashunit inside the
containers. The planned package step should copy the locally built `.deb` files
into each container and invoke `quick-install.sh` with `OPENSIM_KIT_DEBS`
pointing at that copied directory. Source-clone mode remains out of scope.
