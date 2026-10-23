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
DEPLOY_APT_SUITE=${DEPLOY_APT_SUITE:-stable}
DEPLOY_QUICK_INSTALL_TIMEOUT=${DEPLOY_QUICK_INSTALL_TIMEOUT:-900}
DEPLOY_INSTALL_MODE=${DEPLOY_INSTALL_MODE:-separate}
DEPLOY_ENGINE_SELECTED=
DEPLOY_PLATFORM=
DEPLOY_IMAGE=
DEPLOY_NAME_BASE=opensim-deploy
DEPLOY_EXPECTED_ID=
DEPLOY_EXPECTED_VERSION=

deploy_select_engine() {
	case "${DEPLOY_ENGINE:-auto}" in
	auto) if command -v podman >/dev/null 2>&1; then DEPLOY_ENGINE_SELECTED=podman; elif command -v docker >/dev/null 2>&1; then DEPLOY_ENGINE_SELECTED=docker; else return 1; fi ;;
	podman | docker)
		command -v "$DEPLOY_ENGINE" >/dev/null 2>&1 || return 1
		DEPLOY_ENGINE_SELECTED=$DEPLOY_ENGINE
		;;
	*) return 1 ;;
	esac
}

deploy_command() {
	if [[ -z "$DEPLOY_ENGINE_SELECTED" ]]; then deploy_select_engine || return 127; fi
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
	printf '%s-%s' "$DEPLOY_NAME_BASE" "$identity"
}

deploy_slug() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'
}

deploy_log_dir() {
	printf '%s/tmp/deploy-logs/%s' "$DEPLOY_PROJECT_ROOT" "$(deploy_name "$1")"
}

deploy_execution_location() {
	deploy_select_engine >/dev/null 2>&1 || true
	if [[ "$DEPLOY_ENGINE_SELECTED" == podman && -n "${CONTAINER_CONNECTION:-}" ]]; then
		printf '%s' "$CONTAINER_CONNECTION"
	else
		printf 'local %s' "${DEPLOY_ENGINE_SELECTED:-container engine}"
	fi
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

deploy_installation_is_current() {
	local name=$1
	deploy_command exec "$name" sh -c '
		command -v opensim >/dev/null &&
		dpkg-query -W -f="\${db:Status-Status}" opensim 2>/dev/null | grep -qx installed &&
		dpkg-query -W -f="\${db:Status-Status}" opensim-cli 2>/dev/null | grep -qx installed &&
		dotnet --list-runtimes 2>/dev/null | grep -Eq "Microsoft\\.NETCore\\.App [8-9][.]|Microsoft\\.NETCore\\.App [1-9][0-9]+[.]" &&
		mysqladmin ping --silent
	' >/dev/null 2>&1
}

deploy_ensure_image() {
	local image=$1 log_file=$2 status=0
	if ! deploy_select_engine; then return 127; fi
	mkdir -p "$(dirname "$log_file")" || return $?
	if ! deploy_command image inspect "$image" >/dev/null 2>&1; then
		deploy_command pull "$image" >"$log_file" 2>&1 || status=$?
	else
		printf 'Image already present: %s\n' "$image" >"$log_file"
	fi
	if ((status != 0)); then
		printf 'Could not prepare container image %s (log: %s)\n' "$image" "$log_file" >&2
		tail -n 40 "$log_file" >&2 || true
	fi
	return "$status"
}

deploy_test_gate() {
	local failure_file=${FAILURES_OUTPUT_PATH:-$DEPLOY_RUN_DIR/failures}
	bashunit::set_test_title "$DEPLOY_PLATFORM local tests and package set are ready"
	mkdir -p "$DEPLOY_RUN_DIR"
	if [[ "$DEPLOY_INSTALL_MODE" != separate && "$DEPLOY_INSTALL_MODE" != single ]]; then
		deploy_mark_infra_blocked
		assert_equals 'separate or single' "$DEPLOY_INSTALL_MODE" 'DEPLOY_INSTALL_MODE'
		return
	fi
	if [[ -e "$DEPLOY_GATE_BLOCK_FILE" || -e "$DEPLOY_INFRA_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests, build, or deployment setup failed'
		return
	fi
	if [[ ! -e "$DEPLOY_GATE_READY_FILE" && -s "$failure_file" ]]; then
		: >"$DEPLOY_GATE_BLOCK_FILE"
		bashunit::skip 'local tests or package build failed'
		return
	fi
	if [[ ! -s "$DEPLOY_PACKAGE_DIR/MANIFEST" ]]; then
		local build_script artifact_dir
		build_script=$DEPLOY_PROJECT_ROOT/tests/10-Build/build-packages.sh
		artifact_dir=${_BASHUNIT_RUN_OUTPUT_DIR:?}/build-artifacts
		assert_exec "bash $(printf %q "$build_script") $(printf %q "$DEPLOY_PACKAGE_DIR") $(printf %q "$artifact_dir")" \
			'local package build and staging should succeed'
	fi
	assert_exec "test -s $(printf %q "$DEPLOY_PACKAGE_DIR/MANIFEST") && test -s $(printf %q "$DEPLOY_PACKAGE_DIR/debs/SHA256SUMS") && test \$(find $(printf %q "$DEPLOY_PACKAGE_DIR/debs") -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ') -eq 5" \
		'five locally built packages and their manifests should be available'
	if [[ ! -s "$DEPLOY_PACKAGE_DIR/MANIFEST" || ! -s "$DEPLOY_PACKAGE_DIR/debs/SHA256SUMS" || ! -s "$DEPLOY_PACKAGE_DIR/quick-install.sh" ]] ||
		[[ $(find "$DEPLOY_PACKAGE_DIR/debs" -maxdepth 1 -type f -name '*.deb' 2>/dev/null | wc -l | tr -d ' ') != 5 ]]; then
		: >"$DEPLOY_GATE_BLOCK_FILE"
		return
	fi
	: >"$DEPLOY_GATE_READY_FILE"
	assert_exec "cd $(printf %q "$DEPLOY_PACKAGE_DIR") && shasum -a 256 -c MANIFEST >/dev/null && cd debs && shasum -a 256 -c SHA256SUMS >/dev/null" \
		'local package checksums should match their manifests'
	if ! (cd "$DEPLOY_PACKAGE_DIR" && shasum -a 256 -c MANIFEST >/dev/null && cd debs && shasum -a 256 -c SHA256SUMS >/dev/null); then
		: >"$DEPLOY_GATE_BLOCK_FILE"
	fi
}

deploy_mark_infra_blocked() {
	mkdir -p "$DEPLOY_RUN_DIR"
	: >"$DEPLOY_INFRA_BLOCK_FILE"
}

deploy_run_step() {
	local step=$1 name status=0 actual location command
	name=$(deploy_name "$DEPLOY_PLATFORM")
	location=$(deploy_execution_location)
	case "$step" in
	image) bashunit::set_test_title "$DEPLOY_PLATFORM container image is available" ;;
	created) bashunit::set_test_title "$DEPLOY_PLATFORM container is created on $location" ;;
	started) bashunit::set_test_title "$DEPLOY_PLATFORM container start succeeds" ;;
	running) bashunit::set_test_title "$DEPLOY_PLATFORM container reports running" ;;
	ready) bashunit::set_test_title "$DEPLOY_PLATFORM container is ready" ;;
	id) bashunit::set_test_title "$DEPLOY_PLATFORM container OS ID is $DEPLOY_EXPECTED_ID" ;;
	version) bashunit::set_test_title "$DEPLOY_PLATFORM container OS version is $DEPLOY_EXPECTED_VERSION" ;;
	dependencies) bashunit::set_test_title "$DEPLOY_PLATFORM quick-install dependencies succeed" ;;
	apt_source) bashunit::set_test_title "$DEPLOY_PLATFORM OpenSim APT suite is $DEPLOY_APT_SUITE" ;;
	mariadb) bashunit::set_test_title "$DEPLOY_PLATFORM SQL server is available" ;;
	accounts) bashunit::set_test_title "$DEPLOY_PLATFORM SQL accounts are created" ;;
	credentials) bashunit::set_test_title "$DEPLOY_PLATFORM SQL credentials are saved" ;;
	dotnet) bashunit::set_test_title "$DEPLOY_PLATFORM .NET runtime is available" ;;
	opensim) bashunit::set_test_title "$DEPLOY_PLATFORM OpenSim packages are installed" ;;
	packages) bashunit::set_test_title "$DEPLOY_PLATFORM installed packages are complete" ;;
	setup_credentials) bashunit::set_test_title "$DEPLOY_PLATFORM setup reads saved or interactive credentials" ;;
	*) bashunit::set_test_title "$DEPLOY_PLATFORM $step" ;;
	esac
	if [[ -e "$DEPLOY_GATE_BLOCK_FILE" || -e "$DEPLOY_INFRA_BLOCK_FILE" ]]; then
		bashunit::skip 'local tests, build, or shared deployment setup failed'
		return
	fi
	if [[ -e "$(deploy_platform_block_file "$DEPLOY_PLATFORM")" ]]; then
		bashunit::skip "$DEPLOY_PLATFORM prerequisite failed"
		return
	fi

	case "$step" in
	apt_source)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		local failures_before failures_after source
		if [[ "$DEPLOY_APT_SUITE" == tests ]]; then
			source='deb [trusted=yes] https://apt.magiiic.com tests main'
		else
			source="deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com $DEPLOY_APT_SUITE main"
		fi
		printf -v command 'deploy_command exec %q grep -Fx %q /etc/apt/sources.list.d/magiiic.list' \
			"$name" "$source"
		failures_before=$(bashunit::state::get_assertions_failed)
		assert_exec "$command"
		failures_after=$(bashunit::state::get_assertions_failed)
		if ((failures_after > failures_before)); then deploy_mark_platform_blocked "$DEPLOY_PLATFORM"; fi
		return
		;;
	image)
		local image_log image_command
		image_log=$(deploy_log_dir "$DEPLOY_PLATFORM")/image.log
		printf -v image_command 'deploy_ensure_image %q %q' "$DEPLOY_IMAGE" "$image_log"
		assert_exec "$image_command"
		return
		;;
	created)
		if ! deploy_select_engine; then status=127; else
			local memory_args=()
			[[ -n "${MEMORY:-}" ]] && memory_args=(--memory "$MEMORY")
			if deploy_command inspect "$name" >/dev/null 2>&1; then
				printf -v command 'deploy_command inspect %q' "$name"
			else
				local create_args=(deploy_command create --name "$name"
					--label org.opensim-cli.deploy=1
					--label "org.opensim-cli.deploy.platform=$DEPLOY_PLATFORM"
					--label "org.opensim-cli.deploy.host=$DEPLOY_HOST_SLUG"
					--label "org.opensim-cli.deploy.user=$DEPLOY_USER_SLUG"
				--label "org.opensim-cli.deploy.ephemeral=$DEPLOY_EPHEMERAL"
				--label "org.opensim-cli.deploy.run=$DEPLOY_RUN_ID")
				create_args+=("${memory_args[@]}" "$DEPLOY_IMAGE" sh -c 'while :; do sleep 3600; done')
				printf -v command '%q ' "${create_args[@]}"
			fi
			assert_exec "$command"
			return
		fi
		assert_equals 0 "$status" "$DEPLOY_PLATFORM container creation"
		;;
	started)
		if ! deploy_select_engine || ! deploy_command inspect "$name" >/dev/null 2>&1; then
			bashunit::skip "$DEPLOY_PLATFORM container has not been created"
			return
		fi
		local start_command
		printf -v start_command 'if [[ $(deploy_command inspect --format %q %q) != true ]]; then deploy_command start %q; fi' \
			'{{.State.Running}}' "$name" "$name"
		assert_exec "$start_command"
		return
		;;
	running)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		local running_command
		printf -v running_command 'deploy_command inspect --format %q %q' '{{.State.Running}}' "$name"
		assert_exec "$running_command" --stdout true
		return
		;;
	ready)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		local ready_command
		printf -v ready_command 'deploy_command exec %q sh -c %q' "$name" 'test -r /etc/os-release && test -x /bin/sh && command -v tar >/dev/null'
		assert_exec "$ready_command"
		if ! deploy_command exec "$name" sh -c 'test -r /etc/os-release && test -x /bin/sh && command -v tar >/dev/null'; then deploy_mark_platform_blocked "$DEPLOY_PLATFORM"; fi
		return
		;;
	id)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		local id_command id_check
		id_check=' . /etc/os-release; if [ "${ID:-}" != "$1" ]; then printf "OS_RELEASE_MISMATCH expected ID=%s, got ID=%s\n" "$1" "${ID:-missing}" >&2; exit 1; fi'
		printf -v id_command 'deploy_command exec %q sh -c %q sh %q 2>&1' "$name" "$id_check" "$DEPLOY_EXPECTED_ID"
		assert_exec "$id_command" --stdout-not-contains OS_RELEASE_MISMATCH
		if ! deploy_command exec "$name" sh -c "$id_check" sh "$DEPLOY_EXPECTED_ID" >/dev/null 2>&1; then deploy_mark_platform_blocked "$DEPLOY_PLATFORM"; fi
		return
		;;
	version)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		local version_command version_check
		version_check=' . /etc/os-release; if [ "${ID:-}" != "$1" ] || [ "${VERSION_ID:-}" != "$2" ]; then printf "OS_RELEASE_MISMATCH expected ID=%s VERSION_ID=%s, got ID=%s VERSION_ID=%s\n" "$1" "$2" "${ID:-missing}" "${VERSION_ID:-missing}" >&2; exit 1; fi'
		printf -v version_command 'deploy_command exec %q sh -c %q sh %q %q 2>&1' "$name" "$version_check" "$DEPLOY_EXPECTED_ID" "$DEPLOY_EXPECTED_VERSION"
		assert_exec "$version_command" --stdout-not-contains OS_RELEASE_MISMATCH
		if ! deploy_command exec "$name" sh -c "$version_check" sh "$DEPLOY_EXPECTED_ID" "$DEPLOY_EXPECTED_VERSION" >/dev/null 2>&1; then deploy_mark_platform_blocked "$DEPLOY_PLATFORM"; fi
		return
		;;
	dependencies | mariadb | dotnet | opensim)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		local log_dir log_file manifest_stamp installed_stamp container_log install_step option execute_install=1
		install_step=$step
		if [[ "$DEPLOY_INSTALL_MODE" == single ]]; then
			case "$step" in
			dependencies) install_step=single-pass-install; option= ;;
			mariadb) install_step=sql-server-verification; execute_install=0 ;;
			dotnet) install_step=dotnet-verification; execute_install=0 ;;
			opensim) install_step=opensim-verification; execute_install=0 ;;
			esac
		else
			case "$step" in
			dependencies) option=--dependencies ;;
			mariadb) option=--mariadb ;;
			dotnet) option=--dotnet ;;
			opensim) option=--opensim ;;
			esac
		fi
		log_dir=$(deploy_log_dir "$DEPLOY_PLATFORM")
		log_file=$log_dir/$install_step.log
		bashunit::set_test_title "$DEPLOY_PLATFORM $install_step"
		manifest_stamp=
		installed_stamp=
		if [[ "$execute_install" == 1 ]]; then
			manifest_stamp="$DEPLOY_APT_SUITE:$(cksum <"$DEPLOY_PACKAGE_DIR/MANIFEST" | awk '{print $1 ":" $2}')"
			installed_stamp=$(deploy_command exec "$name" sh -c 'cat /var/tmp/opensim-deploy-package-manifest 2>/dev/null' 2>/dev/null) || installed_stamp=
		fi
		if [[ "$execute_install" == 1 && "$DEPLOY_EPHEMERAL" != 1 && "$installed_stamp" == "$manifest_stamp" ]] && [[ "$step" == opensim || ( "$DEPLOY_INSTALL_MODE" == single && "$step" == dependencies ) ]] && deploy_installation_is_current "$name"; then
			bashunit::skip "$DEPLOY_PLATFORM package set already installed"
			return
		fi
		mkdir -p "$log_dir" || status=$?
		if [[ "$execute_install" == 1 ]] && ((status == 0)); then
			container_log="/tmp/$name/$install_step.log"
			deploy_command exec -i "$name" sh -c 'cat > /tmp/quick-install.sh && chmod +x /tmp/quick-install.sh' <"$DEPLOY_PACKAGE_DIR/quick-install.sh" || status=$?
			if ((status == 0)); then
				deploy_command exec "$name" bash -c '
					set -o pipefail
					log_file=$1
					mkdir -p "$(dirname "$log_file")"
					if [[ -n "$4" ]]; then
						timeout --signal=TERM --kill-after=30s "${2}s" env DEBUG=yes OPENSIM_KIT_APT_SUITE="$3" ASSUME_YES=yes /bin/bash /tmp/quick-install.sh "$4" 2>&1 | tee "$log_file"
					else
						timeout --signal=TERM --kill-after=30s "${2}s" env DEBUG=yes OPENSIM_KIT_APT_SUITE="$3" ASSUME_YES=yes /bin/bash /tmp/quick-install.sh 2>&1 | tee "$log_file"
					fi
				' bash "$container_log" "$DEPLOY_QUICK_INSTALL_TIMEOUT" "$DEPLOY_APT_SUITE" "$option" >"$log_file" 2>&1 || status=$?
			fi
		fi
		if [[ "$execute_install" == 0 && "$status" == 0 ]]; then
			case "$step" in
			mariadb)
				deploy_command exec "$name" sh -c 'mysqladmin ping --silent' >"$log_file" 2>&1 || status=$?
				;;
			dotnet)
				deploy_command exec "$name" sh -c 'dotnet --list-runtimes 2>/dev/null | grep -Eq "Microsoft\\.NETCore\\.App [8-9][.]|Microsoft\\.NETCore\\.App [1-9][0-9]+[.]"' >"$log_file" 2>&1 || status=$?
				;;
			opensim)
				deploy_command exec "$name" sh -c 'command -v opensim >/dev/null && test "$(dpkg-query -W -f="\${db:Status-Status}\n" opensim opensim-cli 2>/dev/null | grep -c "^installed$")" -eq 2' >"$log_file" 2>&1 || status=$?
				;;
			esac
		fi
		if ((status == 124)); then printf '%s quick-install timed out after %ss (log: %s)\n' "$DEPLOY_PLATFORM" "$DEPLOY_QUICK_INSTALL_TIMEOUT" "$log_file" >&2; fi
		if ((status != 0)); then
			printf 'Full quick-install log: %s\n' "$log_file" >&2
			tail -n 40 "$log_file" >&2 || true
		elif [[ "$step" == opensim || ( "$DEPLOY_INSTALL_MODE" == single && "$step" == dependencies ) ]]; then
			deploy_command exec "$name" sh -c 'printf "%s\n" "$1" > /var/tmp/opensim-deploy-package-manifest' sh "$manifest_stamp" || status=$?
		fi
		if [[ "$execute_install" == 1 ]]; then
			assert_equals 0 "$status" "$DEPLOY_PLATFORM $install_step step"
		else
			assert_equals 0 "$status" "$DEPLOY_PLATFORM $install_step passed"
		fi
		;;
	accounts)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		printf -v command 'deploy_command exec %q sh -c %q' "$name" 'mysql -Nse "SELECT COUNT(*) FROM mysql.user WHERE User IN (0x6f70656e73696d5f61646d696e,0x6f70656e73696d) AND Host=0x6c6f63616c686f7374"'
		assert_exec "$command" --stdout 2
		;;
	credentials)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		printf -v command 'deploy_command exec %q sh -c %q' "$name" 'count=$(grep -Ec "^export OPENSIM_DB_(HOST|ADMIN_USER|ADMIN_PASS|USER|PASS)=" /root/.opensimrc); printf "saved database setting count: %s\n" "$count"; test "$count" -eq 5'
		assert_exec "$command" --stdout-contains 'saved database setting count: 5'
		;;
	packages)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		printf -v command 'deploy_command exec %q sh -c %q' "$name" 'dpkg-query -W -f="\${db:Status-Status}\n" bash-tools opensim opensim-cli opensim-engine opensim-helpers opensim-rest-php | grep -Ec "^installed$"'
		assert_exec "$command" --stdout 6
		;;
	setup_credentials)
		if deploy_skip_unless_running "$DEPLOY_PLATFORM"; then return; fi
		deploy_command exec -i "$name" bash -s <<-'SETUP_CREDENTIALS_TEST' || status=$?
			set -euo pipefail
			work=$(mktemp -d)
			trap 'rm -rf "$work"' EXIT
			engine="$work/engine"
			mkdir -p "$engine/bin" "$engine/lib"
			cp /usr/share/opensim-cli/vendor/magicoli/opensim-engine/lib/rc-helpers "$engine/lib/rc-helpers"
			cat <<'MOCK_API' >"$engine/bin/opensim-api"
			#!/usr/bin/env bash
			cat >>"$MOCK_REQUESTS"
			if [[ $(wc -l <"$MOCK_REQUESTS") -eq 1 ]]; then
				cat <<'DATABASE_FORM'
			{"data":{"attributes":{"action":"screen","kind":"form","title":"Database","text":"","notice":"","fields":[{"name":"admin_user","label":"Administrator","value":"","secret":false},{"name":"admin_password","label":"Administrator password","value":"","secret":true}],"buttons":{"next":"OK","back":"Back"},"state":"database-state"}}}
			DATABASE_FORM
			else
				cat <<'DONE'
			{"data":{"attributes":{"action":"quit","message":"Done."}}}
			DONE
			fi
			MOCK_API
			chmod +x "$engine/bin/opensim-api"
			run_setup() {
				local home=$1 answers=$2
				: >"$work/requests"
				printf '%s\n' "$answers" >"$work/answers"
				(
					exec 3<"$work/answers"
					unset OPENSIM_RC OPENSIM_DB_ADMIN_USER OPENSIM_DB_ADMIN_PASS
					export HOME="$home" OPENSIM_API="$engine/bin/opensim-api"
					export MOCK_REQUESTS="$work/requests" OPENSIM_SETUP_UI=plain FE_INPUT_FD=3 FE_TTY=/dev/null
					/usr/share/opensim-cli/libexec/setup
				)
			}
			run_setup /root '' >"$work/saved-output" 2>&1
			[[ -r /root/.opensimrc ]]
			expected_user=$(bash -c 'source /root/.opensimrc; printf "%s" "$OPENSIM_DB_ADMIN_USER"')
			expected_pass=$(bash -c 'source /root/.opensimrc; printf "%s" "$OPENSIM_DB_ADMIN_PASS"')
			request=$(tail -n 1 "$work/requests")
			jq -e --arg user "$expected_user" --arg pass "$expected_pass" \
				'.data.attributes.answers.admin_user == $user and .data.attributes.answers.admin_password == $pass' <<<"$request" >/dev/null
			! grep -Fq "$expected_pass" "$work/saved-output"
			mkdir -p "$work/empty-home"
			run_setup "$work/empty-home" $'1\nmanual-admin\n2\ninteractive-secret\n' >"$work/manual-output" 2>&1
			request=$(tail -n 1 "$work/requests")
			jq -e '.data.attributes.answers.admin_user == "manual-admin" and .data.attributes.answers.admin_password == "interactive-secret"' <<<"$request" >/dev/null
			! grep -Fq 'interactive-secret' "$work/manual-output"
		SETUP_CREDENTIALS_TEST
		assert_equals 0 "$status" "$DEPLOY_PLATFORM setup reads saved or interactive SQL credentials"
		;;
	esac
	if ((status != 0)); then deploy_mark_platform_blocked "$DEPLOY_PLATFORM"; fi
}

deploy_cleanup_platform() {
	local platform=$1 name
	name=$(deploy_name "$platform")
	[[ "$DEPLOY_EPHEMERAL" == 1 ]] || return 0
	deploy_select_engine || return 1
	deploy_command inspect "$name" >/dev/null 2>&1 || return 0
	deploy_command rm --force "$name" >/dev/null
}
