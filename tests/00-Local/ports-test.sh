#!/usr/bin/env bash

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"

function set_up() {
	WORK=$(mktemp -d)
	export HOME="$WORK" OPENSIM_SYSTEM_USER=
	unset OPENSIM_CONF OPENSIM_API
	mkdir -p "$WORK/etc/robust.d" "$WORK/etc/opensim.d" "$WORK/regions"
	cat >"$WORK/.opensim.conf" <<-INI
		[Defaults]
		EtcRoot = $WORK/etc
		SystemUser =
	INI
	cat >"$WORK/etc/robust.d/example.ini" <<-'INI'
		[Const]
		PublicPort = 8002
		PrivatePort = 8003
		[Network]
		;ConsolePort = 8004
	INI
	cat >"$WORK/etc/opensim.d/example.plaza.ini" <<-INI
		[Network]
		http_listener_port = 9000
		console_port = 9004
		ConsoleUser = admin
		ConsolePass = secret
		[Startup]
		regionload_regionsdir = $WORK/regions
	INI
	cat >"$WORK/regions/Plaza.ini" <<-'INI'
		[Grand Place]
		InternalPort = 9048
		[Petite Place]
		InternalPort = 9049
	INI
}

function tear_down() {
	rm -rf "$WORK"
}

function test_ports_table_describes_each_listener() {
	assert_exec "'$OPENSIM' ports >'$WORK/table'"
	local output
	output=$(cat "$WORK/table")
	assert_contains 'INSTANCE' "$output"
	assert_contains 'PROTO' "$output"
	assert_contains 'example.plaza' "$output"
	assert_contains '9048' "$output"
	assert_contains 'region Grand Place' "$output"
	assert_contains 'private' "$output"
	assert_contains 'off' "$output"
}

function test_ports_publish_preserves_tcp_udp_and_private_bindings() {
	assert_exec "'$OPENSIM' ports --publish" \
		--stdout '-p 8002:8002 -p 127.0.0.1:8003:8003 -p 9000:9000 -p 127.0.0.1:9004:9004 -p 9048:9048/udp -p 9049:9049/udp'
}

function test_ports_ufw_keeps_private_rules_as_comments() {
	local output
	assert_exec "'$OPENSIM' ports --ufw >'$WORK/ufw'"
	output=$(cat "$WORK/ufw")
	assert_contains 'ufw allow 9000/tcp' "$output"
	assert_contains 'ufw allow 9048/udp' "$output"
	assert_contains '# 9004/tcp' "$output"
	assert_not_contains $'\nufw allow 9004/tcp' "$output"
	assert_not_contains '8004/tcp' "$output"
}

function test_ports_selects_one_instance() {
	assert_exec "'$OPENSIM' ports example.plaza --publish" \
		--stdout '-p 9000:9000 -p 127.0.0.1:9004:9004 -p 9048:9048/udp -p 9049:9049/udp'
}

function test_ports_deduplicates_mappings_without_merging_protocols() {
	cat >"$WORK/regions/Shared.ini" <<-'INI'
		[Shared A]
		InternalPort = 9000
		[Shared B]
		InternalPort = 9000
	INI
	assert_exec "'$OPENSIM' ports example.plaza example.plaza --publish" \
		--stdout '-p 9000:9000 -p 9000:9000/udp -p 127.0.0.1:9004:9004 -p 9048:9048/udp -p 9049:9049/udp'
}

function test_ports_accepts_private_address_with_space_or_equals() {
	assert_exec "'$OPENSIM' ports example --publish --private-address 192.0.2.10" \
		--stdout '-p 8002:8002 -p 192.0.2.10:8003:8003'
	assert_exec "'$OPENSIM' ports example --publish --private-address=::1" \
		--stdout '-p 8002:8002 -p [::1]:8003:8003'
}

function test_ports_unknown_instance_fails_without_partial_output() {
	assert_exec "'$OPENSIM' ports example missing --publish" \
		--exit 1 --stdout '' --stderr-contains 'no ini file found for missing'
}

function test_ports_without_instances_reports_the_problem() {
	rm "$WORK/etc/robust.d/example.ini" "$WORK/etc/opensim.d/example.plaza.ini"
	assert_exec "'$OPENSIM' ports" \
		--exit 1 --stdout '' --stderr-contains 'no enabled instance'
}

function test_ports_rejects_unknown_options_and_invalid_addresses() {
	assert_exec "'$OPENSIM' ports --unknown" \
		--exit 2 --stderr-contains 'unknown ports option'
	assert_exec "'$OPENSIM' ports --publish --ufw" \
		--exit 2 --stderr-contains 'choose either --publish or --ufw'
	assert_exec "'$OPENSIM' ports --private-address=invalid" \
		--exit 2 --stderr-contains 'private address must be an IPv4 or IPv6 address'
}

function test_ports_help_and_completion_are_available() {
	assert_exec "'$OPENSIM' ports --help >'$WORK/help'"
	assert_contains --publish "$(cat "$WORK/help")"
	assert_contains --ufw "$(cat "$WORK/help")"
	source "$(dirname "$OPENSIM")/../share/bash-completion/opensim"
	COMP_WORDS=(opensim por) COMP_CWORD=1
	_opensim
	assert_contains ports "${COMPREPLY[*]}"
	COMP_WORDS=(opensim ports --p) COMP_CWORD=2
	_opensim
	assert_contains --publish "${COMPREPLY[*]}"
}
