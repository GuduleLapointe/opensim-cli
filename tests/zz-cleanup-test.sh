#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/20-Deploy" && pwd)/deploy-test-helpers.sh"

while read -r platform _; do
	[[ -z "$platform" || "$platform" == \#* ]] && continue
	function_name="test_90_cleanup_${platform//[^[:alnum:]_]/_}"
	eval "function $function_name() { deploy_cleanup_platform '$platform'; }"
done <"$DEPLOY_PLATFORMS_FILE"
