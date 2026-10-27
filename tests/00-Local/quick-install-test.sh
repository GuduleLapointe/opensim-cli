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

function test_clone_install_requests_core_when_cli_and_engine_are_installed() {
	quick_install_load_library || return
	local calls=$WORK/install-calls
	clone=$WORK/project
	APT_SOURCE_DIR=
	OPENSIM_KIT_APT_DIST=charm
	uname() { printf 'Linux\n'; }
	dpkg-query() {
		case "$*" in
		*opensim-cli* | *opensim-engine*) printf 'installed\n' ;;
		*) return 1 ;;
		esac
	}
	configure_package_sources() { return 0; }
	install_packages() { printf '%s\n' "$*" >>"$calls"; }
	end_installation() { return 0; }
	phase_opensim
	assert_equals 'opensim opensim-0.9.3.0 opensim-0.9.3.0-gloebit opensim-0.9.3.0-opensimsearch' "$(cat "$calls")"
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

function test_confirmed_setup_ends_with_a_grid_summary() {
	quick_install_load_library || return
	local config="$WORK/Confirmed Setup.json"
	cat >"$config" <<'JSON'
{"version":1,"identity":"test_grid","answers":{"type":"grid","name":"Test Grid","avatar":"Ada Resident"},"setup":{"grid":{"name":"Test Grid","hostname":"grid.example.test","public_port":8123},"simulators":[]}}
JSON
	clone=$WORK/project
	SETUP_CONFIG_FILE=$config
	unset OPENSIM_SETUP_CONFIG_FILE
	RUN_SETUP=yes
	uname() { printf 'Darwin\n'; }
	assert_exec '(end_installation)' --stdout-contains 'Installation completed' --stdout-contains 'Grid:       Test Grid' --stdout-contains 'Login URI:  http://grid.example.test:8123' --stdout-contains 'Avatar:     Ada Resident'
}
