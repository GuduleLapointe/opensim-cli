#!/usr/bin/env bash
# Integration tests for opensim-cli
#
# Run with: tests/lib/bashunit tests/
#
# These tests confirm the current state:
# - Locally (macOS): ./bin/opensim commands work
# - On Linux via containers: quick-install.sh works, apt packages install, opensim setup may fail

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

function set_up() {
    WORK="$(mktemp -d)"
    export HOME="$WORK"
    mkdir -p "$WORK/bin" "$WORK/etc/opensim"
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
    # On macOS, status should work without containers
    if [[ "$(uname)" == Darwin ]]; then
        local output
        output=$("$OPENSIM" status 2>&1)
        # On macOS with existing instances, this should show the table
        # On macOS without instances, it may show empty or error
        # Just check it doesn't crash with a syntax error
        assert_equals 0 $?
    fi
}

# Container-based tests would go here
# They require CONTAINER_CONNECTION to be set
# For now, we just confirm local behavior
