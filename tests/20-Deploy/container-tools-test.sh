#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"

function test_container_tools_does_not_require_local_podman() {
	local previous_path=$PATH temporary_bin status=0
	temporary_bin=$(mktemp -d)
	ln -s "$(command -v php)" "$temporary_bin/php"
	cat >"$temporary_bin/container-tools" <<-'CLI'
		#!/usr/bin/env bash
		exit 0
	CLI
	chmod +x "$temporary_bin/container-tools"

	PATH=$temporary_bin
	DEPLOY_CONTAINER_CLI=$temporary_bin/container-tools
	hash -r
	deploy_select_engine || status=$?

	PATH=$previous_path
	hash -r
	rm -rf "$temporary_bin"
	assert_equals 0 "$status"
}
