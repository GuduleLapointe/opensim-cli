#!/usr/bin/env bash

set -u

OPENSIM_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASHUNIT="$OPENSIM_ROOT/lib/bashunit/bashunit"

if [[ -z "${COMPAT_RUN_ID:-}" ]]; then
	COMPAT_RUN_ID="suite-$(date +%s)-$$"
	export COMPAT_RUN_ID
fi

run_phase() {
	local phase=$1
	shift
	printf '\n=== %s ===\n' "$phase"
	"$BASHUNIT" "$@"
}

run_phase '1. Local application tests' \
	"$OPENSIM_ROOT/tests/elevation-test.sh" \
	"$OPENSIM_ROOT/tests/setup-test.sh" \
	"$OPENSIM_ROOT/tests/Integration/cli-test.sh" || exit $?

run_phase '2. Package build tests' \
	"$OPENSIM_ROOT/tests/Packaging/build-test.sh" || exit $?

run_phase '3. Compatibility tests' \
	"$OPENSIM_ROOT/tests/Compatibility" \
	|| compatibility_status=$?

run_phase '4. Final container cleanup' \
	"$OPENSIM_ROOT/tests/zz-cleanup-test.sh" || cleanup_status=$?

if [[ -n "${compatibility_status:-}" ]]; then
	exit "$compatibility_status"
fi
exit "${cleanup_status:-0}"
