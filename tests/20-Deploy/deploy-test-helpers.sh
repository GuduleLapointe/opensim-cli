#!/usr/bin/env bash

DEPLOY_PLATFORMS_FILE=${DEPLOY_PLATFORMS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platforms.tsv}
DEPLOY_PROJECT_ROOT=${DEPLOY_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
DEPLOY_RUN_DIR=${_BASHUNIT_RUN_OUTPUT_DIR:-${TMPDIR:-/tmp}/bashunit/deploy-$$}
DEPLOY_RUN_ID=${DEPLOY_RUN_ID:-${DEPLOY_RUN_DIR##*/}}
DEPLOY_HOST_SLUG=${DEPLOY_HOST_SLUG:-$(hostname -s 2>/dev/null || hostname)}
DEPLOY_USER_SLUG=${DEPLOY_USER_SLUG:-$(id -un 2>/dev/null || printf user)}
DEPLOY_EPHEMERAL=${DEPLOY_EPHEMERAL:-0}
DEPLOY_GATE_BLOCK_FILE=$DEPLOY_RUN_DIR/deployment-blocked
DEPLOY_GATE_READY_FILE=$DEPLOY_RUN_DIR/deployment-ready
DEPLOY_INFRA_BLOCK_FILE=$DEPLOY_RUN_DIR/deployment-infra-blocked
DEPLOY_PACKAGE_DIR=${DEPLOY_PACKAGE_DIR:-${_BASHUNIT_RUN_OUTPUT_DIR:-}/deploy-packages}
DEPLOY_VOLUME_NAME=${DEPLOY_VOLUME_NAME:-opensim-cli-test-packages}
DEPLOY_BUILDER_NAME=${DEPLOY_BUILDER_NAME:-opensim-cli-test-build}
DEPLOY_BUILDER_IMAGE=${DEPLOY_BUILDER_IMAGE:-docker.io/library/debian:12-slim}
DEPLOY_QUICK_INSTALL_TIMEOUT=${DEPLOY_QUICK_INSTALL_TIMEOUT:-900}
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
	local identity
	identity=$(deploy_slug "${DEPLOY_HOST_SLUG}-${DEPLOY_USER_SLUG}-$1")
	if [[ "$DEPLOY_EPHEMERAL" == 1 ]]; then identity+="-$(deploy_slug "$DEPLOY_RUN_ID")"; fi
	printf 'opensim-deploy-%s' "$identity"
}

deploy_slug() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'
}

deploy_log_dir() {
	printf '%s/tmp/deploy-logs/%s' "$DEPLOY_PROJECT_ROOT" "$(deploy_name "$1")"
}

deploy_volume_name() {
	printf '%s' "$DEPLOY_VOLUME_NAME"
}

deploy_builder_name() {
	printf '%s' "$DEPLOY_BUILDER_NAME"
}

deploy_platform_block_file() {
	printf '%s/%s-blocked' "$DEPLOY_RUN_DIR" "$1"
}

deploy_mark_platform_blocked() {
	mkdir -p "$DEPLOY_RUN_DIR"
	: >"$(deploy_platform_block_file "$1")"
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
	if [[ -e "$DEPLOY_GATE_BLOCK_FILE" || -e "$DEPLOY_INFRA_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests, build, or deployment setup failed'
		return
	fi
	if [[ ! -e "$DEPLOY_GATE_READY_FILE" && -s "$failure_file" ]]; then
		: >"$DEPLOY_GATE_BLOCK_FILE"
		bashunit::skip 'local tests or package build failed'
		return
	fi
	: >"$DEPLOY_GATE_READY_FILE"
	assert_equals 0 0 'deployment gate is open'
}

deploy_mark_infra_blocked() {
	mkdir -p "$DEPLOY_RUN_DIR"
	: >"$DEPLOY_INFRA_BLOCK_FILE"
}

deploy_builder_step() {
	local step=$1 builder volume status=0 running manifest remote_manifest index_stale=0
	builder=$(deploy_builder_name)
	volume=$(deploy_volume_name)
	bashunit::set_test_title "package builder $step"
	if [[ -e "$DEPLOY_GATE_BLOCK_FILE" ]]; then bashunit::skip 'local tests or package build failed'; return; fi
	if [[ -e "$DEPLOY_INFRA_BLOCK_FILE" ]]; then bashunit::skip 'shared deployment setup failed'; return; fi
	if ! deploy_select_engine; then status=127
	else
		case "$step" in
			volume)
				if ! deploy_command volume inspect "$volume" >/dev/null 2>&1; then deploy_command volume create "$volume" >/dev/null || status=$?; fi
				;;
			created)
				if ! deploy_command inspect "$builder" >/dev/null 2>&1; then
					deploy_command create --name "$builder" --label org.opensim-cli.deploy=builder --volume "$volume:/tmp/opensim-local-install" "$DEPLOY_BUILDER_IMAGE" sh -c 'while :; do sleep 3600; done' >/dev/null || status=$?
				fi
				;;
			started)
				if ! deploy_command inspect "$builder" >/dev/null 2>&1; then status=1
				else
					running=$(deploy_command inspect --format '{{.State.Running}}' "$builder") || status=$?
					if [[ "$running" != true ]] && ((status == 0)); then deploy_command start "$builder" >/dev/null || status=$?; fi
				fi
				;;
			ready)
				deploy_command exec "$builder" sh -c 'test -w /tmp/opensim-local-install && command -v apt-get >/dev/null && command -v tar >/dev/null && command -v gzip >/dev/null && command -v sha256sum >/dev/null' >/dev/null || status=$?
				;;
			scanner)
				if ! deploy_command exec "$builder" sh -c 'command -v dpkg-scanpackages >/dev/null'; then
					deploy_command exec "$builder" sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dpkg-dev' >/dev/null 2>&1 || status=$?
				fi
				;;
			synced)
				manifest=$DEPLOY_PACKAGE_DIR/MANIFEST
				if [[ ! -s "$manifest" || ! -s "$DEPLOY_PACKAGE_DIR/quick-install.sh" ]]; then status=1
				else
					remote_manifest=$(deploy_command exec "$builder" sh -c 'cat /tmp/opensim-local-install/MANIFEST 2>/dev/null' 2>/dev/null) || remote_manifest=
					if [[ "$remote_manifest" != "$(cat "$manifest")" ]]; then
						deploy_command exec "$builder" sh -c 'find /tmp/opensim-local-install -mindepth 1 -maxdepth 1 -exec rm -rf {} +' || status=$?
						if ((status == 0)); then COPYFILE_DISABLE=1 tar -chf - -C "$DEPLOY_PACKAGE_DIR" . | deploy_command exec -i "$builder" sh -c 'tar -xf - --no-same-owner -C /tmp/opensim-local-install' || status=$?; fi
						index_stale=1
					else
						deploy_command exec "$builder" sh -c 'cd /tmp/opensim-local-install/debs && { test -s Packages.gz && ! find . -maxdepth 1 -type f -name "*.deb" -newer Packages.gz -print -quit | grep -q .; }' >/dev/null 2>&1 || index_stale=1
					fi
					if ((status == 0 && index_stale == 1)); then deploy_command exec "$builder" sh -c 'cd /tmp/opensim-local-install/debs && dpkg-scanpackages . /dev/null | gzip -9c >Packages.gz' >/dev/null || status=$?; fi
					if ((status == 0)); then deploy_command exec "$builder" sh -c 'cd /tmp/opensim-local-install && sha256sum -c MANIFEST >/dev/null && cd debs && sha256sum -c SHA256SUMS >/dev/null' || status=$?; fi
				fi
				;;
		esac
	fi
	assert_equals 0 "$status" "package builder $step"
	if ((status != 0)); then deploy_mark_infra_blocked; fi
}

deploy_run_step() {
	local step=$1 name status=0 actual
	name=$(deploy_name "$DEPLOY_PLATFORM")
	bashunit::set_test_title "$DEPLOY_PLATFORM $step"
	if [[ -e "$DEPLOY_GATE_BLOCK_FILE" || -e "$DEPLOY_INFRA_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests, build, or shared deployment setup failed'
		return
	fi
	if [[ -e "$(deploy_platform_block_file "$DEPLOY_PLATFORM")" ]]; then
		bashunit::skip "$DEPLOY_PLATFORM prerequisite failed"
		return
	fi

	case "$step" in
		created)
			if ! deploy_select_engine; then status=127; else
				local volume
				local memory_args=()
				volume=$(deploy_volume_name)
				[[ -n "${MEMORY:-}" ]] && memory_args=(--memory "$MEMORY")
				if deploy_command inspect "$name" >/dev/null 2>&1; then
					status=0
				else deploy_command create --name "$name" \
					--label org.opensim-cli.deploy=1 \
					--label "org.opensim-cli.deploy.platform=$DEPLOY_PLATFORM" \
					--label "org.opensim-cli.deploy.host=$DEPLOY_HOST_SLUG" \
					--label "org.opensim-cli.deploy.user=$DEPLOY_USER_SLUG" \
					--label "org.opensim-cli.deploy.ephemeral=$DEPLOY_EPHEMERAL" \
					--label "org.opensim-cli.deploy.run=$DEPLOY_RUN_ID" \
					"${memory_args[@]}" \
					--volume "$volume:/tmp/opensim-local-install" \
					"$DEPLOY_IMAGE" sh -c 'while :; do sleep 3600; done' >/dev/null || status=$?
				fi
			fi
			assert_equals 0 "$status" "$DEPLOY_PLATFORM create"
			;;
		started)
			if ! deploy_select_engine || ! deploy_command inspect "$name" >/dev/null 2>&1; then
				bashunit::skip "$DEPLOY_PLATFORM not created"
				return
			fi
			local running
			running=$(deploy_command inspect --format '{{.State.Running}}' "$name") || status=$?
			if [[ "$running" != true ]] && ((status == 0)); then deploy_command start "$name" >/dev/null || status=$?; fi
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
			[[ "$actual" == "$DEPLOY_EXPECTED_ID" ]] || status=1
			assert_equals "$DEPLOY_EXPECTED_ID" "$actual" "$DEPLOY_PLATFORM ID"
			;;
		version)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			actual=$(deploy_command exec "$name" sh -c '. /etc/os-release; printf "%s" "$VERSION_ID"') || status=$?
			[[ "$actual" == "$DEPLOY_EXPECTED_VERSION" ]] || status=1
			assert_equals "$DEPLOY_EXPECTED_VERSION" "$actual" "$DEPLOY_PLATFORM version"
			;;
		synced)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			deploy_command exec "$name" sh -c 'test -s /tmp/opensim-local-install/MANIFEST && test -s /tmp/opensim-local-install/debs/Packages.gz && cd /tmp/opensim-local-install && sha256sum -c MANIFEST' >/dev/null || status=$?
			assert_equals 0 "$status" "$DEPLOY_PLATFORM package sync"
			;;
		installed)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			local log_dir log_file manifest_stamp installed_stamp
			log_dir=$(deploy_log_dir "$DEPLOY_PLATFORM")
			log_file=$log_dir/quick-install.log
			manifest_stamp=$(cksum <"$DEPLOY_PACKAGE_DIR/MANIFEST" | awk '{print $1 ":" $2}')
			installed_stamp=$(deploy_command exec "$name" sh -c 'cat /var/tmp/opensim-deploy-package-manifest 2>/dev/null' 2>/dev/null) || installed_stamp=
			if [[ "$DEPLOY_EPHEMERAL" != 1 && "$installed_stamp" == "$manifest_stamp" ]] && deploy_command exec "$name" sh -c 'command -v opensim >/dev/null && dpkg-query -W -f="${db:Status-Status}" opensim-cli 2>/dev/null | grep -qx installed'; then
				bashunit::skip "$DEPLOY_PLATFORM package set already installed"
				return
			fi
			mkdir -p "$log_dir" || status=$?
			if ((status == 0)); then deploy_command exec "$name" sh -c 'timeout --signal=TERM --kill-after=30s "'"${DEPLOY_QUICK_INSTALL_TIMEOUT}"'s" env DEBUG=yes OPENSIM_KIT_DEBS=/tmp/opensim-local-install/debs ASSUME_YES=yes /bin/bash /tmp/opensim-local-install/quick-install.sh --no-setup' >"$log_file" 2>&1 || status=$?; fi
			if ((status == 124)); then printf '%s quick-install timed out after %ss (log: %s)\n' "$DEPLOY_PLATFORM" "$DEPLOY_QUICK_INSTALL_TIMEOUT" "$log_file" >&2; fi
			if ((status != 0)); then
				printf 'Full quick-install log: %s\n' "$log_file" >&2
				tail -n 40 "$log_file" >&2 || true
			else deploy_command exec "$name" sh -c 'printf "%s\n" "$1" > /var/tmp/opensim-deploy-package-manifest' sh "$manifest_stamp" || status=$?
			fi
			assert_equals 0 "$status" "$DEPLOY_PLATFORM quick-install"
			;;
		packages)
			if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
			actual=$(deploy_command exec "$name" sh -c 'dpkg-query -W -f="${db:Status-Status}\\n" bash-tools opensim-cli opensim-engine opensim-helpers opensim-rest-php' 2>/dev/null) || status=$?
			if [[ "$actual" != $'installed\ninstalled\ninstalled\ninstalled\ninstalled' ]]; then status=1; fi
			assert_equals 0 "$status" "$DEPLOY_PLATFORM packages installed"
			;;
	esac
	if ((status != 0)); then deploy_mark_platform_blocked "$DEPLOY_PLATFORM"; fi
}

deploy_cleanup_platform() {
	local platform=$1 name status=0
	name=$(deploy_name "$platform")
	bashunit::set_test_title "$platform cleanup"
	if [[ "$DEPLOY_EPHEMERAL" != 1 ]]; then
		bashunit::skip 'persistent container retained'
		return
	fi
	if ! deploy_select_engine || ! deploy_command inspect "$name" >/dev/null 2>&1; then
		bashunit::skip "$platform not created"
		return
	fi
	deploy_command rm --force "$name" >/dev/null || status=$?
	assert_equals 0 "$status" "$platform cleanup"
}
