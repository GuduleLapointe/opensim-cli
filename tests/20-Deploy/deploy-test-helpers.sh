#!/usr/bin/env bash

DEPLOY_PLATFORMS_FILE=${DEPLOY_PLATFORMS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platforms.tsv}
DEPLOY_RUN_DIR=${_BASHUNIT_RUN_OUTPUT_DIR:-${TMPDIR:-/tmp}/bashunit/deploy-$$}
DEPLOY_RUN_ID=${DEPLOY_RUN_ID:-${DEPLOY_RUN_DIR##*/}}
DEPLOY_GATE_BLOCK_FILE=$DEPLOY_RUN_DIR/deployment-blocked
DEPLOY_ENGINE_SELECTED=
DEPLOY_PLATFORM=
DEPLOY_IMAGE=
DEPLOY_EXPECTED_ID=
DEPLOY_EXPECTED_VERSION=

deploy_select_engine() {
	case "${DEPLOY_ENGINE:-auto}" in
		auto) if command -v podman >/dev/null 2>&1; then DEPLOY_ENGINE_SELECTED=podman; elif command -v docker >/dev/null 2>&1; then DEPLOY_ENGINE_SELECTED=docker; else return 1; fi ;;
		podman|docker) command -v "$DEPLOY_ENGINE" >/dev/null 2>&1 || return 1; DEPLOY_ENGINE_SELECTED=$DEPLOY_ENGINE ;;
		*) return 1 ;;
	esac
}

deploy_command() {
	if [[ "$DEPLOY_ENGINE_SELECTED" == podman && -n "${CONTAINER_CONNECTION:-}" ]]; then
		podman --connection "$CONTAINER_CONNECTION" "$@"
	else
		"$DEPLOY_ENGINE_SELECTED" "$@"
	fi
}

deploy_name() {
	printf 'opensim-deploy-%s-%s' "$1" "$DEPLOY_RUN_ID"
}

deploy_load_platform() {
	local requested=$1 platform image expected_id expected_version
	DEPLOY_PLATFORM=
	while read -r platform image expected_id expected_version; do
		[[ -z "$platform" || "$platform" == \#* ]] && continue
		if [[ "$platform" == "$requested" ]]; then
			DEPLOY_PLATFORM=$platform
			DEPLOY_IMAGE=$image
			DEPLOY_EXPECTED_ID=$expected_id
			DEPLOY_EXPECTED_VERSION=$expected_version
			break
		fi
	done <"$DEPLOY_PLATFORMS_FILE"
	if [[ -z "$DEPLOY_PLATFORM" ]]; then
		printf 'Deploy platform not found in %s: %s\n' "$DEPLOY_PLATFORMS_FILE" "$requested" >&2
		return 1
	fi
}

deploy_skip_unless_running() {
	local platform=$1 name state
	name=$(deploy_name "$platform")
	if ! deploy_select_engine || ! deploy_command inspect "$name" >/dev/null 2>&1; then
		bashunit::skip "$platform not created"
		return 0
	fi
	state=$(deploy_command inspect --format '{{.State.Running}}' "$name" 2>/dev/null) || state=false
	if [[ "$state" != true ]]; then
		bashunit::skip "$platform not running"
		return 0
	fi
	return 1
}

deploy_test_gate() {
	local failure_file=${FAILURES_OUTPUT_PATH:-$DEPLOY_RUN_DIR/failures}
	bashunit::set_test_title "$DEPLOY_PLATFORM prerequisites passed"
	mkdir -p "$DEPLOY_RUN_DIR"
	if [[ -s "$failure_file" ]]; then
		: >"$DEPLOY_GATE_BLOCK_FILE"
		bashunit::skip 'local tests or package build failed'
		return
	fi
	if [[ -e "$DEPLOY_GATE_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests or package build failed'
		return
	fi
	assert_equals 0 0 'deployment gate is open'
}

deploy_run_step() {
	local step=$1 name status=0 actual
	name=$(deploy_name "$DEPLOY_PLATFORM")
	bashunit::set_test_title "$DEPLOY_PLATFORM $step"
	if [[ -e "$DEPLOY_GATE_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests or package build failed'
		return
	fi

	case "$step" in
		created)
			if ! deploy_select_engine; then status=127; else
				deploy_command create --name "$name" \
					--label org.opensim-cli.deploy=1 \
					--label "org.opensim-cli.deploy.platform=$DEPLOY_PLATFORM" \
					--label "org.opensim-cli.deploy.run=$DEPLOY_RUN_ID" \
					--memory="${MEMORY:-400m}" "$DEPLOY_IMAGE" sh -c 'while :; do sleep 3600; done' >/dev/null || status=$?
			fi
			assert_equals 0 "$status" "$DEPLOY_PLATFORM create"
			;;
		started)
			if ! deploy_select_engine || ! deploy_command inspect "$name" >/dev/null 2>&1; then
				bashunit::skip "$DEPLOY_PLATFORM not created"
				return
			fi
			deploy_command start "$name" >/dev/null || status=$?
			assert_equals 0 "$status" "$DEPLOY_PLATFORM start"
			;;
		running)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			actual=$(deploy_command inspect --format '{{.State.Running}}' "$name") || status=$?
			assert_equals true "$actual" "$DEPLOY_PLATFORM running"
			;;
		ready)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			deploy_command exec "$name" sh -c 'test -r /etc/os-release && test -x /bin/sh' >/dev/null || status=$?
			assert_equals 0 "$status" "$DEPLOY_PLATFORM shell ready"
			;;
		id)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			actual=$(deploy_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$ID"') || status=$?
			assert_equals "$DEPLOY_EXPECTED_ID" "$actual" "$DEPLOY_PLATFORM ID"
			;;
		version)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			actual=$(deploy_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$VERSION_ID"') || status=$?
			assert_equals "$DEPLOY_EXPECTED_VERSION" "$actual" "$DEPLOY_PLATFORM version"
			;;
	esac
}

deploy_cleanup_platform() {
	local platform=$1 name status=0
	name=$(deploy_name "$platform")
	bashunit::set_test_title "$platform cleanup"
	if [[ "${DEPLOY_KEEP:-0}" == 1 ]]; then
		bashunit::skip 'containers kept for inspection'
		return
	fi
	if ! deploy_select_engine || ! deploy_command inspect "$name" >/dev/null 2>&1; then
		bashunit::skip "$platform not created"
		return
	fi
	deploy_command rm --force "$name" >/dev/null || status=$?
	assert_equals 0 "$status" "$platform cleanup"
}
