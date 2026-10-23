#!/usr/bin/env bash
# bashunit: no-parallel-tests

OPENSIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_STAGE="${_BASHUNIT_RUN_OUTPUT_DIR:?}/deploy-packages"
BUILD_ARTIFACTS="${_BASHUNIT_RUN_OUTPUT_DIR:?}/build-artifacts"
BUILD_SCRIPT="$OPENSIM_ROOT/tests/10-Build/build-packages.sh"

function test_build_sh_produces_deb_and_zip() {
	if [[ -s "${FAILURES_OUTPUT_PATH:-}" ]]; then
		bashunit::skip 'local application tests failed'
		return
	fi

	assert_exec "bash '$BUILD_SCRIPT' '$DEPLOY_STAGE' '$BUILD_ARTIFACTS'" \
		'dev/build.sh should build and stage current packages'
	assert_exec "test -s '$BUILD_ARTIFACTS/opensim-cli.zip'" \
		'.zip package should be produced by this build'
	assert_exec "test \$(find '$DEPLOY_STAGE/debs' -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ') -eq 5" \
		'all five current .deb packages should be staged'
	assert_exec "test -s '$DEPLOY_STAGE/MANIFEST'" \
		'package manifest should be created for deployment'
}

function test_current_packages_can_be_published_to_the_tests_suite() {
	if [[ "${DEPLOY_PUBLISH_TEST_PACKAGES:-0}" != 1 ]]; then
		bashunit::skip 'publishing disabled; set DEPLOY_PUBLISH_TEST_PACKAGES=1 to publish to APT suite tests'
		return
	fi
	assert_exec "bash '$OPENSIM_ROOT/tests/10-Build/publish-test-packages.sh' '$DEPLOY_STAGE/debs'"
}
