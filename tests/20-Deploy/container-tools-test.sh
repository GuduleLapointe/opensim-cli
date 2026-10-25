#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"

function test_container_tools_does_not_require_local_podman() {
	local temporary_bin helper
	temporary_bin=$(mktemp -d)
	ln -s "$(command -v php)" "$temporary_bin/php"
	cat >"$temporary_bin/container-tools" <<-'CLI'
		#!/usr/bin/env bash
		exit 0
	CLI
	chmod +x "$temporary_bin/container-tools"

	helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"
	assert_exec "PATH='$temporary_bin' DEPLOY_CONTAINER_CLI='$temporary_bin/container-tools' '$(command -v bash)' -c 'source \"\$1\"; deploy_select_engine' _ '$helper'"
	rm -rf "$temporary_bin"
}
