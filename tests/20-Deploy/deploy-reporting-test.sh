#!/usr/bin/env bash

DEPLOY_HELPERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"

function set_up() {
	WORK=$(mktemp -d)
}

function tear_down() {
	rm -rf "$WORK"
}

function test_container_creation_failure_shows_podman_error() {
	cat >"$WORK/fail-create" <<'COMMAND'
#!/usr/bin/env bash
printf 'rootless netns: permission denied\n' >&2
exit 244
COMMAND
	chmod +x "$WORK/fail-create"
	assert_exec "bash -c 'source \"\$1\"; deploy_create_container \"\$2/create.log\" \"\$2/fail-create\"' _ '$DEPLOY_HELPERS' '$WORK'" \
		--exit 244 \
		--stdout-contains 'rootless netns: permission denied'
}

function test_container_install_failure_shows_service_error() {
	cat >"$WORK/fail-exec" <<'COMMAND'
#!/usr/bin/env bash
printf 'mysqladmin: connect failed\n' >&2
exit 1
COMMAND
	chmod +x "$WORK/fail-exec"
	assert_exec "DEPLOY_CONTAINER_CLI='$WORK/fail-exec' bash -c 'source \"\$1\"; deploy_install_check sample mariadb \"\$2/install.log\"' _ '$DEPLOY_HELPERS' '$WORK'" \
		--exit 1 \
		--stdout-contains 'MariaDB responds check failed (exit 1)'
}

function test_quick_install_copy_failure_names_container() {
	cat >"$WORK/fail-copy" <<'COMMAND'
#!/usr/bin/env bash
printf 'copy denied\n' >&2
exit 1
COMMAND
	chmod +x "$WORK/fail-copy"
	assert_exec "DEPLOY_CONTAINER_CLI='$WORK/fail-copy' bash -c 'source \"\$1\"; deploy_install_step sample \"\$2/install.log\" /tmp/install.log --dependencies dependencies 60 charm-tests dev' _ '$DEPLOY_HELPERS' '$WORK'" \
		--exit 1 \
		--stdout-contains 'Could not copy quick-install.sh to sample'
}

function test_deploy_platform_filter_skips_other_platforms() {
	assert_exec "DEPLOY_PLATFORM=debian-12 bash -c 'source \"\$1\"; deploy_load_platform ubuntu-24.04' _ '$DEPLOY_HELPERS'" --exit 1
}

function test_deploy_platform_filter_does_not_leak_between_platforms() {
	assert_exec "bash -c 'source \"\$1\"; deploy_load_platform debian-12; source \"\$1\"; deploy_load_platform ubuntu-24.04' _ '$DEPLOY_HELPERS'"
}

function test_container_status_failure_is_asserted() {
	assert_exec "bash -c 'source \"\$1\"; deploy_select_engine() { return 0; }; deploy_command() { printf \"Podman tunnel timed out\\n\"; return 255; }; deploy_assert_exec() { printf \"ASSERTED: %s\\n\" \"\$1\"; return 1; }; assert_deployment_container_running sample' _ '$DEPLOY_HELPERS'" \
		--exit 1 \
		--stdout-contains 'ASSERTED: deploy_command status opensim-deploy-'
}

function test_container_start_status_failure_is_asserted() {
	assert_exec "bash -c 'source \"\$1\"; DEPLOY_PLATFORM=sample; DEPLOY_IMAGE=debian:12; bashunit::set_test_title() { :; }; deploy_command() { printf \"Podman tunnel timed out\\n\"; return 255; }; deploy_assert_exec() { printf \"ASSERTED: %s\\n\" \"\$1\"; return 0; }; deploy_run_step started' _ '$DEPLOY_HELPERS'" \
		--stdout-contains 'ASSERTED: deploy_command status opensim-deploy-'
}
