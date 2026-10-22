#!/usr/bin/env bash
# bashunit: no-parallel-tests

COMPAT_PLATFORMS_FILE=${COMPAT_PLATFORMS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platforms.tsv}
COMPAT_RUN_ID=${_BASHUNIT_RUN_OUTPUT_DIR:-}
COMPAT_RUN_ID=${COMPAT_RUN_ID##*/}
[[ -n "$COMPAT_RUN_ID" ]] || COMPAT_RUN_ID="manual-$$"
COMPAT_ENGINE_SELECTED=

compatibility_platforms() {
	local platform image expected_id expected_version
	while read -r platform image expected_id expected_version; do
		[[ -z "$platform" || "$platform" == \#* ]] && continue
		printf '%q %q %q %q\n' "$platform" "$image" "$expected_id" "$expected_version"
	done <"$COMPAT_PLATFORMS_FILE"
}

compat_select_engine() {
	case "${COMPAT_ENGINE:-auto}" in
		auto) if command -v podman >/dev/null 2>&1; then COMPAT_ENGINE_SELECTED=podman; elif command -v docker >/dev/null 2>&1; then COMPAT_ENGINE_SELECTED=docker; else return 1; fi ;;
		podman|docker) command -v "${COMPAT_ENGINE}" >/dev/null 2>&1 || return 1; COMPAT_ENGINE_SELECTED=$COMPAT_ENGINE ;;
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

compat_title() {
	bashunit::set_test_title "$1: $2 ($(compat_name "$1"))"
}

compat_skip_if_missing() {
	local platform=$1 prerequisite=$2 name
	name=$(compat_name "$platform")
	if ! compat_select_engine || ! compat_command inspect "$name" >/dev/null 2>&1; then
		bashunit::skip "$platform: $prerequisite unavailable; step skipped"
		return 0
	fi
	return 1
}

compat_skip_if_not_running() {
	local platform=$1 name state
	name=$(compat_name "$platform")
	if ! compat_select_engine || ! compat_command inspect "$name" >/dev/null 2>&1; then
		bashunit::skip "$platform: container was not created; step skipped"
		return 0
	fi
	state=$(compat_command inspect --format '{{.State.Running}}' "$name" 2>/dev/null) || state=false
	if [[ "$state" != true ]]; then
		bashunit::skip "$platform: container is not running; step skipped"
		return 0
	fi
	return 1
}

# @data_provider compatibility_platforms
function test_platform_container_created() {
	local platform=$1 image=$2 name status=0
	name=$(compat_name "$platform")
	compat_title "$platform" "container created from $image"
	if ! compat_select_engine; then status=127; else
		compat_command create --name "$name" --label org.opensim-cli.compatibility=1 \
			--memory="${MEMORY:-400m}" "$image" sh -c 'while :; do sleep 3600; done' >/dev/null || status=$?
	fi
	assert_equals 0 "$status" "$platform: create container from $image"
}

# @data_provider compatibility_platforms
function test_platform_container_started() {
	local platform=$1 image=$2 name status=0
	name=$(compat_name "$platform")
	compat_title "$platform" 'container started'
	if compat_skip_if_missing "$platform" 'container creation'; then return; fi
	compat_command start "$name" >/dev/null || status=$?
	assert_equals 0 "$status" "$platform: start container"
}

# @data_provider compatibility_platforms
function test_platform_container_is_running() {
	local platform=$1 image=$2 name state status=0
	name=$(compat_name "$platform")
	compat_title "$platform" 'container reports running'
	if compat_skip_if_missing "$platform" 'container creation'; then return; fi
	state=$(compat_command inspect --format '{{.State.Running}}' "$name" 2>/dev/null) || status=$?
	assert_equals 0 "$status" "$platform: inspect container state"
	assert_equals true "$state" "$platform: container is running"
}

# @data_provider compatibility_platforms
function test_platform_shell_is_ready() {
	local platform=$1 image=$2 name status=0
	name=$(compat_name "$platform")
	compat_title "$platform" 'shell and release file are ready'
	if compat_skip_if_not_running "$platform"; then return; fi
	compat_command exec "$name" sh -c 'test -r /etc/os-release && test -x /bin/sh' >/dev/null || status=$?
	assert_equals 0 "$status" "$platform: shell runs and /etc/os-release is readable"
}

# @data_provider compatibility_platforms
function test_platform_os_id_matches() {
	local platform=$1 image=$2 expected_id=$3 expected_version=$4 name actual status=0
	name=$(compat_name "$platform")
	compat_title "$platform" "operating system ID is $expected_id"
	if compat_skip_if_not_running "$platform"; then return; fi
	actual=$(compat_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$ID"' 2>/dev/null) || status=$?
	assert_equals 0 "$status" "$platform: read operating system ID"
	assert_equals "$expected_id" "$actual" "$platform: operating system ID"
}

# @data_provider compatibility_platforms
function test_platform_os_version_matches() {
	local platform=$1 image=$2 expected_id=$3 expected_version=$4 name actual status=0
	name=$(compat_name "$platform")
	compat_title "$platform" "operating system version is $expected_version"
	if compat_skip_if_not_running "$platform"; then return; fi
	actual=$(compat_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$VERSION_ID"' 2>/dev/null) || status=$?
	assert_equals 0 "$status" "$platform: read operating system version"
	assert_equals "$expected_version" "$actual" "$platform: operating system version"
}

function tear_down_after_script() {
	local platform image expected_id expected_version name
	while read -r platform image expected_id expected_version; do
		[[ -z "$platform" || "$platform" == \#* ]] && continue
		name=$(compat_name "$platform")
		if compat_select_engine && compat_command inspect "$name" >/dev/null 2>&1; then
			compat_command rm --force "$name" >/dev/null 2>&1 || true
		fi
	done <"$COMPAT_PLATFORMS_FILE"
}
