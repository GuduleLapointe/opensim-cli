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

function test_opensim_without_command_shows_usage() {
    local output
    output=$("$OPENSIM" 2>&1)
    assert_contains "usage: opensim" "$output"
    assert_contains "setup" "$output"
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
