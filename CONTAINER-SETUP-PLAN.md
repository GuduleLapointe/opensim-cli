# Functional OpenSim container setup

Implementation checklist. Complete and validate one stage before starting the next. Commit each completed stage. This document tracks decisions and acceptance checks; README.md remains the concise user guide.

## Required behavior

- One reusable software image per supported release, base and architecture. Building the image does not select an instance's ports or create its data, passwords, database accounts or SSH host keys.
- `quick-install.sh --podman` asks all setup questions before creating the target container, including the grid/simulator identity and ports. Collecting answers and applying the setup are separate operations using the same configuration.
- OpenSim's engine owns setup rules, defaults, validation and port allocation. The installer and CLI present and transfer those settings; container-tools provides generic container operations.
- An instance keeps OpenSim's existing identity. The current engine convention is `<grid_nick>.<simulator_nick>`, supplied by `OpenSim\Provisioning\Slug::simulator()`, for example `speculoos.grand_place`. A grid uses its grid nick. Reuse the engine's naming helpers for future grid services; do not invent another normalization scheme.
- Production identities contain no host, platform, user or project prefix and no OCI container ID. Existing OpenSim identities are not renamed by this work.
- Simulator allocation keeps blocks of ten ports, for example `9140–9149`. Allocation and the ports actually used are distinct: publish the configured listeners, with their TCP/UDP protocol and access category.
- Effective setup configuration is the source of truth for every launch. Image defaults have no authority over configured ports.
- OpenSim services use the same port inside and outside the container. Alternate internal ports with translated advertised addresses are deferred to 3.1/3.2. Maintenance services such as SSH may use a separate mapping.
- Changing ports must preserve the deployed instance, its data and identity. Prefer live changes; where the backend fixes bindings at container creation, replace the OCI container from the same image and persistent mounts without reinstalling the software. The OCI ID may change in this fallback; the OpenSim identity and data do not.
- Pasta is an optional backend, not a prerequisite for this behavior.
- Persistent paths belong to the selected Podman host, including remote hosts.
- Containers include SSH and common maintenance tools: Bash, curl, wget, process/socket inspection, DNS diagnostics and ping.
- Validate `ResolveAddress = True` with portable address configuration, including `ExternalHostName = SYSTEMIP`, against the actual core's announced address. A container must remain movable between hosts without a baked-in host IP. The inspected core source resolves SYSTEMIP through its local-address helper; verify actual behavior before deciding whether that is suitable behind NAT.
- Support SQLite3 for small deployments, including a single-region container. MariaDB/MySQL remain supported and recommended for grids. The selected driver controls provisioning and required services; SQLite must not require a SQL server or administrator account.
- Provision a simulator container for an existing region directly, preserving its identity and data. Creating then deleting a placeholder region is not a supported migration workflow.
- Migrating existing live regions into containers is an acceptance case for the next usable beta, not a later enhancement after new-region provisioning.

## 1. Restore `opensim ports`

- [x] Port the kit command through the current CLI/engine architecture. Reference: `../opensim-kit/src/Console/Commands/PortsCommand.php`.
- [x] Use the existing engine port descriptions (`ports()` on controllers), including instance, type, port, protocol, role and access category.
- [x] Provide the table and instance selection supported by the old command.
- [x] Restore `--publish`, `--ufw` and `--private-address` behavior.
- [x] Deduplicate mappings while preserving distinct TCP and UDP entries.
- [x] Keep private/console ports restricted by default; omit disabled listeners.
- [x] Add help and completion using the existing CLI conventions.
- [x] Test Robust, simulators, multiple regions, TCP/UDP, disabled consoles, instance selection and explicit failure for an unknown instance.

Acceptance: reproduce the old command's useful output, including region UDP ports and loopback-bound console mappings. The CLI does not parse a second set of port rules independently of the engine.

Validated: the ten Bashunit port-command tests (29 assertions) pass on macOS and Ubuntu 26.04 using the source CLI and installed engine dependencies. The complete local application suite passes: 58 passed, two expected macOS setup skips, no failures.

## 2. Collect the complete setup before provisioning

- [x] Separate the engine's questionnaire/validation from setup side effects.
- [x] Provide `opensim setup --prepare FILE` with private atomic saving, cancellation that preserves the destination, and refusal of engines that do not acknowledge preparation support.
- [x] Let quick-install collect the full grid, standalone or simulator setup, rather than just its type and name.
- [x] Reuse the same saved answer format in quick-install and `opensim setup`.
- [ ] Include the database driver and the choice to create a region or adopt an existing one in the collected answers.
- [x] Resolve how the engine-owned questionnaire is available before target installation without requiring the full OpenSim stack on the client host. Preserve quick-install's ability to be downloaded and run independently.
- [x] Detect occupied ports on the selected Podman host during planning; repeat the collision check immediately before launch.
- [ ] `opensim setup --podman [--connection <host>]` should also allow the setup of a new or existing podman instance
- [x] Preserve ten-port simulator allocation and the ability to override defaults.
- [x] Compute the final OpenSim identity before creating paths or the container.
- [x] Protect saved secrets and transfer them as file contents or standard input.
- [ ] Test interactive answers and supplied configuration, cancellation, validation failures, config round trips and application without repeated prompts.

Acceptance: cancellation leaves no target container or partial deployment. The confirmed configuration determines both the container identity and setup.

Controller bootstrap decision: a downloaded quick-install installs opensim-cli (and its engine dependency) plus container-tools on the client. The controller suppresses package recommendations so that collecting answers does not install a local SQL server; ordinary target installation keeps its existing dependency behavior. A source checkout reuses its Composer dependencies. No temporary questionnaire container or runtime bundle is used. The engine provides the final identity and random-name defaults. Supplied configuration prefills the same questionnaire; it is confirmed and validated before target creation.

Credential handoff: quick-install copies the selected SQL credentials into a private rc file in the new container, so the package installation and later setup use the same account/password. Applying a prepared file fills an unspecified SQL administrator from the target's normal rc environment while preserving explicitly supplied credentials. SQL account creation quotes arbitrary passwords using a defined session SQL mode; a live MariaDB check authenticated both temporary accounts with apostrophes and backslashes and removed them afterwards. All 72 local CLI tests passed on Ubuntu 24.04 before the additional SQL quoting regression, which also passed separately.

Prepared application: `opensim setup --apply FILE` applies the confirmed configuration without repeating questions and refuses changes to its frozen values. Quick-install recognizes this format and uses `--apply` when `--setup` is requested; ordinary answer files keep interactive `--config` behavior. The installer accepts `--region-config FILE` and passes the original region through preparation before creating the target. Remote SSH installation copies both input files to a private temporary directory, rewrites their paths and removes the directory on completion or failure. Native installer tests pass (27 tests, 87 assertions); all 83 local CLI tests pass on Ubuntu 24.04, including a real private-input handoff to the opensim service account. SQL driver selection remains open.

Port choices: the questionnaire now offers optional grid private/console ports and simulator HTTP/console/region ports. Empty inputs retain the existing planners' defaults and ten-port blocks; changing the simulator HTTP base moves its automatic console and region ports with it. Confirmed values survive preparation. A standalone keeps its Login URI and HTTP listener together. The core engine and CLI regressions pass on Ubuntu 24.04: 1,034 engine tests and 83 CLI tests, with six engine prerequisite skips. The engine now accepts an occupied-port snapshot from the selected Podman host instead of reading the controller's local sockets/configuration; quick-install refreshes it immediately before creating the container and refuses conflicts. Vonda's live snapshot included 8002, 8003 and 8004; the full setup-preparation path selected 8012 before container creation. The temporary probe was removed. Validation: 31 quick-install tests (104 assertions), 92 engine tests (415 assertions) on Ursull Ubuntu 24.04, 80 quick-setup engine tests (391 assertions) on Ursull Ubuntu 24.04, and 36 container-tools unit tests (183 assertions).

## 2a. Provision containers for existing regions

Prioritize this reported bug before extending the new-region-only workflow.

CLI handoff: `opensim setup --region-config FILE` selects the existing-region path, and `--prepare FILE` saves the confirmed configuration for later `--apply`. The CLI checks the engine's advertised setup capabilities through the side-effect-free planning API before sending adoption requests. Older engines that would ignore the new input are rejected before provisioning. Private configuration/region files are preflighted as the caller, transferred to a temporary directory owned by the service account only when elevation is needed, and cleaned after the command. A real Ubuntu service-account check verified both the prepared-file pipe and the private-file handoff. `OPENSIM_API` now survives elevation, and unexported administrator settings in the rc file are honored. Validation: all 162 targeted engine tests and all 80 local CLI tests pass on Ubuntu 24.04; the real service-account handoff also passes. Quick-install now forwards this input through preparation before target creation.

Engine adoption is implemented and validated: the setup accepts original Region.ini contents, checks registered identity by name and, when needed, UUID, and stages an inactive simulator using the existing region configuration. It keeps UUID, estate ID, dimensions, unknown options and legacy names. No database, avatar, estate or replacement region is created and no instance is started. A repeat preserves identical files and refuses to overwrite edited target region data. All 161 targeted engine tests pass on Ubuntu 24.04. Database/file restoration, release/schema checks and live cutover remain pending; staging alone is not a completed migration.

Planning foundation validated: applying a fixed-region move now preserves its existing UUID, name, roles and estate, and rejects a missing or invalid UUID. The fixed-region path accepts only location/port changes. The 137 targeted engine tests pass on Ubuntu 24.04. This fixes a destructive planning primitive; it does not yet expose the complete adoption/import workflow or move a live source.

- [x] Reproduce rejection of an existing region when provisioning its new simulator/container, using a fixture with its existing grid registration.
- [x] Reuse the engine's existing move/adoption mechanisms where applicable; inspect RegionPlanner's existing-region context and uniqueness checks.
- [x] Distinguish adopting the same region from creating a conflicting new region. Keep genuine duplicate-name/UUID protection.
- [x] Allow the simulator/container to be provisioned without creating any new region, SQL schema, estate or registry entry for a placeholder.
- [x] Import or reference the existing Region.ini, preserving region UUID, name, location, estate associations and settings except explicitly changed values.
- [ ] Transfer/reconnect the existing database and required files using the appropriate backup/restore workflow for their current driver. Do not assume migration into a container also means conversion from MySQL to SQLite.
- [ ] Validate compatible core/schema versions before applying migrations.
- [ ] Define the source shutdown, final data copy and destination startup sequence so the same region is not running from two simulators at once.
- [ ] Test cancellation, failed import and rerun without damaging the source or leaving placeholder records. Retain a recoverable source backup for cutover.

Acceptance: move a region with its original UUID and data into its intended simulator container, then verify its grid registration, estate and contents. No temporary region or disposable database is created to bypass setup.

An already migrated region can serve as a read-only manual investigation reference. Reproduce its relevant structure with anonymous fixtures rather than committing personal server, grid or container names as test configuration.

## 2b. Complete SQLite3 provisioning

- [ ] Reuse OSPDO's existing `driver=sqlite` and database-file/DSN support.
- [ ] Audit DatabaseService, SqlRunner and model queries for MySQL-only extension checks, SQL, account creation and connection assumptions. OSPDO's connection support does not by itself validate the complete setup/runtime workflow.
- [ ] Carry the selected driver consistently through setup answers, saved configuration, engine access and the OpenSim core storage provider.
- [ ] Verify the selected OpenSim release/profile supports the chosen SQLite stores and initialize their schemas using existing supported mechanisms.
- [ ] Provide the PHP SQLite extension and core-native SQLite dependencies in the reusable image, without requiring a MariaDB service for SQLite instances.
- [ ] Skip SQL administrator/application account questions and server startup for SQLite; create database files with the instance's correct permissions.
- [ ] Place database files, including any journal/WAL companion files, on the instance's persistent data mount and define a consistent backup procedure.
- [ ] Test fresh SQLite setup, normal reads/writes, region start/stop/restart, persistence and adoption of a compatible existing SQLite region.
- [ ] Retain MySQL/MariaDB regression coverage and their grid recommendation; do not silently convert an existing database or change its driver.

Acceptance: a single-region deployment completes setup and runs with SQLite3 without installing/starting a SQL server or asking for SQL admin credentials.

## 3. Prove launch-time and changing-port behavior

This stage uses small TCP/UDP listeners, avoiding repeated full installations.

Podman distinguishes `run` (create and start) from `start` (start an existing container). Standard `--publish` mappings are supplied to `create`/`run`; `start` does not offer a replacement port list. Merely stopping and starting an existing bridge container does not implement the required update behavior.

- [x] Record the selected hosts' Podman versions and available network backends.
- [x] Verify explicit TCP and UDP mappings derived from the setup configuration, without depending on image `EXPOSE` metadata or automatic host-port selection.
- [x] Resolve port changes when Pasta is unavailable: Podman has no supported API to mutate fixed bridge bindings, so use a controlled container replacement with the same image and persistent mounts; implement this after stage 5 establishes those mounts.
- [x] Test Pasta live forwarding separately for TCP and UDP where available.
- [x] Keep public, private and console bindings distinct with every backend; automatic forwarding must not expose SQL or private consoles unintentionally.
- [x] Verify Pasta reacts to listeners started and stopped by the controller or inside the container; its automatic forwarding tracks bound sockets without changing the container.
- [x] Exercise an occupied host port and a listener outside the initial published set on bridge and Pasta backends.
- [x] Verify Pasta removes and restores forwarding when a listener stops and restarts.
- [x] Verify published access from another machine, not only container loopback.
- [x] Keep generic mappings and Pasta forwarding in container-tools and generate OpenSim's access policy in the engine.
- [ ] Restart an individual OpenSim simulator after changing its configured ports; validate bridge replacement once stage 5 mounts are implemented.

Acceptance: change the configured ports, relaunch if required, and verify the same OpenSim identity and data plus the new TCP/UDP bindings. Pasta keeps the OCI ID for live changes; a bridge fallback may replace the OCI container while preserving mounted data. Live changes must leave unrelated simulators running.

Development hosts checked: Vonda runs rootless Podman 5.7.0 with Netavark (client 5.6.0); Ursull runs rootless Podman 4.9.3 with Netavark (client 5.6.0). The live TCP/UDP integration checks in this stage currently run against Vonda.

Prepared setups now carry engine-generated `port_bindings`: public TCP/UDP listeners bind on all host interfaces; private and console TCP listeners bind to host loopback; disabled consoles are omitted; duplicate standalone/listener ports are collapsed. Quick-install passes those records as explicit container-tools mappings and disables image `EXPOSE` defaults. Validation: 81 QuickSetup tests (394 assertions), 31 quick-install tests (108 assertions), one real-engine-to-installer setup test (16 assertions), and Vonda explicit TCP/UDP listener delivery (one integration test, 11 assertions).

Live forwarding validation on Vonda: Pasta passed TCP listeners started by the controller and inside the container, UDP listener delivery, and TCP listener start/stop/restart outside the initial published set while keeping the OCI ID. A bridge test passed a listener started after container startup on a mapping chosen at creation, and another confirmed a second container cannot claim an occupied host port. The external-access test connected from the Mac to a TCP listener published by Vonda. The UDP probe waits for the socket to bind before sending; test port selection checks both TCP and UDP sockets. These checks verify dynamic listener forwarding on Pasta, not fixed `--publish` changes on a bridge container.

OpenSim uses explicit engine-generated bindings for every network backend; it never enables Pasta auto-publish, which would forward every eligible listening port, including private services. The quick-install engine integration test now asserts that the auto-publish flag is absent while checking public, private, console and UDP mappings.

Same-container port update investigation: Podman's `create` accepts `--publish`, but `update` only changes resource limits and health checks, and `network connect` only accepts network, alias, IP and MAC settings. The REST update endpoint has no port-binding fields either. Therefore fixed bridge `--publish` mappings cannot be changed for the same container through the supported Podman CLI/API. Decision: Pasta can update listeners live; other backends use a controlled OCI container replacement with the same image and persistent mounts, preserving OpenSim identity and data without reinstalling packages. This fallback is implemented and validated in stages 5–6, once the mounts exist. References: [Podman create](https://docs.podman.io/en/v5.7.0/markdown/podman-create.1.html), [Podman update](https://docs.podman.io/en/v4.9.3/markdown/podman-update.1.html), [Podman network connect](https://docs.podman.io/en/latest/markdown/podman-network-connect.1.html), [Podman API update endpoint](https://docs.podman.io/en/latest/_static/api.html?version=v5.0).

Bridge replacement changes the OCI ID and briefly stops that container, but it preserves the logical instance, mounts and unrelated containers. Do not implement the replacement before the persistent mounts and rollback behavior are ready.

## 4. Build the reusable server image and service lifecycle

- [ ] Reuse quick-install's installation phases through a readable setup script called by the Containerfile; avoid a second package-install implementation.
- [ ] Keep Debian/Ubuntu base selection parameterized where the recipe is shared.
- [ ] Include OpenSim tools/core dependencies and maintenance tools, including SSH.
- [ ] Generate instance secrets and SSH host keys at initialization, not build.
- [ ] Diagnose current `opensim start|stop|restart` inside a container. The engine's current StartService/StopService use its runtime/console machinery; absence of systemd alone does not explain an instance restart failure.
- [x] Validate systemd as PID 1 through the container-tools API path. The reusable Debian/Ubuntu server recipe enables SSH with host keys generated on instance boot. Ubuntu 26.04 lifecycle tests pass on Ursull without privileged mode; application-specific service integration remains below.
- [ ] Manage MariaDB when bundled, SSH and enabled OpenSim instances; remove the installer's placeholder sleep loop once real service lifecycle is validated.
- [ ] Start database services according to the instance's selected driver; a reusable image must also run a SQLite-only instance without MariaDB startup.
- [ ] Ensure signals stop OpenSim and databases cleanly within an appropriate stop timeout. An instance restart must not restart the whole container.
- [ ] Clean build-only files and package indexes from the image.
- [ ] Test start, individual restart, stop, container restart and startup with no configured instances yet. Do not reboot a shared test host for this check.
- [ ] **CRITICAL BUG**: Test actual answer from detected ports, ensure it comes from the intended container (e.g. with host:port/get_grid_info for grid)

Acceptance: the server starts its configured services autonomously and stops them cleanly, with readable status and logs and no personal data in its image.

## 5. Persist instance data on the Podman host

- [ ] Use `/etc/opensim/containers/<opensim-identity>` as the host configuration source mounted at `/etc/opensim` inside the container.
- [ ] Use `/var/lib/opensim/containers/<opensim-identity>` as its host data source mounted at `/var/lib/opensim` inside the container.
- [ ] Define persistent locations for logs, SSH host keys and `/var/lib/mysql` when the deployment includes its own MariaDB server.
- [ ] Persist SQLite database files and companion files under the instance's data tree when SQLite is selected.
- [ ] Make host roots configurable and provision the required permissions on the Podman host. Rootless access and UID/GID mapping must work with these paths.
- [ ] Initialize empty mounted folders from the image's installed defaults; mounting an empty directory hides the corresponding image contents.
- [ ] Keep initialization idempotent and preserve existing instance settings.
- [ ] Test stop/start and replacement from the same image, preserving settings, database records, assets, inventories and SSH identity.
- [ ] Test two instances from one image with isolated configuration and data.

Acceptance: container replacement preserves all application state without another software installation. Normal restart also preserves it. Container replacement for image updates remains distinct from the port-change contract.

## 6. Apply setup and validate a running grid and region

- [ ] Create the target instance using the confirmed configuration and mounts.
- [ ] Apply setup without repeating the questionnaire or changing chosen ports.
- [ ] Validate SQL administrator/application credentials for MySQL/MariaDB, SQLite file access for SQLite, and normal rc loading for both workflows.
- [ ] Test `ResolveAddress = True` with `SYSTEMIP` and with a public hostname on the actual core. Verify the advertised address outside the container, including after moving the deployment to another host. Select the working portable configuration and preserve explicit public-address choices.
- [ ] Start a grid and a simulator with a region, and check actual readiness.
- [ ] Compare `opensim ports` with configured listeners and effective bindings.
- [ ] Verify advertised public hostnames and matching external/internal OpenSim ports, including region UDP access.
- [ ] Test the region address announced to Robust/viewers from an external client. A passing file-content assertion alone does not validate reachability.
- [ ] Check start/stop/status/restart and preservation after a container restart.
- [ ] Add a region and validate the port-change workflow from stage 3.
- [ ] Confirm a real Firestorm login and entry into the region.
- [ ] Repeat the runtime checks with an adopted existing region, preserving its UUID, estate, terrain, objects and applicable database/file contents.

Acceptance: a working grid and region, usable externally, with retained state and independently manageable instances.

## 7. Finish installer integration and image distribution

- [ ] Make `quick-install.sh --podman` drive the validated sequence: questionnaire, preflight, persistent paths, container initialization, setup, effective-port application, launch and readiness.
- [ ] Honor standard Podman connection/environment settings and inline overrides.
- [ ] Report instance name, selected host, actual ports, logs and maintenance commands clearly; failures name the operation and block dependent steps.
- [ ] Integrate image build/versioning with the existing development tools.
- [ ] Define OCI registry publication and release tags alongside package releases; image publication is a release operation, not a test side effect.
- [ ] Reuse the released image for a second instance without rebuilding it.
- [ ] Add concise user instructions after the implemented workflow is verified.
- [ ] Finish with targeted and complete regression runs as justified by changes, using persistent test containers first and a fresh ephemeral pass last.

Acceptance: one installation command leads through setup to an externally reachable grid/region, using a reusable image and persistent instance data.

## Validation discipline

- [ ] Implement and validate only the current stage; check items after evidence.
- [ ] Use existing Bashunit/Pest conventions, concise separate test results and explicit prerequisite skips. Do not modify the vendored test runner.
- [ ] Source the normal rc/environment bootstrap and preserve inline overrides.
- [ ] Use configurable test remotes; no personal connection names in source.
- [ ] Prefer the development remotes for container work. Production-host checks are a distinct final validation, not the default development target.
- [ ] Commit every validated stage, including its documentation; never push.

## References

- Existing naming: `../opensim-engine/src/Provisioning/Slug.php`.
- Existing port allocation: `../opensim-engine/src/Network/Ports.php`.
- Existing port descriptions: engine controllers' `ports()` methods.
- Existing database abstraction: `../opensim-engine/src/Data/OSPDO.php`.
- Existing provisioning: engine DatabaseService, SqlRunner and RegionPlanner.
- Address resolution behavior: `../opensim-kit/upstream/opensim/OpenSim/Framework/RegionInfo.cs`.
- Existing CLI output: `../opensim-kit/src/Console/Commands/PortsCommand.php`.
- [Podman create](https://docs.podman.io/en/latest/markdown/podman-create.1.html).
- [Podman run](https://docs.podman.io/en/latest/markdown/podman-run.1.html).
- [Podman start](https://docs.podman.io/en/latest/markdown/podman-start.1.html).
