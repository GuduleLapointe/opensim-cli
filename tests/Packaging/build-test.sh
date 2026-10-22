#!/usr/bin/env bash
# Build test for opensim-cli
#
# Run with: tests/lib/bashunit tests/
#
# Confirms that dev/build.sh works and produces valid packages

OPENSIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up() {
	WORK="$(mktemp -d)"
}

function tear_down() {
	rm -rf "$WORK"
}

function test_build_sh_produces_deb_and_zip() {
	cd "$OPENSIM_ROOT"
	local output status

	# there must be no .deb packages in tests dist/ before build
	# assert_exit_code 1 $(ls dist/*.deb 1>/dev/null 2>&1)

	# build test packags
	assert_exec "DIRTY=1 ./dev/build.sh 2>&1" "dev/build.sh should succeed"

	# Check .deb file exists
	assert_exec "ls dist/*.deb 1>/dev/null 2>&1" ".deb files should be found in dist/"

	# Check .zip file exists
	assert_exec "ls dist/*.zip 1>/dev/null 2>&1" ".zip files should be found in dist/"
}
