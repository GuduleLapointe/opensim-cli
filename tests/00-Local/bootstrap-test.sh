#!/usr/bin/env bash

BOOTSTRAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bootstrap.sh"

function set_up() {
	WORK=$(mktemp -d)
	local project=$WORK/project
	mkdir -p "$project/tests" "$project/vendor/magicoli/opensim-engine/lib" "$WORK/home"
	cp "$BOOTSTRAP" "$project/tests/bootstrap.sh"
	cat >"$project/vendor/magicoli/opensim-engine/lib/rc-helpers" <<'HELPERS'
read_rc() {
	local file
	for file in "$1/.env" "${OPENSIM_RC:-$HOME/.opensimrc}"; do
		[[ -r "$file" ]] && source "$file"
	done
}
HELPERS
	cat >"$WORK/home/.opensimrc" <<'RC'
export PRECEDENCE=opensimrc
export RC_ONLY=from-user
export PATH="$PATH:/opensimrc-path"
RC
	cat >"$project/.env" <<'ENV'
PRECEDENCE=project
PROJECT_ONLY=from-project
ENV
	cat >"$project/tests/.env" <<'ENV'
PRECEDENCE=tests
PROJECT_ONLY=from-tests
TEST_ONLY=from-tests
ENV
	FIXTURE_BOOTSTRAP=$project/tests/bootstrap.sh
	FIXTURE_PROJECT=$project
	export FIXTURE_BOOTSTRAP FIXTURE_PROJECT
}

function tear_down() {
	rm -rf "$WORK"
}

function test_bootstrap_loads_rc_project_and_test_environment() {
	assert_exec "HOME='$WORK/home' OPENSIM_RC='$WORK/home/.opensimrc' PRECEDENCE=command bash -c 'source \"\$1\"; printf \"%s|%s|%s|%s|%s\\n\" \"\$PRECEDENCE\" \"\$RC_ONLY\" \"\$PROJECT_ONLY\" \"\$TEST_ONLY\" \"\$([[ \$PATH == *:/opensimrc-path ]] && printf path-configured)\"' _ '$FIXTURE_BOOTSTRAP'" \
		--stdout 'command|from-user|from-tests|from-tests|path-configured'
}

function test_command_line_environment_overrides_all_config_files() {
	assert_exec "HOME='$WORK/home' OPENSIM_RC='$WORK/home/.opensimrc' PRECEDENCE=command bash -c 'source \"\$1\"; printf \"%s\\n\" \"\$PRECEDENCE\"' _ '$FIXTURE_BOOTSTRAP'" \
		--stdout command
}
