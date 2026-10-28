#!/usr/bin/env bash
# The commands run as the user the instances run as (SystemUser), checked before any question; sudo is a stand-in.
#
# Run with: composer test

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

function set_up() {
    WORK="$(mktemp -d)"
    export HOME="$WORK" OPENSIM_SYSTEM_USER=nobody
    unset OPENSIM_CONF OPENSIM_RC
    mkdir -p "$WORK/bin" "$WORK/etc"
    cat >"$WORK/.opensim.conf" <<-INI
	[Defaults]
	EtcRoot = $WORK/etc
	SystemUser = nobody
	INI
}
function tear_down() {
    rm -rf "$WORK"
}

function test_a_command_runs_as_the_system_user() {
    printf '#!/bin/sh\necho "sudo $*"\n' >"$WORK/bin/sudo"
    chmod +x "$WORK/bin/sudo"

    assert_contains "sudo -u nobody --preserve-env=" "$(PATH="$WORK/bin:$PATH" "$OPENSIM" status 2>&1)"
}

function test_without_sudo_rights_it_stops_at_once_and_says_so() {
    printf '#!/bin/sh\necho "sudo: access denied for nobody" >&2\nexit 1\n' >"$WORK/bin/sudo"
    chmod +x "$WORK/bin/sudo"
	assert_exec "PATH='$WORK/bin:$PATH' '$OPENSIM' setup 2>&1" \
		--exit 1 \
		--stdout-contains 'sudo: access denied for nobody'
}

function test_setup_does_not_escalate_to_root_for_the_system_layout() {
    printf '#!/bin/sh\necho "sudo $*"\n' >"$WORK/bin/sudo"
    chmod +x "$WORK/bin/sudo"
    local output real_php
    real_php=$(command -v php)
    cat >"$WORK/bin/php" <<-PHP
	#!/usr/bin/env bash
	if [[ "\${2:-}" == system-user ]]; then printf 'nobody\n'; else exec "$real_php" "\$@"; fi
	PHP
    chmod +x "$WORK/bin/php"
    output=$(PATH="$WORK/bin:$PATH" "$OPENSIM" setup 2>&1 </dev/null)

    assert_contains "sudo -u nobody" "$output"
    assert_not_contains "prepare-layout" "$output"
}
