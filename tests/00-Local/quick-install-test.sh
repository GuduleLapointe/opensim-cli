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
	# write_apt_repositories normally installs the generated file as root.
	as_root() { "$@"; }
}

function set_up() {
	WORK=$(mktemp -d)
	APT_SOURCE_FILE=$WORK/magiiic.list
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

	assert_exec "CALL_LOG='$calls' PATH='$fake_bin:$PATH' APT_SOURCE='deb https://packages.example.test/debian bookworm main' APT_SOURCE_TESTS='deb https://test.example.test/debian bookworm main' bash '$QUICK_INSTALL' --remote root@example.test --cleanup --opensim"
	assert_contains 'root@example.test' "$(cat "$calls")"
	assert_contains '--cleanup --opensim' "$(cat "$calls")"
	assert_contains 'APT_SOURCE=deb' "$(cat "$calls")"
	assert_contains 'packages.example.test/debian' "$(cat "$calls")"
	assert_contains 'APT_SOURCE_TESTS=deb' "$(cat "$calls")"
	assert_contains 'test.example.test/debian' "$(cat "$calls")"
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
	local fake_bin=$WORK/tools calls=$WORK/podman-calls debs=$WORK/local-debs
	mkdir -p "$debs"
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null CONTAINER_CONNECTION=ursull APT_SOURCE_DIR='$debs' bash '$QUICK_INSTALL' --podman --connection=ursull --image=docker.io/library/ubuntu:24.04 --opensim --yes"
	assert_contains '<--name> <opensim>' "$(cat "$calls")"
	assert_contains '<--connection> <ursull> <create> <--name> <opensim> <--image> <docker.io/library/ubuntu:24.04>' "$(cat "$calls")"
	assert_contains '<cp> ' "$(cat "$calls")"
	assert_contains '<cp> <'"$debs"'> <test-opensim:/tmp/opensim-kit-debs>' "$(cat "$calls")"
	assert_contains '<exec> <test-opensim> <-->' "$(cat "$calls")"
	assert_contains '<APT_SOURCE_DIR=/tmp/opensim-kit-debs>' "$(cat "$calls")"
	assert_contains '<bash> </tmp/quick-install.sh> <--opensim> <--yes>' "$(cat "$calls")"
}

function test_podman_config_names_container_and_is_copied_for_setup() {
	local fake_bin=$WORK/tools calls=$WORK/podman-config-calls config=$WORK/setup.json
	create_container_tools_stub "$fake_bin"
cat >"$config" <<'JSON'
{"type":"standalone","name":"Ile de Re"}
JSON
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --config '$config' --connection=local --opensim"
	assert_contains '<--name> <ile-de-re>' "$(cat "$calls")"
	assert_contains '<cp> <'"$config"'> <test-opensim:/tmp/opensim-setup.json>' "$(cat "$calls")"
	assert_contains '<OPENSIM_SETUP_CONFIG_FILE=/tmp/opensim-setup.json>' "$(cat "$calls")"
}

function test_podman_config_rejects_missing_setup_identity_before_create() {
	local fake_bin=$WORK/tools calls=$WORK/podman-bad-config-calls config=$WORK/setup.json status=0 output
	create_container_tools_stub "$fake_bin"
	printf '{"type":"grid"}\n' >"$config"
	output=$(CALL_LOG="$calls" CONTAINER_TOOLS_CLI="$fake_bin/container-tools" OPENSIM_RC=/dev/null bash "$QUICK_INSTALL" --podman --config "$config" 2>&1) || status=$?
	assert_not_equals 0 "$status"
	assert_contains 'invalid setup config' "$output"
	assert_not_contains '<create>' "$(cat "$calls" 2>/dev/null || true)"
}

function test_podman_connection_local_forces_local_engine() {
	local fake_bin=$WORK/tools calls=$WORK/podman-local-calls
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null CONTAINER_CONNECTION=ursull bash '$QUICK_INSTALL' --podman --connection=local --yes"
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
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC='$rc' CONTAINER_CONNECTION=ursull OPENSIM_CONTAINER_IMAGE=docker.io/library/debian:13-slim bash '$QUICK_INSTALL' --podman --yes"
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
	cat <<'SOURCES' >"$APT_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com stable main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com unstable main
deb [trusted=yes] https://apt.magiiic.com tests main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com main stable
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable
deb [trusted=yes] https://apt.magiiic.com charm-tests dev
deb https://archive.ubuntu.com/ubuntu resolute main
SOURCES

	OPENSIM_KIT_APT_DIST=charm
	OPENSIM_KIT_APT_COMPONENT=stable
	APT_REPOSITORIES=("deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable")
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"

	assert_contains 'deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable' "$(cat "$APT_SOURCE_FILE")"
	assert_contains 'deb [trusted=yes] https://apt.magiiic.com charm-tests dev' "$(cat "$APT_SOURCE_FILE")"
	assert_contains 'deb https://archive.ubuntu.com/ubuntu resolute main' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com stable ' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com unstable ' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com tests ' "$(cat "$APT_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com main ' "$(cat "$APT_SOURCE_FILE")"
}

function test_existing_components_are_merged_without_duplicates() {
	quick_install_load_library || return
	cat <<'SOURCES' >"$APT_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable
SOURCES
	APT_REPOSITORIES=('deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable')
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"

	assert_equals 1 "$(grep -Fc 'https://apt.magiiic.com charm stable unstable' "$APT_SOURCE_FILE")"
}

function test_default_apt_repository_is_charm_stable() {
	quick_install_load_library || return
	assert_equals 1 "${#APT_REPOSITORIES[@]}"
	assert_equals 'deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable' "${APT_REPOSITORIES[0]}"
}

function test_apt_source_parser_accepts_multiword_options() {
	quick_install_load_library || return
	local source='deb [arch=amd64 signed-by=/usr/share/keyrings/example.gpg] https://packages.example.test/debian bookworm main'
	assert_equals 3 "$(apt_source_uri_index "$source")"
	APT_REPOSITORIES=("$source")
	write_apt_repositories "$APT_SOURCE_FILE" "$TMP.sources"
	assert_equals "$source" "$(cat "$APT_SOURCE_FILE")"
}

function test_apt_source_settings_build_primary_and_test_entries() {
	local fixture=$WORK/project-sources output
	mkdir -p "$fixture/tests"
	cp "$QUICK_INSTALL" "$fixture/quick-install.sh"
	cat >"$fixture/.env" <<'ENV'
APT_SOURCE="deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable"
ENV
	cat >"$fixture/tests/.env" <<'ENV'
APT_SOURCE_TESTS="deb [trusted=yes] https://apt.magiiic.com charm-tests dev"
ENV
	output=$(QUICK_INSTALL_LIBRARY_ONLY=yes OPENSIM_RC=/dev/null bash -c 'script=$1; set -- --podman; source "$script"; printf "%s\n" "${APT_REPOSITORIES[@]}"' bash "$fixture/quick-install.sh")
	assert_contains 'https://apt.magiiic.com charm stable unstable' "$output"
	assert_contains 'https://apt.magiiic.com charm-tests dev' "$output"
}

function test_podman_install_loads_project_and_test_apt_repositories() {
	local fixture=$WORK/project calls=$WORK/podman-repository-calls
	mkdir -p "$fixture/tests" "$fixture/tools"
	cp "$QUICK_INSTALL" "$fixture/quick-install.sh"
	cat >"$fixture/.env" <<'ENV'
APT_SOURCE="deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable"
ENV
	cat >"$fixture/tests/.env" <<'ENV'
APT_SOURCE_TESTS="deb [trusted=yes] https://apt.magiiic.com charm-tests dev"
ENV
	create_container_tools_stub "$fixture/tools"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fixture/tools/container-tools' OPENSIM_RC=/dev/null bash '$fixture/quick-install.sh' --podman --yes"
	local output
	output=$(cat "$calls")
	assert_contains 'apt.magiiic.com charm stable unstable' "$output"
	assert_contains 'apt.magiiic.com charm-tests dev' "$output"
}

function test_podman_caller_apt_repositories_override_test_environment() {
	local fixture=$WORK/project-override calls=$WORK/podman-repository-override-calls
	mkdir -p "$fixture/tests" "$fixture/tools"
	cp "$QUICK_INSTALL" "$fixture/quick-install.sh"
	cat >"$fixture/tests/.env" <<'ENV'
APT_SOURCE="deb https://packages.example.test/debian bookworm main"
ENV
	create_container_tools_stub "$fixture/tools"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fixture/tools/container-tools' OPENSIM_RC=/dev/null APT_SOURCE='deb https://caller.example.test/debian trixie main' bash '$fixture/quick-install.sh' --podman --yes"
	assert_contains 'caller.example.test/debian trixie main' "$(cat "$calls")"
	assert_not_contains 'packages.example.test' "$(cat "$calls")"
}

function test_custom_apt_source_does_not_fetch_magiiic_signing_key() {
	quick_install_load_library || return
	local key_downloaded=no
	APT_REPOSITORIES=('deb https://packages.example.test/debian bookworm main')
	APT_SOURCE_FILE=$WORK/custom.list
	PACKAGE_SOURCES_READY=no
	apt-get() { return 0; }
	dpkg-query() { printf 'installed\n'; }
	apt_update() { return 0; }
	as_root() { return 0; }
	uname() { printf 'Linux\n'; }
	curl() { key_downloaded=yes; return 1; }
	configure_package_sources
	unset -f apt-get dpkg-query apt_update as_root uname curl
	assert_equals no "$key_downloaded"
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

function test_dotnet_runtime_detection_accepts_apt_candidate_with_pipefail() {
	quick_install_load_library || return
	local runtime= status=0 line
	apt-cache() {
		case "$1" in
		pkgnames) printf 'dotnet-runtime-10.0\n' ;;
		policy)
			printf 'dotnet-runtime-10.0:\n  Installed: (none)\n  Candidate: 10.0.13-0ubuntu1~26.04.1\n  Version table:\n'
			for ((line = 0; line < 4096; line++)); do printf '    available version %s\n' "$line"; done
			;;
		esac
	}
	runtime=$(dotnet_runtime_package) || status=$?
	unset -f apt-cache
	assert_equals 0 "$status"
	assert_equals 'dotnet-runtime-10.0' "$runtime"
}

