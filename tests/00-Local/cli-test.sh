#!/usr/bin/env bash
# Integration tests for opensim-cli
#
# Run with: composer test
#
# These tests confirm the current state:
# - Locally: ./bin/opensim commands work

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

function set_up() {
	WORK="$(mktemp -d)"
	export HOME="$WORK"
	unset OPENSIM_CONF OPENSIM_RC
	export OPENSIM_SYSTEM_USER=
	mkdir -p "$WORK/bin" "$WORK/etc/opensim/opensim.d"
	cat >"$WORK/.opensim.conf" <<-INI
		[Defaults]
		EtcRoot = $WORK/etc/opensim
		SystemUser =
	INI
}

function tear_down() {
	[[ -z "${CONSOLE_PID:-}" ]] || kill "$CONSOLE_PID" 2>/dev/null || true
	rm -rf "$WORK"
}

function make_test_grid() {
	mkdir -p "$WORK/etc/opensim/grids/tender_tern/sims"
	cat >"$WORK/etc/opensim/grids/tender_tern/Robust.ini" <<'INI'
[Const]
BaseURL = "http://127.0.0.1:8002"
[GridInfoService]
gridname = "Tender Tern"
INI
	cat >"$WORK/etc/opensim/grids/tender_tern/sims/tender_tern.welcome.ini" <<'INI'
[Network]
http_listener_port = 9000
console_port = 9004
INI
	cat >"$WORK/etc/opensim/grids/tender_tern/tender_tern.conf" <<'INI'
[Grid]
Center = 8002,8002
INI
}

function test_opensim_without_command_shows_usage() {
	local output
	output=$("$OPENSIM" 2>&1)
	assert_contains "usage: opensim" "$output"
	assert_contains "setup" "$output"
}

function test_layout_env_outputs_sourceable_system_and_current_identities() {
	local api="$WORK/opensim-api" etc_real var_real logs_real
	mkdir -p "$WORK/layout/etc-target" "$WORK/layout/var-target" "$WORK/layout/logs-target"
	ln -s "$WORK/layout/etc-target" "$WORK/layout/etc-link"
	ln -s "$WORK/layout/var-target" "$WORK/layout/var-link"
	ln -s "$WORK/layout/logs-target" "$WORK/layout/logs-link"
	etc_real=$(php -r 'echo realpath($argv[1]);' "$WORK/layout/etc-link")
	var_real=$(php -r 'echo realpath($argv[1]);' "$WORK/layout/var-link")
	logs_real=$(php -r 'echo realpath($argv[1]);' "$WORK/layout/logs-link")
	export LAYOUT_ETC_ROOT="$WORK/layout/etc-link" LAYOUT_VAR_ROOT="$WORK/layout/var-link" LAYOUT_LOGS_ROOT="$WORK/layout/logs-link"
	cat >"$api" <<'API'
#!/usr/bin/env bash
[[ "$1 $2" == "GET /layout" ]] || exit 2
jq -cn --arg etc "$LAYOUT_ETC_ROOT" --arg var "$LAYOUT_VAR_ROOT" --arg logs "$LAYOUT_LOGS_ROOT" \
    '{data:{type:"layout",attributes:{systemUser:"opensim",systemUid:123,systemGroup:"opensim",systemGid:456,currentUser:"magic",currentUid:501,currentGroup:"staff",currentGid:20,etcRoot:$etc,varRoot:$var,logsRoot:$logs}}}'
API
	chmod +x "$api"
	assert_exec "OPENSIM_API='$api' '$OPENSIM' --layout --format=env" \
		--stdout-contains "OPENSIM_SYSTEM_USER='opensim'" \
		--stdout-contains "OPENSIM_SYSTEM_UID='123'" \
		--stdout-contains "OPENSIM_ADMIN_USER='magic'" \
		--stdout-contains "OPENSIM_ETC_ROOT='$WORK/layout/etc-link'" \
		--stdout-contains "CANONICAL_ETC_ROOT='$etc_real'" \
		--stdout-contains "OPENSIM_VAR_ROOT='$WORK/layout/var-link'" \
		--stdout-contains "CANONICAL_VAR_ROOT='$var_real'" \
		--stdout-contains "OPENSIM_LOGS_ROOT='$WORK/layout/logs-link'" \
		--stdout-contains "CANONICAL_LOGS_ROOT='$logs_real'" \
		--stdout-not-contains 'export '
}

function test_layout_rejects_unsupported_format() {
	assert_exec "'$OPENSIM' --layout --format=json" --exit 1 --stderr-contains '--layout requires --format=env'
}

function test_opensim_status_works() {
	assert_exec "'$OPENSIM' status"
}

function test_console_connects_to_a_running_instance() {
	local port log
	port=$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); echo substr(strrchr(stream_socket_get_name($socket, false), ":"), 1); fclose($socket);')
	log=$WORK/console-server.log
	cat >"$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini" <<INI
[Network]
http_listener_port = 9000
console_port = $port
ConsoleUser = admin
ConsolePass = secret
INI
	php -S "127.0.0.1:$port" "$(dirname "$OPENSIM")/../tests/fixtures/rest-console.php" >"$log" 2>&1 &
	CONSOLE_PID=$!
	for _ in {1..50}; do
		if php -r '$socket = @fsockopen("127.0.0.1", (int) $argv[1], $errno, $error, 0.1); if ($socket) fclose($socket); exit($socket ? 0 : 1);' "$port"; then break; fi
		sleep 0.1
	done
	assert_exec "'$OPENSIM' console tender_tern.welcome </dev/null" --stderr-contains 'Connection to tender_tern.welcome'
	kill "$CONSOLE_PID" 2>/dev/null || true
	CONSOLE_PID=
}

function test_next_port_skips_ports_in_configuration() {
	cat >"$WORK/etc/opensim/opensim.d/port-check.ini" <<'INI'
[Network]
http_listener_port = 58130
INI
	assert_exec "'$OPENSIM' next port 58130 1" --stdout '58131'
}

function test_next_location_uses_grid_center() {
	make_test_grid
	assert_exec "'$OPENSIM' next tender_tern location" --stdout '8002,8002'
}

function test_web_reports_missing_grid() {
	assert_exec "'$OPENSIM' web" --exit 2 --stderr-contains 'no local grid'
}

function test_web_shows_local_grid_services() {
	make_test_grid
	assert_exec "'$OPENSIM' web" --stdout-contains 'Grid:      tender_tern'
}

function test_web_prints_caddy_snippet() {
	make_test_grid
	assert_exec "'$OPENSIM' web tender_tern snippet caddy" --stdout-contains 'php_fastcgi'
}

function test_ban_reports_missing_grid() {
	assert_exec "'$OPENSIM' ban Resident" --exit 2 --stderr-contains 'no local grid'
}

function test_ban_requires_account_database() {
	make_test_grid
	assert_exec "'$OPENSIM' ban tender_tern Resident" --exit 1 --stderr-contains 'no account database'
}

function test_save_requires_archive_kind() {
	assert_exec "'$OPENSIM' save" --exit 2 --stderr-contains 'usage: opensim save iar|oar'
}

function test_save_iar_reports_missing_required_arguments() {
	assert_exec "'$OPENSIM' save iar" --exit 2 --stderr-contains 'missing argument'
}

function test_backup_reports_missing_grid() {
	assert_exec "'$OPENSIM' backup" --exit 1 --stderr-contains 'no grid here'
}

function test_backup_writes_grid_archive() {
	local archive
	make_test_grid
	assert_exec "'$OPENSIM' backup tender_tern --output '$WORK/backups'" --stdout-contains "$WORK/backups/tender_tern-"
	archive=$(find "$WORK/backups" -maxdepth 1 -name 'tender_tern-*.tar.gz' -print -quit)
	assert_file_exists "$archive"
}

function test_rest_delegates_to_rest_cli() {
	assert_exec "'$OPENSIM' rest --help" --stdout-contains 'Run the opensim-rest-php console client'
}

function test_enable_links_simulator_configuration() {
	make_test_grid
	assert_exec "'$OPENSIM' enable tender_tern.welcome" --stdout-contains 'simulator tender_tern.welcome enabled'
	assert_file_exists "$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini"
}

function test_disable_unlinks_simulator_configuration() {
	make_test_grid
	ln -s "$WORK/etc/opensim/grids/tender_tern/sims/tender_tern.welcome.ini" "$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini"
	assert_exec "'$OPENSIM' disable tender_tern.welcome" --stdout-contains 'simulator tender_tern.welcome disabled'
	assert_file_not_exists "$WORK/etc/opensim/opensim.d/tender_tern.welcome.ini"
}

function test_enable_applies_grid_feature_preset() {
	make_test_grid
	mkdir -p "$WORK/etc/opensim/presets/profiles"
	cat >"$WORK/etc/opensim/presets/profiles/option.conf" <<'INI'
[Option]
Label = Profiles
INI
	cat >"$WORK/etc/opensim/presets/profiles/OpenSim.ini" <<'INI'
[Startup]
TestProfileSetting = enabled
INI
	assert_exec "'$OPENSIM' enable tender_tern profiles" --stdout-contains 'profiles enabled for tender_tern'
	assert_file_contains "$WORK/etc/opensim/grids/tender_tern/sims/tender_tern.welcome.ini" 'TestProfileSetting = enabled'
}
