#!/usr/bin/env bash

COMPAT_PLATFORMS_FILE=${COMPAT_PLATFORMS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platforms.tsv}
COMPAT_RUN_DIR=${_BASHUNIT_RUN_OUTPUT_DIR:-${TMPDIR:-/tmp}/bashunit/compat-$$}
COMPAT_RUN_ID=${COMPAT_RUN_ID:-${COMPAT_RUN_DIR##*/}}
COMPAT_GATE_BLOCK_FILE=$COMPAT_RUN_DIR/compatibility-blocked
COMPAT_ENGINE_SELECTED=
COMPAT_PLATFORM=
COMPAT_IMAGE=
COMPAT_EXPECTED_ID=
COMPAT_EXPECTED_VERSION=

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

compat_load_platform() {
	local requested=$1 platform image expected_id expected_version
	COMPAT_PLATFORM=
	while read -r platform image expected_id expected_version; do
		[[ -z "$platform" || "$platform" == \#* ]] && continue
		if [[ "$platform" == "$requested" ]]; then
			COMPAT_PLATFORM=$platform
			COMPAT_IMAGE=$image
			COMPAT_EXPECTED_ID=$expected_id
			COMPAT_EXPECTED_VERSION=$expected_version
			break
		fi
	done <"$COMPAT_PLATFORMS_FILE"
	if [[ -z "$COMPAT_PLATFORM" ]]; then
		printf 'Compatibility platform not found in %s: %s\n' "$COMPAT_PLATFORMS_FILE" "$requested" >&2
		return 1
	fi
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

compat_test_gate() {
	local failure_file=${FAILURES_OUTPUT_PATH:-$COMPAT_RUN_DIR/failures}
	bashunit::set_test_title "$COMPAT_PLATFORM prerequisites passed"
	mkdir -p "$COMPAT_RUN_DIR"
	if [[ -s "$failure_file" ]]; then
		: >"$COMPAT_GATE_BLOCK_FILE"
		bashunit::skip 'local tests or package build failed'
		return
	fi
	if [[ -e "$COMPAT_GATE_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests or package build failed'
		return
	fi
	assert_equals 0 0 'compatibility gate is open'
}

compat_run_step() {
	local step=$1 name status=0 actual
	name=$(compat_name "$COMPAT_PLATFORM")
	bashunit::set_test_title "$COMPAT_PLATFORM $step"
	if [[ -e "$COMPAT_GATE_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests or package build failed'
		return
	fi

	case "$step" in
		created)
			if ! compat_select_engine; then status=127; else
				compat_command create --name "$name" \
					--label org.opensim-cli.compatibility=1 \
					--label "org.opensim-cli.compatibility.platform=$COMPAT_PLATFORM" \
					--label "org.opensim-cli.compatibility.run=$COMPAT_RUN_ID" \
					--memory="${MEMORY:-400m}" "$COMPAT_IMAGE" sh -c 'while :; do sleep 3600; done' >/dev/null || status=$?
			fi
			assert_equals 0 "$status" "$COMPAT_PLATFORM create"
			;;
		started)
			if ! compat_select_engine || ! compat_command inspect "$name" >/dev/null 2>&1; then
				bashunit::skip "$COMPAT_PLATFORM not created"
				return
			fi
			compat_command start "$name" >/dev/null || status=$?
			assert_equals 0 "$status" "$COMPAT_PLATFORM start"
			;;
		running)
			if compat_skip_unless_running "$COMPAT_PLATFORM"; then return; fi
			actual=$(compat_command inspect --format '{{.State.Running}}' "$name") || status=$?
			assert_equals true "$actual" "$COMPAT_PLATFORM running"
			;;
		ready)
			if compat_skip_unless_running "$COMPAT_PLATFORM"; then return; fi
			compat_command exec "$name" sh -c 'test -r /etc/os-release && test -x /bin/sh' >/dev/null || status=$?
			assert_equals 0 "$status" "$COMPAT_PLATFORM shell ready"
			;;
		id)
			if compat_skip_unless_running "$COMPAT_PLATFORM"; then return; fi
			actual=$(compat_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$ID"') || status=$?
			assert_equals "$COMPAT_EXPECTED_ID" "$actual" "$COMPAT_PLATFORM ID"
			;;
		version)
			if compat_skip_unless_running "$COMPAT_PLATFORM"; then return; fi
			actual=$(compat_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$VERSION_ID"') || status=$?
			assert_equals "$COMPAT_EXPECTED_VERSION" "$actual" "$COMPAT_PLATFORM version"
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
