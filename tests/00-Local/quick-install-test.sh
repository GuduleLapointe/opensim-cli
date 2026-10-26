#!/usr/bin/env bash

QUICK_INSTALL_SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/quick-install.sh
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
	QUICK_INSTALL=$WORK/project/quick-install.sh
	mkdir -p "$WORK/project/bin" "$WORK/project/vendor"
	cp "$QUICK_INSTALL_SOURCE" "$QUICK_INSTALL"
	printf '{}\n' >"$WORK/project/composer.json"
	: >"$WORK/project/vendor/autoload.php"
	cat >"$WORK/project/bin/opensim" <<'SETUP'
#!/usr/bin/env bash
printf 'setup' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
shift
while (($#)); do
    case "$1" in
        --prepare) destination=$2; shift 2 ;;
        --config) config=$2; shift 2 ;;
        --region-config) region=$2; shift 2 ;;
        --apply) exit 0 ;;
        *) exit 2 ;;
    esac
done
[[ -n "${destination:-}" ]] || exit 0
if [[ -n "${config:-}" ]]; then
    [[ -z "${CAPTURED_SETUP:-}" ]] || cp "$config" "$CAPTURED_SETUP"
    if jq -e 'keys == ["hostname","occupied_ports"] or keys == ["occupied_ports"]' "$config" >/dev/null; then
        printf '{"identity":"test_grid","answers":{"type":"grid","name":"Test Grid"},"setup":{"grid":{"public_port":8012,"private_port":8013,"console_port":8014},"simulators":[{"http_port":9010,"console":"rest","console_port":9014,"regions":[{"port":9011}]}]},"port_bindings":[{"port":8012,"protocol":"tcp","use":"public","host_ip":null},{"port":8013,"protocol":"tcp","use":"private","host_ip":"127.0.0.1"},{"port":8014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"},{"port":9010,"protocol":"tcp","use":"public","host_ip":null},{"port":9011,"protocol":"udp","use":"public","host_ip":null},{"port":9014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"}]}\n' >"$destination"
    else
        jq -e '.identity' "$config" >/dev/null || { echo 'invalid setup config' >&2; exit 1; }
        jq '.port_bindings //= [{"port":8012,"protocol":"tcp","use":"public","host_ip":null}]' "$config" >"$destination"
    fi
else
    printf '{"identity":"test_grid","answers":{"type":"grid","name":"Test Grid"},"setup":{"grid":{"public_port":8012,"private_port":8013,"console_port":8014},"simulators":[{"http_port":9010,"console":"rest","console_port":9014,"regions":[{"port":9011}]}]},"port_bindings":[{"port":8012,"protocol":"tcp","use":"public","host_ip":null},{"port":8013,"protocol":"tcp","use":"private","host_ip":"127.0.0.1"},{"port":8014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"},{"port":9010,"protocol":"tcp","use":"public","host_ip":null},{"port":9011,"protocol":"udp","use":"public","host_ip":null},{"port":9014,"protocol":"tcp","use":"console","host_ip":"127.0.0.1"}]}\n' >"$destination"
fi
chmod 600 "$destination"
SETUP
	chmod +x "$WORK/project/bin/opensim"
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
if [[ "$*" == *mktemp* ]]; then printf '/tmp/quick-install.test-session\n'; fi
SSH
	chmod +x "$fake_bin/scp" "$fake_bin/ssh"

	assert_exec "CALL_LOG='$calls' PATH='$fake_bin:$PATH' APT_SOURCE='deb https://packages.example.test/debian bookworm main' APT_SOURCE_TESTS='deb https://test.example.test/debian bookworm main' bash '$QUICK_INSTALL' --remote root@example.test --cleanup --opensim"
	local config="$WORK/Setup Answers.json" region="$WORK/Existing Region.ini"
	printf '{"type":"simulator"}\n' >"$config"
	printf '[Existing Region]\n' >"$region"
	: >"$calls"
	assert_exec "CALL_LOG='$calls' PATH='$fake_bin:$PATH' APT_SOURCE='deb https://packages.example.test/debian bookworm main' APT_SOURCE_TESTS='deb https://test.example.test/debian bookworm main' bash '$QUICK_INSTALL' --remote root@example.test --config '$config' --region-config='$region' --cleanup --opensim"
	assert_contains '<'"$config"'> <root@example.test:/tmp/quick-install.test-session/setup.json>' "$(cat "$calls")"
	assert_contains '<'"$region"'> <root@example.test:/tmp/quick-install.test-session/Region.ini>' "$(cat "$calls")"
	assert_contains '--config /tmp/quick-install.test-session/setup.json' "$(cat "$calls")"
	assert_contains '--region-config /tmp/quick-install.test-session/Region.ini' "$(cat "$calls")"
	assert_contains 'root@example.test' "$(cat "$calls")"
	assert_contains '--cleanup --opensim' "$(cat "$calls")"
	assert_contains 'APT_SOURCE=deb' "$(cat "$calls")"
	assert_contains 'packages.example.test/debian' "$(cat "$calls")"
	assert_contains 'APT_SOURCE_TESTS=deb' "$(cat "$calls")"
	assert_contains 'test.example.test/debian' "$(cat "$calls")"
	assert_contains 'scp' "$(cat "$calls")"
	assert_equals 3 "$(grep -c '^ssh ' "$calls")"
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
if [[ "$action" == cp && -n "${CAPTURED_RC:-}" && "${3:-}" == *:/root/.opensimrc ]]; then
	cp "$2" "$CAPTURED_RC"
fi
if [[ "$action" == cp && -n "${CAPTURED_CONTAINER_SETUP:-}" && "${3:-}" == *:/tmp/opensim-setup.json ]]; then
	cp "$2" "$CAPTURED_CONTAINER_SETUP"
fi
if [[ "$action" == info ]]; then
    printf '{"Name":"podman.example.test"}\n'
fi
if [[ "$action" == host-ports ]]; then
    printf '[8002,9001]\n'
fi
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
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null CONTAINER_CONNECTION=podman-host APT_SOURCE_DIR='$debs' bash '$QUICK_INSTALL' --podman --connection=podman-host --image=docker.io/library/ubuntu:24.04 --opensim --yes"
	assert_contains '<--name> <test_grid>' "$(cat "$calls")"
	assert_contains '<--connection> <podman-host> <create> <--name> <test_grid> <--image> <localhost/opensim-server:docker.io-library-ubuntu-24.04-' "$(cat "$calls")"
	assert_contains '<--no-publish-defaults>' "$(grep '<create>' "$calls")"
	assert_contains '<--publish> <8012:8012/tcp>' "$(grep '<create>' "$calls")"
	assert_contains '<--publish> <127.0.0.1:8013:8013/tcp>' "$(grep '<create>' "$calls")"
	assert_contains '<--publish> <9011:9011/udp>' "$(grep '<create>' "$calls")"
	assert_not_contains '<-->' "$(grep '<create>' "$calls")"
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
{"identity":"ile_de_re.ile_de_re","answers":{"type":"standalone","name":"Ile de Re"},"setup":{}}
JSON
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --config '$config' --connection=local --opensim"
	assert_contains '<--name> <ile_de_re.ile_de_re>' "$(cat "$calls")"
	assert_contains '> <test-opensim:/tmp/opensim-setup.json>' "$(cat "$calls")"
	assert_contains '<OPENSIM_SETUP_CONFIG_FILE=/tmp/opensim-setup.json>' "$(cat "$calls")"
}

function test_podman_setup_advertises_the_selected_host_for_region_udp() {
	local fake_bin=$WORK/tools calls=$WORK/podman-external-host-calls config=$WORK/setup.json
	create_container_tools_stub "$fake_bin"
	cat >"$config" <<'JSON'
{"identity":"example","answers":{"type":"grid"},"setup":{"grid":{"hostname":"grid.example.test"},"simulators":[{"external_host":"SYSTEMIP","regions":[{"port":9021}]}]}}
JSON
	assert_exec "CALL_LOG='$calls' CAPTURED_CONTAINER_SETUP='$WORK/applied-setup.json' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --config '$config' --connection=podman-host --opensim"
	assert_equals 'podman.example.test' "$(jq -r '.setup.simulators[0].external_host' "$WORK/applied-setup.json")"
}

function test_podman_transfers_database_credentials_privately() {
	local fake_bin=$WORK/tools calls=$WORK/rc-calls config=$WORK/setup.json
	create_container_tools_stub "$fake_bin"
	cat >"$config" <<'JSON'
{"identity":"example","answers":{"type":"grid","name":"Example","database_user":"example_db","database_password":"quote' dollar$","admin_user":"example_admin","admin_password":"admin-fixture"},"setup":{}}
JSON
	assert_exec "CALL_LOG='$calls' CAPTURED_RC='$WORK/target-rc' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --config '$config' --yes"
	assert_file_exists "$WORK/target-rc"
	assert_equals "quote' dollar\$" "$(source "$WORK/target-rc"; printf '%s' "$OPENSIM_DB_PASS")"
	assert_equals example_admin "$(source "$WORK/target-rc"; printf '%s' "$OPENSIM_DB_ADMIN_USER")"
	assert_not_contains admin-fixture "$(cat "$calls")"
}

function test_podman_config_rejects_missing_setup_identity_before_create() {
	local fake_bin=$WORK/tools calls=$WORK/podman-bad-config-calls config=$WORK/setup.json
	create_container_tools_stub "$fake_bin"
	printf '{"type":"grid"}\n' >"$config"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --config '$config' 2>&1" \
		--exit 1 \
		--stdout-contains 'invalid setup config'
	assert_not_contains '<create>' "$(cat "$calls" 2>/dev/null || true)"
}

function test_podman_connection_local_forces_local_engine() {
	local fake_bin=$WORK/tools calls=$WORK/podman-local-calls
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null CONTAINER_CONNECTION=podman-host bash '$QUICK_INSTALL' --podman --connection=local --yes"
	assert_contains 'connection=<unset>' "$(cat "$calls")"
	assert_contains '<--image> <localhost/opensim-server:docker.io-library-ubuntu-26.04-' "$(cat "$calls")"
	assert_not_contains '<--connection>' "$(cat "$calls")"
}

function test_podman_environment_overrides_opensimrc() {
	local fake_bin=$WORK/tools calls=$WORK/podman-env-calls rc=$WORK/opensimrc
	create_container_tools_stub "$fake_bin"
	cat >"$rc" <<'RC'
CONTAINER_CONNECTION=other
OPENSIM_CONTAINER_IMAGE=docker.io/library/ubuntu:24.04
RC
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC='$rc' CONTAINER_CONNECTION=podman-host OPENSIM_CONTAINER_IMAGE=docker.io/library/debian:13-slim bash '$QUICK_INSTALL' --podman --yes"
	assert_contains 'connection=podman-host' "$(cat "$calls")"
	assert_contains '<--image> <localhost/opensim-server:docker.io-library-debian-13-slim-' "$(cat "$calls")"
}

function test_podman_setup_applies_prepared_settings() {
	local fake_bin=$WORK/tools calls=$WORK/podman-setup-calls
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --setup"
	assert_contains '<RUN_SETUP=yes>' "$(cat "$calls")"
	assert_contains '<bash> </tmp/quick-install.sh> <--setup>' "$(cat "$calls")"
}

function test_podman_prepares_an_existing_region() {
	local fake_bin=$WORK/tools calls=$WORK/region-calls region="$WORK/Existing Region.ini"
	printf '[Existing Region]\n' >"$region"
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --region-config '$region'"
	assert_contains '<--region-config> <'"$region"'>' "$(grep '^setup ' "$calls")"
	assert_not_contains '<--region-config>' "$(grep '<exec>' "$calls")"
}

function test_confirmed_setup_is_applied_after_installation() {
	quick_install_load_library || return
	local calls=$WORK/apply-calls config="$WORK/Confirmed Setup.json"
	printf '{"version":1,"identity":"test_grid","answers":{},"setup":{}}\n' >"$config"
	clone=$WORK/project
	SETUP_CONFIG_FILE=$config
	unset OPENSIM_SETUP_CONFIG_FILE
	RUN_SETUP=yes
	uname() { printf 'Darwin\n'; }
	export CALL_LOG=$calls
	assert_exec '(end_installation)' --stdout-contains '--apply'
	assert_contains '<setup> <--apply> <'"$config"'>' "$(cat "$calls")"
}

function test_unconfirmed_answers_keep_interactive_setup() {
	quick_install_load_library || return
	local calls=$WORK/prefill-calls config="$WORK/Setup Answers.json"
	printf '{"type":"grid"}\n' >"$config"
	clone=$WORK/project
	SETUP_CONFIG_FILE=$config
	unset OPENSIM_SETUP_CONFIG_FILE
	RUN_SETUP=yes
	uname() { printf 'Darwin\n'; }
	export CALL_LOG=$calls
	assert_exec '(end_installation)' --stdout-contains '--config'
	assert_contains '<setup> <--config> <'"$config"'>' "$(cat "$calls")"
}

function test_podman_prepares_before_container_creation() {
	local fake_bin=$WORK/tools calls=$WORK/prepare-calls
	create_container_tools_stub "$fake_bin"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --yes"
	assert_contains '<--prepare>' "$(grep -E '^setup |<create>' "$calls" | head -n 1)"
	assert_contains '<create>' "$(cat "$calls")"
}

function test_podman_cancel_creates_no_container() {
	local fake_bin=$WORK/tools calls=$WORK/cancel-calls
	create_container_tools_stub "$fake_bin"
	printf '#!/usr/bin/env bash\necho Cancelled >&2\nexit 1\n' >"$WORK/project/bin/opensim"
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman 2>&1" --exit 1 --stdout-contains Cancelled
	assert_not_contains '<create>' "$(cat "$calls")"
}

function test_podman_bootstrap_installs_only_management_packages() {
	quick_install_load_library || return
	clone=
	local calls=$WORK/bootstrap-calls
	configure_package_sources() { printf 'sources\n' >>"$calls"; }
	install_packages() { printf '%s\n' "$*" >>"$calls"; }
	bootstrap_podman_manager
	assert_equals $'sources\n--no-install-recommends opensim-cli container-tools' "$(cat "$calls")"
	assert_equals /usr/share/opensim-cli/bin/opensim "$SETUP_CLI_SELECTED"
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
	local APT_SOURCE= APT_SOURCE_TESTS=
	QUICK_INSTALL_LIBRARY_LOADED=no
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
	cp -R "$WORK/project/." "$fixture/"
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
	cp -R "$WORK/project/." "$fixture/"
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
	cp -R "$WORK/project/." "$fixture/"
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

function test_database_passwords_are_quoted_as_sql_literals() {
	quick_install_load_library || return
	local sql=$WORK/accounts.sql
	configure_package_sources() { return 0; }
	database_server_installed() { return 0; }
	start_sql_server() { return 0; }
	save_database_credentials() { return 0; }
	uname() { printf 'Linux\n'; }
	as_root() { "$@"; }
	mariadb() {
		if [[ "${1:-}" == -Nse ]]; then printf '0\n'; else cat >"$sql"; fi
	}
	OPENSIM_DB_ADMIN_USER=example_admin OPENSIM_DB_ADMIN_PASS="ad'min"
	OPENSIM_DB_USER=example_user OPENSIM_DB_PASS="p'ass\\word"
	phase_database
	assert_contains "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES';" "$(cat "$sql")"
	assert_contains "IDENTIFIED BY 'ad''min';" "$(cat "$sql")"
	assert_contains "IDENTIFIED BY 'p''ass\\word';" "$(cat "$sql")"
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
	local line
	apt-cache() {
		case "$1" in
		pkgnames) printf 'dotnet-runtime-10.0\n' ;;
		policy)
			printf 'dotnet-runtime-10.0:\n  Installed: (none)\n  Candidate: 10.0.13-0ubuntu1~26.04.1\n  Version table:\n'
			for ((line = 0; line < 4096; line++)); do printf '    available version %s\n' "$line"; done
			;;
		esac
	}
	assert_exec 'dotnet_runtime_package' --stdout 'dotnet-runtime-10.0'
	unset -f apt-cache
}

function test_dotnet_installer_uses_supported_runtime_channel() {
	quick_install_load_library || return
	PGM=quick-install
	local calls=$WORK/dotnet-installer-calls runtime_checks=0
	recover_dpkg_configuration() { return 0; }
	apt_update() { return 0; }
	uname() { printf 'Linux\n'; }
	dotnet_runtime_package() { return 1; }
	ldconfig() { printf 'libicuuc.so.76\nlibgdiplus.so.0\n'; }
	dpkg-query() { printf 'installed\n'; }
	dotnet_runtime_installed() {
		((runtime_checks += 1))
		((runtime_checks >= 3))
	}
	curl() {
		local output
		while (($#)); do
			if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi
		done
		printf '#!/usr/bin/env bash\nexit 0\n' >"$output"
	}
	as_root() {
		printf '%q ' "$@" >>"$calls"
		printf '\n' >>"$calls"
		[[ "$1" != bash ]] || "$@"
	}
	phase_dotnet
	local output
	output=$(cat "$calls")
	unset -f recover_dpkg_configuration apt_update uname dotnet_runtime_package ldconfig dpkg-query dotnet_runtime_installed curl as_root
	assert_contains '--channel 10.0' "$output"
	assert_contains '--azure-feed https://builds.dotnet.microsoft.com/dotnet' "$output"
}


function test_podman_setup_proposes_selected_server_hostname() {
    local fake_bin=$WORK/tools calls=$WORK/host-calls
    create_container_tools_stub "$fake_bin"
    assert_exec "CALL_LOG='$calls' CAPTURED_SETUP='$WORK/prefill.json' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --connection=podman-host --yes"
    assert_file_exists "$WORK/prefill.json"
    assert_equals podman.example.test "$(jq -r '.hostname' "$WORK/prefill.json")"
    assert_equals '[8002,9001]' "$(jq -c '.occupied_ports' "$WORK/prefill.json")"
    assert_contains '<host-ports>' "$(cat "$calls")"
    assert_contains '<--connection> <podman-host> <info>' "$(cat "$calls")"
}

function test_podman_install_rechecks_prepared_ports_before_creating_the_container() {
	local fake_bin=$WORK/tools calls=$WORK/port-recheck-calls config=$WORK/setup.json
	create_container_tools_stub "$fake_bin"
	cat >"$config" <<'JSON'
{"identity":"test_grid","answers":{"type":"grid","name":"Test Grid"},"setup":{"grid":{"public_port":8002,"private_port":8003,"console_port":8004},"simulators":[]}}
JSON
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --config '$config' --connection=podman-host --yes 2>&1" --exit 1 --stdout-contains 'ports already occupied on the selected Podman host: 8002'
	assert_equals 2 "$(grep -c '<host-ports>' "$calls")"
	assert_not_contains '<create>' "$(cat "$calls")"
}

function test_podman_install_does_not_recheck_a_remote_grids_ports() {
	local fake_bin=$WORK/tools calls=$WORK/remote-grid-port-calls config=$WORK/setup.json
	create_container_tools_stub "$fake_bin"
	cat >"$config" <<'JSON'
{"identity":"example.region","answers":{"type":"simulator"},"setup":{"grid":{"public_port":8002,"private_port":8003,"console_port":8004},"simulators":[{"http_port":9100,"console_port":9104,"regions":[{"port":9101}]}]}}
JSON
	assert_exec "CALL_LOG='$calls' CONTAINER_TOOLS_CLI='$fake_bin/container-tools' OPENSIM_RC=/dev/null bash '$QUICK_INSTALL' --podman --config '$config' --connection=podman-host --yes"
	assert_contains '<create>' "$(cat "$calls")"
}

function test_systemd_image_starts_init_and_generates_keys_at_boot() {
    quick_install_load_library || return
    mkdir "$WORK/context"
    write_systemd_context "$WORK/context" docker.io/library/debian:12-slim
    assert_contains 'FROM docker.io/library/debian:12-slim' "$(cat "$WORK/context/Containerfile")"
    assert_contains 'COPY setup-system.sh /usr/local/sbin/setup-system' "$(cat "$WORK/context/Containerfile")"
    assert_contains '&& /usr/local/sbin/setup-system' "$(cat "$WORK/context/Containerfile")"
    assert_contains 'CMD ["/sbin/init"]' "$(cat "$WORK/context/Containerfile")"
    assert_contains 'STOPSIGNAL SIGRTMIN+3' "$(cat "$WORK/context/Containerfile")"
    assert_contains 'systemd-sysv' "$(cat "$WORK/context/setup-system.sh")"
    assert_contains 'openssh-server' "$(cat "$WORK/context/setup-system.sh")"
    assert_contains 'rm -rf /var/lib/apt/lists/*' "$(cat "$WORK/context/setup-system.sh")"
    assert_exec "bash -n '$WORK/context/setup-system.sh'"
    assert_contains 'ExecStart=/usr/bin/ssh-keygen -A' "$(cat "$WORK/context/ssh-host-keys.service")"
}

function test_systemd_image_fingerprint_includes_setup_script() {
	quick_install_load_library || return
	mkdir "$WORK/context"
	write_systemd_context "$WORK/context" docker.io/library/ubuntu:26.04
	local original changed
	original=$(systemd_image_checksum "$WORK/context")
	printf '\n# image setup revision\n' >>"$WORK/context/setup-system.sh"
	changed=$(systemd_image_checksum "$WORK/context")
	assert_not_equals "$original" "$changed"
}
