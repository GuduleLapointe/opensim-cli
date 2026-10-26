# Functional OpenSim container setup

Implementation checklist. Complete and validate one stage before starting the next.
Commit each completed stage. This document tracks decisions and acceptance checks;
README.md remains the concise user guide.

## Required behavior

- One reusable software image per supported release, base and architecture.
  Building the image does not select an instance's ports or create its data,
  passwords, database accounts or SSH host keys.
- `quick-install.sh --podman` asks all setup questions before creating the target
  container, including the grid/simulator identity and ports. Collecting answers
  and applying the setup are separate operations using the same configuration.
- OpenSim's engine owns setup rules, defaults, validation and port allocation.
  The installer and CLI present and transfer those settings; container-tools
  provides generic container operations.
- An instance keeps OpenSim's existing identity. The current engine convention
  is `<grid_nick>.<simulator_nick>`, supplied by
  `OpenSim\Provisioning\Slug::simulator()`, for example
  `speculoos.grand_place`. A grid uses its grid nick. Reuse the engine's naming
  helpers for future grid services; do not invent another normalization scheme.
- Production identities contain no host, platform, user or project prefix and
  no OCI container ID. Existing OpenSim identities are not renamed by this work.
- Simulator allocation keeps blocks of ten ports, for example `9140–9149`.
  Allocation and the ports actually used are distinct: publish the configured
  listeners, with their TCP/UDP protocol and access category.
- Effective setup configuration is the source of truth for every launch.
  Image defaults have no authority over configured ports.
- OpenSim services use the same port inside and outside the container.
  Alternate internal ports with translated advertised addresses are deferred
  to 3.1/3.2. Maintenance services such as SSH may use a separate mapping.
- Changing ports must preserve the deployed instance, its data and identity.
  Prefer live changes; otherwise allow relaunching the same container with the
  new ports. Rebuilding or reinstalling the software is not part of this action.
- Pasta is an optional backend, not a prerequisite for this behavior.
- Persistent paths belong to the selected Podman host, including remote hosts.
- Containers include SSH and common maintenance tools: Bash, curl, wget,
  process/socket inspection, DNS diagnostics and ping.

## 1. Restore `opensim ports`

- [ ] Port the kit command through the current CLI/engine architecture.
  Reference: `../opensim-kit/src/Console/Commands/PortsCommand.php`.
- [ ] Use the existing engine port descriptions (`ports()` on controllers),
  including instance, type, port, protocol, role and access category.
- [ ] Provide the table and instance selection supported by the old command.
- [ ] Restore `--publish`, `--ufw` and `--private-address` behavior.
- [ ] Deduplicate mappings while preserving distinct TCP and UDP entries.
- [ ] Keep private/console ports restricted by default; omit disabled listeners.
- [ ] Add help and completion using the existing CLI conventions.
- [ ] Test Robust, simulators, multiple regions, TCP/UDP, disabled consoles,
  instance selection and explicit failure for an unknown instance.

Acceptance: reproduce the old command's useful output, including region UDP
ports and loopback-bound console mappings. The CLI does not parse a second set
of port rules independently of the engine.

## 2. Collect the complete setup before provisioning

- [ ] Separate the engine's questionnaire/validation from setup side effects.
- [ ] Let quick-install collect the full grid, standalone or simulator setup,
  rather than just its type and name.
- [ ] Reuse the same saved answer format in quick-install and `opensim setup`.
- [ ] Resolve how the engine-owned questionnaire is available before target
  installation without requiring the full OpenSim stack on the client host.
  Preserve quick-install's ability to be downloaded and run independently.
- [ ] Check the selected Podman host's occupied/reserved ports during planning;
  repeat collision checks immediately before launch to catch intervening changes.
- [ ] Preserve ten-port simulator allocation and the ability to override defaults.
- [ ] Compute the final OpenSim identity before creating paths or the container.
- [ ] Protect saved secrets and transfer them as file contents or standard input.
- [ ] Test interactive answers and supplied configuration, cancellation,
  validation failures, config round trips and application without repeated prompts.

Acceptance: cancellation leaves no target container or partial deployment.
The confirmed configuration determines both the container identity and setup.

## 3. Prove launch-time and changing-port behavior

This stage uses small TCP/UDP listeners, avoiding repeated full installations.

Podman distinguishes `run` (create and start) from `start` (start an existing
container). Standard `--publish` mappings are supplied to `create`/`run`;
`start` does not offer a replacement port list. Merely stopping and starting an
existing bridge container does not implement the required update behavior.

- [ ] Record the selected hosts' Podman versions and available network backends.
- [ ] Verify explicit TCP and UDP mappings derived from the setup configuration,
  without depending on image `EXPOSE` metadata or automatic host-port selection.
- [ ] Prove a supported mechanism to change ports for the same OCI container
  when Pasta is unavailable. Investigate existing networking/forwarding tools
  before writing a forwarding service.
- [ ] Test Pasta live forwarding separately for TCP and UDP where available.
- [ ] Keep public, private and console bindings distinct with every backend;
  automatic forwarding must not expose SQL or private consoles unintentionally.
- [ ] Verify changes initiated by the controller and by configuration inside
  the container, and define how these changes reach the network backend.
- [ ] Exercise an occupied host port, a new listener outside the old published
  set, removing a listener and restarting an individual simulator.
- [ ] Verify published access from another machine, not only container loopback.
- [ ] Put reusable mechanisms in container-tools and OpenSim policy in the engine.

Acceptance: change the configured ports, relaunch if required, and verify the
same container ID, instance identity and data, plus the new TCP/UDP bindings.
Live changes must leave unrelated simulators running.

If standard Podman mechanisms cannot meet same-container relaunch on a target
backend, record that limitation and resolve the design before continuing.
Replacing the OCI container while retaining its volumes is a different behavior
and requires an explicit decision; it is not silently substituted here.

## 4. Build the reusable server image and service lifecycle

- [ ] Reuse quick-install's installation phases through a readable setup script
  called by the Containerfile; avoid a second package-install implementation.
- [ ] Keep Debian/Ubuntu base selection parameterized where the recipe is shared.
- [ ] Include OpenSim tools/core dependencies and maintenance tools, including SSH.
- [ ] Generate instance secrets and SSH host keys at initialization, not build.
- [ ] Diagnose current `opensim start|stop|restart` inside a container. The
  engine's current StartService/StopService use its runtime/console machinery;
  absence of systemd alone does not explain an instance restart failure.
- [ ] Validate an existing service manager for PID 1 and automatic startup.
  Evaluate Podman's supported systemd mode for the complete server, including
  rootless operation and the container-tools API path, before adopting it.
- [ ] Manage MariaDB when bundled, SSH and enabled OpenSim instances; remove the
  installer's placeholder sleep loop once real service lifecycle is validated.
- [ ] Ensure signals stop OpenSim and databases cleanly within an appropriate
  stop timeout. An instance restart must not restart the whole container.
- [ ] Clean build-only files and package indexes from the image.
- [ ] Test start, individual restart, stop, container restart and startup with
  no configured instances yet. Do not reboot a shared test host for this check.

Acceptance: the server starts its configured services autonomously and stops
them cleanly, with readable status and logs and no personal data in its image.

## 5. Persist instance data on the Podman host

- [ ] Use `/etc/opensim/containers/<opensim-identity>` as the host configuration
  source mounted at `/etc/opensim` inside the container.
- [ ] Use `/var/lib/opensim/containers/<opensim-identity>` as its host data source
  mounted at `/var/lib/opensim` inside the container.
- [ ] Define persistent locations for logs, SSH host keys and `/var/lib/mysql`
  when the deployment includes its own MariaDB server.
- [ ] Make host roots configurable and provision the required permissions on the
  Podman host. Rootless access and UID/GID mapping must work with these paths.
- [ ] Initialize empty mounted folders from the image's installed defaults;
  mounting an empty directory hides the corresponding image contents.
- [ ] Keep initialization idempotent and preserve existing instance settings.
- [ ] Test stop/start and replacement from the same image, preserving settings,
  database records, assets, inventories and SSH identity.
- [ ] Test two instances from one image with isolated configuration and data.

Acceptance: container replacement preserves all application state without
another software installation. Normal restart also preserves it. Container
replacement for image updates remains distinct from the port-change contract.

## 6. Apply setup and validate a running grid and region

- [ ] Create the target instance using the confirmed configuration and mounts.
- [ ] Apply setup without repeating the questionnaire or changing chosen ports.
- [ ] Validate SQL administrator/application credentials and normal rc loading.
- [ ] Start a grid and a simulator with a region, and check actual readiness.
- [ ] Compare `opensim ports` with configured listeners and effective bindings.
- [ ] Verify advertised public hostnames and matching external/internal OpenSim
  ports, including region UDP access.
- [ ] Check start/stop/status/restart and preservation after a container restart.
- [ ] Add a region and validate the port-change workflow from stage 3.
- [ ] Confirm a real Firestorm login and entry into the region.

Acceptance: a working grid and region, usable externally, with retained state
and independently manageable instances.

## 7. Finish installer integration and image distribution

- [ ] Make `quick-install.sh --podman` drive the validated sequence:
  questionnaire, preflight, persistent paths, container initialization, setup,
  effective-port application, launch and readiness.
- [ ] Honor standard Podman connection/environment settings and inline overrides.
- [ ] Report instance name, selected host, actual ports, logs and maintenance
  commands clearly; failures name the operation and block dependent steps.
- [ ] Integrate image build/versioning with the existing development tools.
- [ ] Define OCI registry publication and release tags alongside package releases;
  image publication is a release operation, not a test side effect.
- [ ] Reuse the released image for a second instance without rebuilding it.
- [ ] Add concise user instructions after the implemented workflow is verified.
- [ ] Finish with targeted and complete regression runs as justified by changes,
  using persistent test containers first and a fresh ephemeral pass last.

Acceptance: one installation command leads through setup to an externally
reachable grid/region, using a reusable image and persistent instance data.

## Validation discipline

- [ ] Implement and validate only the current stage; check items after evidence.
- [ ] Use existing Bashunit/Pest conventions, concise separate test results and
  explicit prerequisite skips. Do not modify the vendored test runner.
- [ ] Source the normal rc/environment bootstrap and preserve inline overrides.
- [ ] Use configurable test remotes; no personal connection names in source.
- [ ] Prefer the development remotes for container work. Production-host checks
  are a distinct final validation, not the default development target.
- [ ] Commit every validated stage, including its documentation; never push.

## References

- Existing naming: `../opensim-engine/src/Provisioning/Slug.php`.
- Existing port allocation: `../opensim-engine/src/Network/Ports.php`.
- Existing port descriptions: engine controllers' `ports()` methods.
- Existing CLI output: `../opensim-kit/src/Console/Commands/PortsCommand.php`.
- [Podman create](https://docs.podman.io/en/latest/markdown/podman-create.1.html).
- [Podman run](https://docs.podman.io/en/latest/markdown/podman-run.1.html).
- [Podman start](https://docs.podman.io/en/latest/markdown/podman-start.1.html).
