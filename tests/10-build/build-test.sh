#!/usr/bin/env bash
# Build test for opensim-cli
#
# Run with: composer test
#
# Confirms that dev/build.sh works and produces valid packages

OPENSIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up() {
	WORK="$(mktemp -d "$OPENSIM_ROOT/tests/.build-test.XXXXXX")"
	BUILD_PROJECT="$WORK/project"
	git clone --quiet --shared --no-checkout "$OPENSIM_ROOT" "$BUILD_PROJECT"
	git -C "$BUILD_PROJECT" checkout --quiet --detach HEAD
	git clone --quiet --shared --no-checkout "$OPENSIM_ROOT/../opensim-engine" "$WORK/opensim-engine"
	git -C "$WORK/opensim-engine" checkout --quiet --detach HEAD
	git clone --quiet --shared --no-checkout "$OPENSIM_ROOT/../opensim-rest-php" "$WORK/opensim-rest-php"
	git -C "$WORK/opensim-rest-php" checkout --quiet --detach HEAD
	ln -s "$OPENSIM_ROOT/vendor" "$BUILD_PROJECT/vendor"
}

function tear_down() {
	rm -rf "$WORK"
}

function test_build_sh_produces_deb_and_zip() {
	if [[ -s "${FAILURES_OUTPUT_PATH:-}" ]]; then
		bashunit::skip 'local application tests failed'
		return
	fi

	cd "$BUILD_PROJECT"

	# Build in an isolated project copy so build-tools' dist/, build/ and other
	# generated files stay beneath tests/ and never touch the developer checkout.
	mkdir -p dist
	find dist -mindepth 1 -maxdepth 1 -type f -delete
	assert_exec "DIRTY=1 ./dev/build.sh 2>&1" "dev/build.sh should succeed"

	# The isolated dist/ was emptied immediately before this build, so these
	# non-empty files must have been produced by this invocation.
	assert_exec "find dist -maxdepth 1 -type f -name '*.deb' -size +0c -print -quit | grep -q ." ".deb package should be produced by this build"

	assert_exec "find dist -maxdepth 1 -type f -name '*.zip' -size +0c -print -quit | grep -q ." ".zip package should be produced by this build"
}
