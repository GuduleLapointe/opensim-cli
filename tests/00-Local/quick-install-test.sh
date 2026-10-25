#!/usr/bin/env bash

QUICK_INSTALL=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/quick-install.sh
QUICK_INSTALL_LIBRARY_LOADED=no

function quick_install_load_library() {
	if [[ "$QUICK_INSTALL_LIBRARY_LOADED" == yes ]]; then return 0; fi
	if ! bash -n "$QUICK_INSTALL"; then
		bashunit::skip 'quick-install syntax check failed'
		return 1
	fi
	QUICK_INSTALL_LIBRARY_ONLY=yes OPENSIM_RC=/dev/null source "$QUICK_INSTALL"
	QUICK_INSTALL_LIBRARY_LOADED=yes
	# write_magiiic_repositories normally installs the generated file as root.
	as_root() { "$@"; }
}

function set_up() {
	WORK=$(mktemp -d)
	MAGIIIC_SOURCE_FILE=$WORK/magiiic.list
	TMP=$WORK/quick-install
}

function tear_down() {
	rm -rf "$WORK"
}

function test_00_quick_install_has_valid_bash_syntax() {
	assert_exec "bash -n '$QUICK_INSTALL'"
}

function test_remote_install_copies_script_and_forwards_install_options() {
	quick_install_load_library || return
	local fake_bin=$WORK/bin calls=$WORK/remote-calls
	mkdir -p "$fake_bin"
	cat >"$fake_bin/scp" <<'SCP'
#!/usr/bin/env bash
printf 'scp' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
SCP
	cat >"$fake_bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf 'ssh' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
SSH
	chmod +x "$fake_bin/scp" "$fake_bin/ssh"

	assert_exec "CALL_LOG='$calls' PATH='$fake_bin:$PATH' bash '$QUICK_INSTALL' --remote root@example.test --cleanup --opensim"
	assert_contains 'root@example.test' "$(cat "$calls")"
	assert_contains '--cleanup --opensim' "$(cat "$calls")"
	assert_contains 'scp' "$(cat "$calls")"
	assert_equals 2 "$(grep -c '^ssh ' "$calls")"
}

function create_container_tools_stub() {
	local fake_bin=$1
	mkdir -p "$fake_bin"
	cat >"$fake_bin/container-tools" <<'CLI'
#!/usr/bin/env bash
printf 'connection=%s args=' "${CONTAINER_CONNECTION-<unset>}" >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
action=$1
[[ "$action" == --connection ]] && { shift 2; action=$1; }
if [[ "$action" == create ]]; then
	printf 'Container created\nName: test-opensim\n'
fi
CLI
	chmod +x "$fake_bin/container-tools"
}

function test_podman_install_uses_connection_image_and_forwards_install_options() {
	local fake_bin=$WORK/tools calls=$WORK/podman-calls
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null CONTAINER_CONNECTION=ursull bash '$QUICK_INSTALL' --podman --connection=ursull --image=docker.io/library/ubuntu:24.04 --opensim --yes"
	assert_contains '<--connection> <ursull> <create> <--image> <docker.io/library/ubuntu:24.04>' "$(cat "$calls")"
	assert_contains '<cp> ' "$(cat "$calls")"
	assert_contains '<exec> <test-opensim> <-->' "$(cat "$calls")"
	assert_contains '<bash> </tmp/quick-install.sh> <--opensim> <--yes>' "$(cat "$calls")"
}

function test_podman_connection_local_forces_local_engine() {
	local fake_bin=$WORK/tools calls=$WORK/podman-local-calls
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null CONTAINER_CONNECTION=ursull bash '$QUICK_INSTALL' --podman --connection=local"
	assert_contains 'connection=<unset>' "$(cat "$calls")"
	assert_contains '<--image> <docker.io/library/ubuntu:26.04>' "$(cat "$calls")"
	assert_not_contains '<--connection>' "$(cat "$calls")"
}

function test_podman_environment_overrides_opensimrc() {
	local fake_bin=$WORK/tools calls=$WORK/podman-env-calls rc=$WORK/opensimrc
	create_container_tools_stub "$fake_bin"
	cat >"$rc" <<'RC'
CONTAINER_CONNECTION=other
OPENSIM_CONTAINER_IMAGE=docker.io/library/ubuntu:24.04
RC
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC='$rc' CONTAINER_CONNECTION=ursull OPENSIM_CONTAINER_IMAGE=docker.io/library/debian:13-slim bash '$QUICK_INSTALL' --podman"
	assert_contains 'connection=ursull' "$(cat "$calls")"
	assert_contains '<--image> <docker.io/library/debian:13-slim>' "$(cat "$calls")"
}

function test_podman_setup_requires_interactive_container_terminal() {
	local fake_bin=$WORK/tools calls=$WORK/podman-setup-calls status=0 output
	create_container_tools_stub "$fake_bin"
	output=$(CALL_LOG="$calls" CONTAINER_TOOLS_CLI="$fake_bin/container-tools" OPENSIM_RC=/dev/null bash "$QUICK_INSTALL" --podman --setup 2>&1) || status=$?
	assert_not_equals 0 "$status"
	assert_contains 'run opensim setup in the container after installation' "$output"
	assert_equals '' "$(cat "$calls" 2>/dev/null || true)"
}

function test_default_source_replaces_old_magiiic_distributions_and_preserves_other_sources() {
	quick_install_load_library || return
	cat <<'SOURCES' >"$MAGIIIC_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com stable main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com unstable main
deb [trusted=yes] https://apt.magiiic.com tests main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable
deb [trusted=yes] https://apt.magiiic.com charm-tests dev
deb https://archive.ubuntu.com/ubuntu resolute main
SOURCES

	OPENSIM_KIT_APT_DIST=charm
	OPENSIM_KIT_APT_COMPONENT=stable
	MAGIIIC_REPOSITORIES=("deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable")
	write_magiiic_repositories "$MAGIIIC_SOURCE_FILE" "$TMP.sources"

	assert_contains 'deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_contains 'deb [trusted=yes] https://apt.magiiic.com charm-tests dev' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_contains 'deb https://archive.ubuntu.com/ubuntu resolute main' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com stable ' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com unstable ' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com tests ' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com main ' "$(cat "$MAGIIIC_SOURCE_FILE")"
}

function test_existing_components_are_merged_without_duplicates() {
	quick_install_load_library || return
	cat <<'SOURCES' >"$MAGIIIC_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable
SOURCES
	MAGIIIC_REPOSITORIES=('deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable')
	write_magiiic_repositories "$MAGIIIC_SOURCE_FILE" "$TMP.sources"

	assert_equals 1 "$(grep -Fc 'https://apt.magiiic.com charm stable unstable' "$MAGIIIC_SOURCE_FILE")"
}

function test_dotnet_phase_requests_libgdiplus_directly_from_apt_when_missing() {
	quick_install_load_library || return
	recover_dpkg_configuration() { return 0; }
	apt_update() { return 0; }
	uname() { printf 'Linux\n'; }
	ldconfig() { return 1; }
	dotnet_runtime_package() { printf 'dotnet-runtime-10.0\n'; }
	local runtime_checks=0 installed_packages
	dotnet_runtime_installed() {
		((runtime_checks += 1))
		((runtime_checks > 1))
	}
	install_packages() { installed_packages="$*"; }
	phase_dotnet
	assert_contains 'dotnet-runtime-10.0' "$installed_packages"
	assert_contains 'libgdiplus' "$installed_packages"
}

