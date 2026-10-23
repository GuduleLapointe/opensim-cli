#!/usr/bin/env bash
# Build test for opensim-cli
#
# Run with: composer test
#
# Confirms that dev/build.sh works and produces valid packages

OPENSIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_TOOLS="$OPENSIM_ROOT/vendor/bin/build-tools"
DEPLOY_STAGE="${_BASHUNIT_RUN_OUTPUT_DIR:?}/deploy-packages"

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

	mkdir -p "$DEPLOY_STAGE/debs"
	local cli_deb
	cli_deb=$(find dist -maxdepth 1 -type f -name 'opensim-cli_*.deb' -size +0c -print -quit)
	if [[ -n "$cli_deb" ]]; then cp "$cli_deb" "$DEPLOY_STAGE/debs/"; fi
	cp "$OPENSIM_ROOT/quick-install.sh" "$DEPLOY_STAGE/quick-install.sh"

	local repo package version deb
	for repo_package in \
		"$OPENSIM_ROOT/../bash-tools:bash-tools" \
		"$OPENSIM_ROOT/vendor/magicoli/opensim-engine:opensim-engine" \
		"$OPENSIM_ROOT/vendor/magicoli/opensim-rest-php:opensim-rest-php" \
		"$OPENSIM_ROOT/../opensim-helpers:opensim-helpers"; do
		repo=${repo_package%:*}
		package=${repo_package##*:}
		version=$(cd "$repo" && "$BUILD_TOOLS" version | sed -n 's/^DEB_VERSION=//p')
		deb="$repo/dist/${package}_${version}_all.deb"
		assert_exec "test -s '$deb'" "$package package matches current source hash"
		if [[ -s "$deb" ]]; then cp "$deb" "$DEPLOY_STAGE/debs/"; fi
	done

	assert_exec "test -s '$DEPLOY_STAGE/debs/opensim-cli_'*.deb" "opensim-cli package is staged for deployment"
	assert_exec "test \$(find '$DEPLOY_STAGE/debs' -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ') -eq 5" "all five current packages are staged"
	(cd "$DEPLOY_STAGE/debs" && shasum -a 256 ./*.deb >SHA256SUMS)
	(cd "$DEPLOY_STAGE" && shasum -a 256 quick-install.sh debs/*.deb >MANIFEST)
}
