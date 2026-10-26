#!/usr/bin/env bash
# Integration tests for opensim-cli
#
# Run with: composer test
#
# These tests confirm the current state:
# - Locally (macOS): ./bin/opensim commands work
# - Deploy containers are tested separately after the local tests and package build

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

function set_up() {
    WORK="$(mktemp -d)"
    export HOME="$WORK"
    unset OPENSIM_CONF OPENSIM_RC
    export OPENSIM_SYSTEM_USER=
    mkdir -p "$WORK/bin" "$WORK/etc/opensim"
    cat >"$WORK/.opensim.conf" <<-INI
	[Defaults]
	EtcRoot = $WORK/etc/opensim
	SystemUser =
	INI
}

function tear_down() {
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
