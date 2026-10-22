# Compatibility tests

Run the tests through Bashunit, using its normal recursive test discovery:

```sh
./tests/lib/bashunit
./tests/lib/bashunit tests/Compatibility
```

The first command runs the full suite; the second runs only the compatibility
tests. Bashunit loads `tests/bootstrap.sh` for both commands, so the shared
environment setup stays in that one file.

Each platform has its own Bashunit test. The test prints the platform, image,
container name, engine command, and the result and duration of each step:
create, start, check running state, execute a shell readiness check, and verify
the distribution ID and version. If an earlier step fails, later steps for
that platform are reported as skipped; the other platform still runs. Each
container is removed after the compatibility test file finishes.

Podman is preferred and Docker is the fallback. To select an engine explicitly,
set `COMPAT_ENGINE=podman` or `COMPAT_ENGINE=docker` in the caller's environment
or `tests/.env`. `CONTAINER_CONNECTION` and `MEMORY` are also read by the
existing `tests/bootstrap.sh`. `COMPAT_READY_TIMEOUT` sets the shell-readiness
deadline in seconds (default: 10).

This step does not install OpenSim packages or run Bashunit inside the
containers. The planned package step should copy the locally built `.deb` files
into each container and invoke `quick-install.sh` with `OPENSIM_KIT_DEBS`
pointing at that copied directory. Source-clone mode remains out of scope.
