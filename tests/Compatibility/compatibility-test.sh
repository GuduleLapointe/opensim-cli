#!/usr/bin/env bash
# bashunit: no-parallel-tests

COMPAT_PLATFORMS_FILE=${COMPAT_PLATFORMS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platforms.tsv}
COMPAT_RUN_DIR=${_BASHUNIT_RUN_OUTPUT_DIR:-${TMPDIR:-/tmp}/bashunit/compat-$$}
COMPAT_RUN_ID=${COMPAT_RUN_DIR##*/}
COMPAT_GATE_BLOCK_FILE=$COMPAT_RUN_DIR/compatibility-blocked
COMPAT_ENGINE_SELECTED=

compat_select_engine() {
	case "${COMPAT_ENGINE:-auto}" in
		auto) if command -v podman >/dev/null 2>&1; then COMPAT_ENGINE_SELECTED=podman; elif command -v docker >/dev/null 2>&1; then COMPAT_ENGINE_SELECTED=docker; else return 1; fi ;;
		podman|docker) command -v "$COMPAT_ENGINE" >/dev/null 2>&1 || return 1; COMPAT_ENGINE_SELECTED=$COMPAT_ENGINE ;;
		*) return 1 ;;
	esac
}

compat_command() {
	if [[ "$COMPAT_ENGINE_SELECTED" == podman && -n "${CONTAINER_CONNECTION:-}" ]]; then
		podman --connection "$CONTAINER_CONNECTION" "$@"
	else
		"$COMPAT_ENGINE_SELECTED" "$@"
	fi
}

compat_name() {
	printf 'opensim-compat-%s-%s' "$1" "$COMPAT_RUN_ID"
}

compat_skip_unless_running() {
	local platform=$1 name state
	name=$(compat_name "$platform")
	if ! compat_select_engine || ! compat_command inspect "$name" >/dev/null 2>&1; then
		bashunit::skip "$platform not created"
		return 0
	fi
	state=$(compat_command inspect --format '{{.State.Running}}' "$name" 2>/dev/null) || state=false
	if [[ "$state" != true ]]; then
		bashunit::skip "$platform not running"
		return 0
	fi
	return 1
}

compat_run_step() {
	local step=$1 platform=$2 image=$3 expected_id=$4 expected_version=$5
	local name status=0 actual
	name=$(compat_name "$platform")
	bashunit::set_test_title "$platform $step"
	if [[ -e "$COMPAT_GATE_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests or package build failed'
		return
	fi

	case "$step" in
		created)
			if ! compat_select_engine; then status=127; else
				compat_command create --name "$name" \
					--label org.opensim-cli.compatibility=1 \
					--label "org.opensim-cli.compatibility.platform=$platform" \
					--label "org.opensim-cli.compatibility.run=$COMPAT_RUN_ID" \
					--memory="${MEMORY:-400m}" "$image" sh -c 'while :; do sleep 3600; done' >/dev/null || status=$?
			fi
			assert_equals 0 "$status" "$platform create"
			;;
		started)
			if ! compat_select_engine || ! compat_command inspect "$name" >/dev/null 2>&1; then
				bashunit::skip "$platform not created"
				return
			fi
			compat_command start "$name" >/dev/null || status=$?
			assert_equals 0 "$status" "$platform start"
			;;
		running)
			if compat_skip_unless_running "$platform"; then return; fi
			actual=$(compat_command inspect --format '{{.State.Running}}' "$name") || status=$?
			assert_equals 0 "$status" "$platform inspect state"
			assert_equals true "$actual" "$platform running"
			;;
		ready)
			if compat_skip_unless_running "$platform"; then return; fi
			compat_command exec "$name" sh -c 'test -r /etc/os-release && test -x /bin/sh' >/dev/null || status=$?
			assert_equals 0 "$status" "$platform shell ready"
			;;
		id)
			if compat_skip_unless_running "$platform"; then return; fi
			actual=$(compat_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$ID"') || status=$?
			assert_equals 0 "$status" "$platform read ID"
			assert_equals "$expected_id" "$actual" "$platform ID"
			;;
		version)
			if compat_skip_unless_running "$platform"; then return; fi
			actual=$(compat_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$VERSION_ID"') || status=$?
			assert_equals 0 "$status" "$platform read version"
			assert_equals "$expected_version" "$actual" "$platform version"
			;;
	esac
}

compat_cleanup_platform() {
	local platform=$1 name status=0
	name=$(compat_name "$platform")
	bashunit::set_test_title "$platform cleanup"
	if [[ "${COMPAT_KEEP:-0}" == 1 ]]; then
		bashunit::skip 'containers kept for inspection'
		return
	fi
	if ! compat_select_engine || ! compat_command inspect "$name" >/dev/null 2>&1; then
		bashunit::skip "$platform not created"
		return
	fi
	compat_command rm --force "$name" >/dev/null || status=$?
	assert_equals 0 "$status" "$platform cleanup"
}

function test_00_compatibility_gate() {
	bashunit::set_test_title 'Local tests and build passed'
	local failure_file=${FAILURES_OUTPUT_PATH:-$COMPAT_RUN_DIR/failures} gate_status=0
	mkdir -p "$COMPAT_RUN_DIR"
	if [[ -s "$failure_file" ]]; then
		: >"$COMPAT_GATE_BLOCK_FILE"
		bashunit::skip 'local tests or package build failed'
		return
	fi
	[[ ! -e "$COMPAT_GATE_BLOCK_FILE" ]] || gate_status=1
	assert_equals 0 "$gate_status" 'compatibility gate is open'
}

# Register separate tests in platform-major order, matching the TSV order.
compat_register_platform_tests() {
	local platform=$1 image=$2 expected_id=$3 expected_version=$4 order=$5 safe fn step_index step definition
	safe=${platform//[^a-zA-Z0-9_]/_}
	step_index=0
	for step in created started running ready id version; do
		step_index=$((step_index + 1))
		fn=$(printf 'test_%02d_%s_%02d_%s' "$order" "$safe" "$step_index" "$step")
		printf -v definition 'function %s() { compat_run_step %q %q %q %q %q; }' \
			"$fn" "$step" "$platform" "$image" "$expected_id" "$expected_version"
		eval "$definition"
	done
}

compat_platform_order=0
compat_platforms=()
while read -r compat_platform compat_image compat_id compat_version; do
	[[ -z "$compat_platform" || "$compat_platform" == \#* ]] && continue
	[[ "$compat_platform" =~ ^[a-zA-Z0-9._-]+$ ]] || { printf 'Invalid platform key: %s\n' "$compat_platform" >&2; continue; }
	compat_platform_order=$((compat_platform_order + 1))
	compat_platforms[${#compat_platforms[@]}]=$compat_platform
	compat_register_platform_tests "$compat_platform" "$compat_image" "$compat_id" "$compat_version" "$compat_platform_order"
done <"$COMPAT_PLATFORMS_FILE"

# Cleanup tests are declared after every platform test so containers remain
# available in Podman Desktop throughout the full compatibility matrix.
compat_cleanup_order=0
for compat_platform in "${compat_platforms[@]}"; do
	compat_cleanup_order=$((compat_cleanup_order + 1))
	compat_safe=${compat_platform//[^a-zA-Z0-9_]/_}
	compat_fn=$(printf 'test_99_%02d_%s_cleanup' "$compat_cleanup_order" "$compat_safe")
	printf -v compat_definition 'function %s() { compat_cleanup_platform %q; }' \
		"$compat_fn" "$compat_platform"
	eval "$compat_definition"
done
