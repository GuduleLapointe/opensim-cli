#!/usr/bin/env bash

DEPLOY_PLATFORMS_FILE=${DEPLOY_PLATFORMS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platforms.tsv}
DEPLOY_PROJECT_ROOT=${DEPLOY_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
DEPLOY_CONTAINER_CLI=${DEPLOY_CONTAINER_CLI:-$DEPLOY_PROJECT_ROOT/vendor/bin/container-tools}
DEPLOY_RUN_DIR=${_BASHUNIT_RUN_OUTPUT_DIR:-${TMPDIR:-/tmp}/bashunit/deploy-$$}
DEPLOY_RUN_ID=${DEPLOY_RUN_ID:-${DEPLOY_RUN_DIR##*/}}
DEPLOY_HOST_SLUG=${DEPLOY_HOST_SLUG:-$(hostname -s 2>/dev/null || hostname)}
DEPLOY_USER_SLUG=${DEPLOY_USER_SLUG:-$(id -un 2>/dev/null || printf user)}
DEPLOY_EPHEMERAL=${DEPLOY_EPHEMERAL:-0}
if [[ ${__DEPLOY_PLATFORM_FILTER_INITIALIZED:-} != 1 ]]; then
	DEPLOY_PLATFORM_FILTER=${DEPLOY_PLATFORM_FILTER:-${DEPLOY_PLATFORM:-}}
	__DEPLOY_PLATFORM_FILTER_INITIALIZED=1
fi
DEPLOY_INFRA_BLOCK_FILE=$DEPLOY_RUN_DIR/deployment-infra-blocked
DEPLOY_APT_DIST=charm-tests
DEPLOY_APT_COMPONENT=dev
DEPLOY_QUICK_INSTALL_TIMEOUT=${DEPLOY_QUICK_INSTALL_TIMEOUT:-900}
DEPLOY_INSTALL_MODE=${DEPLOY_INSTALL_MODE:-separate}
DEPLOY_ENGINE_SELECTED=
DEPLOY_PLATFORM=
DEPLOY_IMAGE=
DEPLOY_NAME_BASE=opensim-deploy
DEPLOY_EXPECTED_ID=
DEPLOY_EXPECTED_VERSION=

deploy_select_engine() {
	[[ "${DEPLOY_ENGINE:-podman}" == podman || "${DEPLOY_ENGINE:-podman}" == auto ]] || return 1
	command -v php >/dev/null 2>&1 || return 1
	[[ -x "$DEPLOY_CONTAINER_CLI" ]] || return 1
	DEPLOY_ENGINE_SELECTED=podman
}

deploy_command() {
	deploy_select_engine || return 127
	local connection_args=()
	[[ -n "${CONTAINER_CONNECTION:-}" ]] && connection_args=(--connection "$CONTAINER_CONNECTION")
	"$DEPLOY_CONTAINER_CLI" "${connection_args[@]}" "$@"
}

deploy_copy_file() {
	local name=$1 source=$2 destination=$3
	deploy_command cp "$source" "$name:$destination"
}

deploy_run_script() {
	local name=$1 source=$2 destination
	shift 2
	destination="/tmp/$(basename "$source")"
	deploy_copy_file "$name" "$source" "$destination" || return $?
	deploy_command exec "$name" -- bash "$destination" "$@"
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
	if [[ -n "${CONTAINER_CONNECTION:-}" ]]; then
		printf '%s' "$CONTAINER_CONNECTION"
	else
		printf 'local Podman'
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
	if [[ -n "$DEPLOY_PLATFORM_FILTER" && "$requested" != "$DEPLOY_PLATFORM_FILTER" ]]; then
		return 1
	fi
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

assert_deployment_container_running() {
	local platform=$1 name status_command
	name=$(deploy_name "$platform")
	printf -v status_command 'deploy_command status %q 2>&1' "$name"
	deploy_assert_exec "$status_command" --stdout-contains 'Status: running'
}

deploy_installation_is_current() {
	local name=$1
	deploy_command exec "$name" -- sh -c '
		command -v opensim >/dev/null &&
		dpkg-query -W -f="\${db:Status-Status}" opensim 2>/dev/null | grep -qx installed &&
		dpkg-query -W -f="\${db:Status-Status}" opensim-cli 2>/dev/null | grep -qx installed &&
		dotnet --list-runtimes 2>/dev/null | grep -Eq "Microsoft\\.NETCore\\.App [8-9][.]|Microsoft\\.NETCore\\.App [1-9][0-9]+[.]" &&
		mysqladmin ping --silent
	' >/dev/null 2>&1
}

deploy_ensure_image() {
	local image=$1 log_file=$2 status=0
	if ! deploy_select_engine; then
		printf 'Container-tools is unavailable\n'
		return 127
	fi
	mkdir -p "$(dirname "$log_file")" || return $?
	deploy_command image-pull "$image" >"$log_file" 2>&1 || status=$?
	if ((status != 0)); then
		printf 'Image pull failed: %s\n' "$image"
		tail -n 12 "$log_file"
	else
		printf 'Image available: %s\n' "$image"
	fi
	return "$status"
}

deploy_assert_exec() {
	local failures_before failures_after
	failures_before=$(bashunit::state::get_assertions_failed)
	if (($# == 1)); then
		local command=$1 log_file wrapped_command
		log_file="$DEPLOY_RUN_DIR/$DEPLOY_PLATFORM-command.log"
		printf -v wrapped_command 'deploy_capture_command %q %q' "$log_file" "$command"
		assert_exec "$wrapped_command" --stdout-contains 'DEPLOY_COMMAND_OK'
	else
		assert_exec "$@"
	fi
	failures_after=$(bashunit::state::get_assertions_failed)
	if ((failures_after > failures_before)); then
		deploy_mark_platform_blocked "$DEPLOY_PLATFORM"
		return 1
	fi
	return 0
}

deploy_capture_command() {
	local log_file=$1 command=$2 status=0
	eval "$command" >"$log_file" 2>&1 || status=$?
	if ((status == 0)); then
		cat "$log_file"
		printf 'DEPLOY_COMMAND_OK\n'
	else
		printf 'Command failed (exit %s)\n' "$status"
		tail -n 12 "$log_file"
	fi
	return "$status"
}

deploy_install_check() {
	local name=$1 step=$2 log_file=$3 command label status=0
	case "$step" in
		mariadb)
			command='mysqladmin ping --silent'
			label='MariaDB responds'
			;;
		dotnet)
			command='dotnet --list-runtimes 2>/dev/null | grep -Eq "Microsoft\\.NETCore\\.App [8-9][.]|Microsoft\\.NETCore\\.App [1-9][0-9]+[.]"'
			label='.NET runtime is installed'
			;;
		opensim)
			command='command -v opensim >/dev/null && test "$(dpkg-query -W -f="\${db:Status-Status}\\n" opensim opensim-cli 2>/dev/null | grep -c "^installed$")" -eq 2'
			label='OpenSim packages are installed'
			;;
	esac
	deploy_command exec "$name" -- sh -c "$command" >"$log_file" 2>&1 || status=$?
	if ((status == 0)); then
		printf '%s\n' "$label"
	else
		printf '%s check failed (exit %s)\n' "$label" "$status"
		tail -n 12 "$log_file"
	fi
	return "$status"
}

deploy_create_container() {
	local log_file=$1
	shift
	local status=0
	"$@" >"$log_file" 2>&1 || status=$?
	if ((status == 0)); then
		printf 'Container created\n'
	else
		printf 'Container creation failed (exit %s)\n' "$status"
		tail -n 12 "$log_file"
	fi
	return "$status"
}

deploy_install_step() {
	local name=$1 log_file=$2 container_log=$3 option=$4 step=$5 timeout=$6 dist=$7 component=$8
	local status=0
	if ! mkdir -p "$(dirname "$log_file")"; then
		printf 'Cannot create install log directory: %s\n' "$(dirname "$log_file")"
		return 1
	fi
	if ! deploy_copy_file "$name" "$DEPLOY_PROJECT_ROOT/quick-install.sh" /tmp/quick-install.sh; then
		printf 'Could not copy quick-install.sh to %s\n' "$name"
		return 1
	fi
	deploy_command exec "$name" -- bash -c '
		set -o pipefail
		log_file=$1
		mkdir -p "$(dirname "$log_file")"
		if [[ -n "$5" ]]; then
			timeout --signal=TERM --kill-after=30s "${2}s" env DEBUG=yes OPENSIM_KIT_APT_DIST="$3" OPENSIM_KIT_APT_COMPONENT="$4" ASSUME_YES=yes /bin/bash /tmp/quick-install.sh "$5" 2>&1 | tee "$log_file"
		else
			timeout --signal=TERM --kill-after=30s "${2}s" env DEBUG=yes OPENSIM_KIT_APT_DIST="$3" OPENSIM_KIT_APT_COMPONENT="$4" ASSUME_YES=yes /bin/bash /tmp/quick-install.sh 2>&1 | tee "$log_file"
		fi
	' bash "$container_log" "$timeout" "$dist" "$component" "$option" >"$log_file" 2>&1 || status=$?
	if ((status == 0)); then
		printf 'quick-install %s completed\n' "$step"
	else
		if ((status == 124)); then
			printf 'quick-install %s timed out after %ss\n' "$step" "$timeout"
		else
			printf 'quick-install %s failed (exit %s)\n' "$step" "$status"
		fi
		tail -n 12 "$log_file"
	fi
	return "$status"
}

deploy_test_gate() {
	bashunit::set_test_title "$DEPLOY_PLATFORM deployment mode is valid"
	mkdir -p "$DEPLOY_RUN_DIR"
	if [[ "$DEPLOY_INSTALL_MODE" != separate && "$DEPLOY_INSTALL_MODE" != single ]]; then
		deploy_mark_infra_blocked
		assert_equals 'separate or single' "$DEPLOY_INSTALL_MODE" 'DEPLOY_INSTALL_MODE'
		return
	fi
	assert_matches '^(separate|single)$' "$DEPLOY_INSTALL_MODE"
	if [[ -e "$DEPLOY_INFRA_BLOCK_FILE" ]]; then
		bashunit::skip 'deployment setup failed'
	fi
}

deploy_mark_infra_blocked() {
	mkdir -p "$DEPLOY_RUN_DIR"
	: >"$DEPLOY_INFRA_BLOCK_FILE"
}

deploy_run_step() {
	local step=$1 name location command
	name=$(deploy_name "$DEPLOY_PLATFORM")
	location=$(deploy_execution_location)
	case "$step" in
	image) bashunit::set_test_title "$DEPLOY_PLATFORM image available" ;;
	created) bashunit::set_test_title "$DEPLOY_PLATFORM container available on $location" ;;
	started) bashunit::set_test_title "$DEPLOY_PLATFORM container started" ;;
	running) bashunit::set_test_title "$DEPLOY_PLATFORM container running" ;;
	ready) bashunit::set_test_title "$DEPLOY_PLATFORM container ready" ;;
	id) bashunit::set_test_title "$DEPLOY_PLATFORM OS ID matches" ;;
	version) bashunit::set_test_title "$DEPLOY_PLATFORM OS version matches" ;;
	dependencies) bashunit::set_test_title "$DEPLOY_PLATFORM dependencies installed" ;;
	apt_source_family) bashunit::set_test_title "$DEPLOY_PLATFORM APT stable source configured" ;;
	apt_source_tests) bashunit::set_test_title "$DEPLOY_PLATFORM APT tests source configured" ;;
	apt_source_no_main) bashunit::set_test_title "$DEPLOY_PLATFORM obsolete APT source absent" ;;
	mariadb) bashunit::set_test_title "$DEPLOY_PLATFORM MariaDB installed" ;;
	accounts) bashunit::set_test_title "$DEPLOY_PLATFORM SQL accounts created" ;;
	credentials) bashunit::set_test_title "$DEPLOY_PLATFORM SQL credentials saved" ;;
	dotnet) bashunit::set_test_title "$DEPLOY_PLATFORM .NET runtime installed" ;;
	opensim) bashunit::set_test_title "$DEPLOY_PLATFORM OpenSim packages are installed" ;;
	packages) bashunit::set_test_title "$DEPLOY_PLATFORM package set complete" ;;
	setup_credentials) bashunit::set_test_title "$DEPLOY_PLATFORM setup credentials accepted" ;;
	*) bashunit::set_test_title "$DEPLOY_PLATFORM $step" ;;
	esac
	if [[ -e "$DEPLOY_INFRA_BLOCK_FILE" ]]; then
		bashunit::skip 'deployment setup failed'
		return
	fi
	if [[ -e "$(deploy_platform_block_file "$DEPLOY_PLATFORM")" ]]; then
		bashunit::skip "$DEPLOY_PLATFORM prerequisite failed"
		return
	fi

	case "$step" in
	apt_source_family | apt_source_tests | apt_source_no_main)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		local expected
		case "$step" in
		apt_source_family) expected='deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable' ;;
		apt_source_tests) expected='deb [trusted=yes] https://apt.magiiic.com charm-tests dev' ;;
		apt_source_no_main)
		printf -v command 'deploy_command exec %q -- sh -c %q' "$name" '! grep -Eq "^[[:space:]]*deb .*apt\\.magiiic\\.com main " /etc/apt/sources.list.d/magiiic.list'
			deploy_assert_exec "$command"
			return
			;;
		esac
		printf -v command 'deploy_command exec %q -- grep -Fx %q /etc/apt/sources.list.d/magiiic.list' "$name" "$expected"
		deploy_assert_exec "$command"
		return
		;;
	image)
		local image_log image_command
		image_log=$(deploy_log_dir "$DEPLOY_PLATFORM")/image.log
		printf -v image_command 'deploy_ensure_image %q %q' "$DEPLOY_IMAGE" "$image_log"
		deploy_assert_exec "$image_command" --stdout-contains 'Image available'
		return
		;;
	created)
		if ! deploy_select_engine; then
			deploy_assert_exec 'deploy_select_engine'
			return
		else
			local status_output status_log
			status_log=$(deploy_log_dir "$DEPLOY_PLATFORM")/status.log
			mkdir -p "$(dirname "$status_log")"
			if deploy_command status "$name" >"$status_log" 2>&1; then
				printf -v command 'deploy_command status %q' "$name"
				deploy_assert_exec "$command" --stdout-contains "Image: $DEPLOY_IMAGE"
				return
			fi
			local create_args=(deploy_command create --no-start --name "$name" --image "$DEPLOY_IMAGE"
				--label org.opensim-cli.deploy=1
				--label "org.opensim-cli.deploy.platform=$DEPLOY_PLATFORM"
				--label "org.opensim-cli.deploy.host=$DEPLOY_HOST_SLUG"
				--label "org.opensim-cli.deploy.user=$DEPLOY_USER_SLUG"
				--label "org.opensim-cli.deploy.ephemeral=$DEPLOY_EPHEMERAL"
				--label "org.opensim-cli.deploy.run=$DEPLOY_RUN_ID")
			[[ -n "${MEMORY:-}" ]] && create_args+=(--memory "$MEMORY")
			create_args+=(-- sh -c 'while :; do sleep 3600; done')
			local create_log create_command
			create_log=$(deploy_log_dir "$DEPLOY_PLATFORM")/create.log
			mkdir -p "$(dirname "$create_log")"
			printf -v create_command 'deploy_create_container %q ' "$create_log"
			printf -v command '%q ' "${create_args[@]}"
			create_command+="$command"
			deploy_assert_exec "$create_command" --stdout-contains 'Container created'
			return
		fi
		;;
	started)
		local status_command status_output current_status
		printf -v status_command 'deploy_command status %q 2>&1' "$name"
		if ! status_output=$(deploy_command status "$name" 2>&1); then
			deploy_assert_exec "$status_command" --stdout-contains "Image: $DEPLOY_IMAGE"
			return
		fi
		current_status=$(printf '%s\n' "$status_output" | sed -n 's/^Status: //p')
		if [[ "$current_status" == running ]]; then
			deploy_assert_exec "$status_command" --stdout-contains 'Status: running'
			return
		fi
		local start_command
		printf -v start_command 'deploy_command start %q' "$name"
		deploy_assert_exec "$start_command"
		return
		;;
	running)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		local running_command
		printf -v running_command 'deploy_command status %q 2>&1' "$name"
		deploy_assert_exec "$running_command" --stdout-contains 'Status: running'
		return
		;;
	ready)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		local ready_command
		printf -v ready_command 'deploy_command exec %q -- sh -c %q' "$name" 'test -r /etc/os-release && test -x /bin/sh && command -v tar >/dev/null'
		deploy_assert_exec "$ready_command"
		return
		;;
	id)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		local id_command id_check
		id_check=' . /etc/os-release; if [ "${ID:-}" != "$1" ]; then printf "OS_RELEASE_MISMATCH expected ID=%s, got ID=%s\n" "$1" "${ID:-missing}" >&2; exit 1; fi'
		printf -v id_command 'deploy_command exec %q -- sh -c %q sh %q 2>&1' "$name" "$id_check" "$DEPLOY_EXPECTED_ID"
		deploy_assert_exec "$id_command"
		return
		;;
	version)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		local version_command version_check
		version_check=' . /etc/os-release; if [ "${ID:-}" != "$1" ] || [ "${VERSION_ID:-}" != "$2" ]; then printf "OS_RELEASE_MISMATCH expected ID=%s VERSION_ID=%s, got ID=%s VERSION_ID=%s\n" "$1" "$2" "${ID:-missing}" "${VERSION_ID:-missing}" >&2; exit 1; fi'
		printf -v version_command 'deploy_command exec %q -- sh -c %q sh %q %q 2>&1' "$name" "$version_check" "$DEPLOY_EXPECTED_ID" "$DEPLOY_EXPECTED_VERSION"
		deploy_assert_exec "$version_command"
		return
		;;
	dependencies | mariadb | dotnet | opensim)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		local log_dir log_file install_stamp installed_stamp container_log install_step option execute_install=1
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
		if [[ "$execute_install" == 1 ]]; then
			bashunit::set_test_title "$DEPLOY_PLATFORM $step install"
		else
			bashunit::set_test_title "$DEPLOY_PLATFORM $step verification"
		fi
		install_stamp=
		installed_stamp=
		if [[ "$execute_install" == 1 ]]; then
			install_stamp="$DEPLOY_APT_DIST/$DEPLOY_APT_COMPONENT:$(shasum -a 256 "$DEPLOY_PROJECT_ROOT/quick-install.sh" | awk '{print $1}')"
			if [[ "$step" == opensim ]]; then
				local apt_candidates
				apt_candidates=$(deploy_command exec "$name" -- sh -c '
					for package in bash-tools opensim opensim-cli opensim-engine opensim-helpers opensim-rest-php; do
						candidate=$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ { print $2 }')
						printf "%s=%s\n" "$package" "${candidate:-missing}"
					done
				' 2>/dev/null) || apt_candidates=
				if [[ -n "$apt_candidates" ]]; then
					install_stamp+=":$(printf '%s\n' "$apt_candidates" | shasum -a 256 | awk '{print $1}')"
				else
					install_stamp=
				fi
			fi
			installed_stamp=$(deploy_command exec "$name" -- sh -c 'cat /var/tmp/opensim-deploy-install-stamp 2>/dev/null' 2>/dev/null) || installed_stamp=
		fi
		if [[ "$step" == opensim && "$execute_install" == 1 && "$DEPLOY_EPHEMERAL" != 1 && -n "$install_stamp" && "$installed_stamp" == "$install_stamp" ]] && deploy_installation_is_current "$name"; then
			bashunit::skip "$DEPLOY_PLATFORM package set already installed"
			return
		fi
		mkdir -p "$log_dir"
		if [[ "$execute_install" == 1 ]]; then
			container_log="/tmp/$name/$install_step.log"
			local install_command
			printf -v install_command 'deploy_install_step %q %q %q %q %q %q %q %q' \
				"$name" "$log_file" "$container_log" "$option" "$install_step" \
				"$DEPLOY_QUICK_INSTALL_TIMEOUT" "$DEPLOY_APT_DIST" "$DEPLOY_APT_COMPONENT"
			if ! deploy_assert_exec "$install_command" --stdout-contains "quick-install $install_step completed"; then return; fi
		else
			local check_command check_label
			case "$step" in
				mariadb) check_label='MariaDB responds' ;;
				dotnet) check_label='.NET runtime is installed' ;;
				opensim) check_label='OpenSim packages are installed' ;;
			esac
			printf -v check_command 'deploy_install_check %q %q %q' "$name" "$step" "$log_file"
			if ! deploy_assert_exec "$check_command" --stdout-contains "$check_label"; then return; fi
		fi
		if [[ "$step" == opensim || ( "$DEPLOY_INSTALL_MODE" == single && "$step" == dependencies ) ]]; then
			local stamp_command
			printf -v stamp_command 'deploy_command exec %q -- sh -c %q sh %q' \
				"$name" 'printf "%s\\n" "$1" > /var/tmp/opensim-deploy-install-stamp' "$install_stamp"
			if ! deploy_assert_exec "$stamp_command"; then return; fi
		fi
		;;
	accounts)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		printf -v command 'deploy_command exec %q -- sh -c %q 2>&1' "$name" 'count=$(mysql -Nse "SELECT COUNT(*) FROM mysql.user WHERE User IN (0x6f70656e73696d5f61646d696e,0x6f70656e73696d) AND Host=0x6c6f63616c686f7374"); printf "OpenSim SQL accounts found: %s\n" "$count"'
		deploy_assert_exec "$command" --stdout-contains 'OpenSim SQL accounts found: 2'
		;;
	credentials)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		printf -v command 'deploy_command exec %q -- sh -c %q 2>&1' "$name" 'count=$(grep -Ec "^export OPENSIM_DB_(HOST|ADMIN_USER|ADMIN_PASS|USER|PASS)=" /root/.opensimrc); printf "saved database setting count: %s\n" "$count"; test "$count" -eq 5'
		deploy_assert_exec "$command" --stdout-contains 'saved database setting count: 5'
		;;
	packages)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		printf -v command 'deploy_command exec %q -- sh -c %q 2>&1' "$name" "count=\$(dpkg-query -W -f='\${db:Status-Status}\\n' bash-tools opensim opensim-cli opensim-engine opensim-helpers opensim-rest-php | grep -Ec '^installed\$'); printf 'Installed OpenSim package count: %s\\n' \"\$count\""
		deploy_assert_exec "$command" --stdout-contains 'Installed OpenSim package count: 6'
		;;
	setup_credentials)
		if ! assert_deployment_container_running "$DEPLOY_PLATFORM"; then return; fi
		local setup_script setup_command
		setup_script="$DEPLOY_RUN_DIR/setup-credentials-$DEPLOY_PLATFORM.sh"
		mkdir -p "$DEPLOY_RUN_DIR"
		cat >"$setup_script" <<-'SETUP_CREDENTIALS_TEST'
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
		printf -v setup_command 'deploy_run_script %q %q' "$name" "$setup_script"
		deploy_assert_exec "$setup_command"
		;;
	esac
}

deploy_cleanup_platform() {
	local platform=$1 name
	name=$(deploy_name "$platform")
	[[ "$DEPLOY_EPHEMERAL" == 1 ]] || return 0
	deploy_select_engine || return 1
	deploy_command status "$name" >/dev/null 2>&1 || return 0
	deploy_command destroy "$name" >/dev/null
}
