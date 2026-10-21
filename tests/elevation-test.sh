#!/usr/bin/env bash
# The commands run as the user the instances run as (SystemUser), checked before any question; sudo is a stand-in.
#
# Run with: tests/lib/bashunit tests/

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/opensim"

function set_up() {
    WORK="$(mktemp -d)"
    export HOME="$WORK" OPENSIM_SYSTEM_USER=nobody
    mkdir -p "$WORK/bin"
}
function tear_down() {
    rm -rf "$WORK"
}

function test_a_command_runs_as_the_system_user() {
    printf '#!/bin/sh\necho "sudo $*"\n' >"$WORK/bin/sudo"
    chmod +x "$WORK/bin/sudo"

    assert_contains "sudo -H -u nobody $OPENSIM status" "$(PATH="$WORK/bin:$PATH" "$OPENSIM" status 2>&1)"
}

function test_without_sudo_rights_it_stops_at_once_and_says_so() {
    printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/sudo"
    chmod +x "$WORK/bin/sudo"
    local output status
    output=$(PATH="$WORK/bin:$PATH" "$OPENSIM" setup 2>&1)
    status=$?

    assert_equals 1 "$status"
    assert_contains "needs sudo to act as nobody" "$output"
}

function test_a_machine_without_the_layout_gets_it_from_the_engine_through_sudo() {
    printf '#!/bin/sh\necho "sudo $*"\n' >"$WORK/bin/sudo"
    chmod +x "$WORK/bin/sudo"
    local output
    output=$(PATH="$WORK/bin:$PATH" OPENSIM_SYSTEM_USER= OPENSIM_ETC_ROOT=/nonexistent-zz/etc "$OPENSIM" setup 2>&1 </dev/null)

    assert_contains "prepare-layout" "$output"
}
