#!/usr/bin/env bash

# Bashunit loads tests/bootstrap.sh before the tests. Each platform runs as an
# independent, ordered test so a failure on one does not prevent the other.

COMPAT_RUN_ID=${_BASHUNIT_RUN_OUTPUT_DIR##*/}
[[ -n "$COMPAT_RUN_ID" ]] || COMPAT_RUN_ID="manual-$$"
COMPAT_ENGINE_SELECTED=
COMPAT_DETAIL_LOG=

compat_log() {
	COMPAT_DETAIL_LOG+="$1"$'\n'
}

compat_publish_log() {
	[[ -n "$COMPAT_DETAIL_LOG" ]] || return 0
	bashunit::console_results::print_line successful "${COMPAT_DETAIL_LOG%$'\n'}"
}

compat_select_engine() {
	local requested=${COMPAT_ENGINE:-auto}
	case "$requested" in
		auto)
			if command -v podman >/dev/null 2>&1; then
				COMPAT_ENGINE_SELECTED=podman
			elif command -v docker >/dev/null 2>&1; then
				COMPAT_ENGINE_SELECTED=docker
			else
				printf 'FAILED: neither Podman nor Docker is available on PATH.\n' >&2
				return 1
			fi
			;;
		podman|docker)
			if ! command -v "$requested" >/dev/null 2>&1; then
				printf 'FAILED: requested container engine %s is not available on PATH.\n' "$requested" >&2
				return 1
			fi
			COMPAT_ENGINE_SELECTED=$requested
			;;
		*)
			printf 'FAILED: COMPAT_ENGINE must be auto, podman, or docker (got %s).\n' "$requested" >&2
			return 2
			;;
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

compat_step_skip() {
	compat_log "SKIPPED [$1] $2: $3"
}

compat_assert_step() {
	local platform=$1 step=$2 status=$3 elapsed=${4:-0}
	if ((status == 0)); then
		compat_log "PASS    [$platform] $step (${elapsed}s)"
		return 0
	fi
	compat_log "FAILED  [$platform] $step (exit $status, ${elapsed}s)"
	assert_equals 0 "$status" "$platform: $step"
	return 1
}

compat_test_platform() {
	local platform=$1 image=$2 expected_id=$3 expected_version=$4
	local name status state os_release actual_id actual_version timeout attempt step_started
	local command_output
	COMPAT_DETAIL_LOG=
	name=$(compat_name "$platform")
	compat_log "=== Platform: $platform ==="
	compat_log "Container: $name"
	compat_log "Requested engine: ${COMPAT_ENGINE:-auto} (Podman preferred)"
	compat_log "Image: $image"
	if ! compat_select_engine; then
		compat_log 'FAILED: no usable container engine'
		assert_equals 0 1 "$platform: select Podman or Docker" || true
		compat_step_skip "$platform" 'create container' 'no usable engine'
		compat_step_skip "$platform" 'start container' 'container creation did not succeed'
		compat_step_skip "$platform" 'check running state' 'container start did not succeed'
		compat_step_skip "$platform" 'execute shell readiness check' 'container is not running'
		compat_step_skip "$platform" 'verify distribution release' 'readiness check did not succeed'
		compat_publish_log
		return
	fi
	compat_log "Selected engine: $COMPAT_ENGINE_SELECTED"
	timeout=${COMPAT_READY_TIMEOUT:-10}
	if [[ ! $timeout =~ ^[0-9]+$ ]] || ((timeout < 1)); then
		compat_log 'FAILED: COMPAT_READY_TIMEOUT must be a positive number of seconds'
		assert_equals 0 1 'COMPAT_READY_TIMEOUT must be a positive number of seconds' || true
		compat_step_skip "$platform" 'create container' 'invalid COMPAT_READY_TIMEOUT'
		compat_step_skip "$platform" 'start container' 'invalid COMPAT_READY_TIMEOUT'
		compat_step_skip "$platform" 'check running state' 'invalid COMPAT_READY_TIMEOUT'
		compat_step_skip "$platform" 'execute shell readiness check' 'invalid COMPAT_READY_TIMEOUT'
		compat_step_skip "$platform" 'verify distribution release' 'invalid COMPAT_READY_TIMEOUT'
		compat_publish_log
		return
	fi

	compat_log "\nSTEP 1/5: create $platform container"
	if compat_command inspect "$name" >/dev/null 2>&1; then
		compat_log "FAILED: container name already exists: $name"
		assert_equals 0 1 "$platform: create container (name already exists)" || true
		compat_step_skip "$platform" 'start container' 'creation step failed'
		compat_step_skip "$platform" 'check running state' 'creation step failed'
		compat_step_skip "$platform" 'execute shell readiness check' 'creation step failed'
		compat_step_skip "$platform" 'verify distribution release' 'creation step failed'
		compat_publish_log
		return
	fi
	compat_log "+ $COMPAT_ENGINE_SELECTED create --name $name --label org.opensim-cli.compatibility=1 --memory=${MEMORY:-400m} $image sh -c 'while :; do sleep 3600; done'"
	step_started=$SECONDS
	if command_output=$(compat_command create --name "$name" --label org.opensim-cli.compatibility=1 \
		--memory="${MEMORY:-400m}" "$image" sh -c 'while :; do sleep 3600; done' 2>&1); then
		status=0
	else
		status=$?
	fi
	compat_log "Create output: ${command_output:-<empty>}"
	if ! compat_assert_step "$platform" 'container created' "$status" "$((SECONDS - step_started))"; then
		compat_step_skip "$platform" 'start container' 'creation step failed'
		compat_step_skip "$platform" 'check running state' 'creation step failed'
		compat_step_skip "$platform" 'execute shell readiness check' 'creation step failed'
		compat_step_skip "$platform" 'verify distribution release' 'creation step failed'
		compat_publish_log
		return
	fi

	compat_log "\nSTEP 2/5: start $platform container"
	compat_log "+ $COMPAT_ENGINE_SELECTED start $name"
	step_started=$SECONDS
	if command_output=$(compat_command start "$name" 2>&1); then
		status=0
	else
		status=$?
	fi
	compat_log "Start output: ${command_output:-<empty>}"
	if ! compat_assert_step "$platform" 'container started' "$status" "$((SECONDS - step_started))"; then
		compat_step_skip "$platform" 'check running state' 'start step failed'
		compat_step_skip "$platform" 'execute shell readiness check' 'start step failed'
		compat_step_skip "$platform" 'verify distribution release' 'start step failed'
		compat_publish_log
		return
	fi

	compat_log "\nSTEP 3/5: verify $platform running state"
	step_started=$SECONDS
	if state=$(compat_command inspect --format '{{.State.Running}}' "$name" 2>&1); then
		status=0
	else
		status=$?
	fi
	compat_log "Container state: $state"
	if [[ "$state" != true ]]; then status=1; fi
	if ! compat_assert_step "$platform" 'container reports running' "$status" "$((SECONDS - step_started))"; then
		compat_step_skip "$platform" 'execute shell readiness check' 'container is not running'
		compat_step_skip "$platform" 'verify distribution release' 'container is not running'
		compat_publish_log
		return
	fi

	compat_log "\nSTEP 4/5: execute shell readiness check in $platform"
	step_started=$SECONDS
	status=1
	for ((attempt = 1; attempt <= timeout; attempt++)); do
		compat_log "Readiness attempt $attempt/$timeout: $COMPAT_ENGINE_SELECTED exec $name sh -c 'test -r /etc/os-release && test -x /bin/sh'"
		if command_output=$(compat_command exec "$name" sh -c 'test -r /etc/os-release && test -x /bin/sh' 2>&1); then
			status=0
			break
		fi
		if ((attempt < timeout)); then sleep 1; fi
	done
	compat_log "Readiness command output: ${command_output:-<empty>}"
	if ! compat_assert_step "$platform" 'shell command succeeds and /etc/os-release is readable' "$status" "$((SECONDS - step_started))"; then
		compat_step_skip "$platform" 'verify distribution release' 'readiness command failed'
		compat_publish_log
		return
	fi

	compat_log "\nSTEP 5/5: verify $platform distribution identity"
	step_started=$SECONDS
	if os_release=$(compat_command exec "$name" sh -c 'cat /etc/os-release' 2>&1); then
		status=0
	else
		status=$?
	fi
	actual_id=$(printf '%s\n' "$os_release" | sed -n 's/^ID="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p' | head -1)
	actual_version=$(printf '%s\n' "$os_release" | sed -n 's/^VERSION_ID="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p' | head -1)
	compat_log "Reported distribution: ID=${actual_id:-unknown} VERSION_ID=${actual_version:-unknown}"
	if [[ "$actual_id" != "$expected_id" || "$actual_version" != "$expected_version" ]]; then
		compat_log "$os_release"
		status=1
	fi
	compat_assert_step "$platform" "distribution is $expected_id $expected_version" "$status" "$((SECONDS - step_started))"
	compat_publish_log
}

function test_debian_12_platform() {
	compat_test_platform debian-12 docker.io/library/debian:12-slim debian 12
}

function test_ubuntu_24_04_platform() {
	compat_test_platform ubuntu-24.04 docker.io/library/ubuntu:24.04 ubuntu 24.04
}

function tear_down_after_script() {
	local platform name status overall_status=0
	for platform in debian-12 ubuntu-24.04; do
		name=$(compat_name "$platform")
		if compat_select_engine >/dev/null 2>&1 && compat_command inspect "$name" >/dev/null 2>&1; then
			bashunit::console_results::print_line successful "CLEANUP [$platform] removing $name"
			if compat_command rm --force "$name" >/dev/null 2>&1; then status=0; else status=$?; fi
			if ((status == 0)); then
				bashunit::console_results::print_line successful "PASS    [$platform] container removed"
			else
				bashunit::console_results::print_line failed "FAILED  [$platform] could not remove $name (exit $status)"
				overall_status=1
			fi
		fi
	done
	return "$overall_status"
}
