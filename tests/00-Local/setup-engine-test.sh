#!/usr/bin/env bash

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

function set_up() {
	WORK=$(mktemp -d)
	export HOME=$WORK OPENSIM_RC=/dev/null OPENSIM_CONF=$WORK/opensim.conf OPENSIM_SYSTEM_USER=
	export OPENSIM_API=$PROJECT_ROOT/vendor/magicoli/opensim-engine/bin/opensim-api
	mkdir -p "$WORK/etc" "$WORK/core" "$WORK/var"
	cat >"$OPENSIM_CONF" <<-INI
		[Defaults]
		EtcRoot = $WORK/etc
		CoreRoot = $WORK/core
		VarRoot = $WORK/var
		SystemUser =
	INI
}

function tear_down() {
	rm -rf "$WORK"
}

function test_podman_setup_uses_selected_host_ports_when_preparing_the_grid() {
	cat >"$WORK/answers.json" <<'JSON'
{"type":"grid","name":"Olivier's Test-Grid","login_uri":"login.example.test","avatar":"Example Resident","password":"fixture-password","password2":"fixture-password","database_host":"localhost","database_user":"opensim","database_password":"fixture-db-password","admin_user":"opensim_admin","admin_password":"fixture-admin-password"}
JSON
	cat >"$WORK/container-tools" <<'CLI'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALL_LOG"
while [[ "$1" == --connection ]]; do shift 2; done
case "$1" in
	host-ports) printf '[8002,8003,8004,9000]\n' ;;
	info) printf '{"Name":"podman.example.test"}\n' ;;
	create) printf 'Container created\nName: oliviers_test-grid\n' ;;
	cp) [[ "$3" != *:/tmp/opensim-setup.json ]] || cp "$2" "$CAPTURED_CONFIG" ;;
esac
exit 0
CLI
	chmod +x "$WORK/container-tools"
	local line
	for ((line = 0; line < 50; line++)); do printf '\n'; done >"$WORK/input"
	assert_exec "CALL_LOG='$WORK/calls' CAPTURED_CONFIG='$WORK/prepared.json' CONTAINER_TOOLS_CLI='$WORK/container-tools' FE_INPUT_FD=7 FE_TTY='$WORK/none' OPENSIM_SETUP_UI=plain '$PROJECT_ROOT/quick-install.sh' --podman --config '$WORK/answers.json' --yes 7<'$WORK/input'" --stdout-contains 'Setup configuration saved'
	assert_contains 'create --name oliviers_test-grid' "$(cat "$WORK/calls")"
	assert_equals oliviers_test-grid "$(jq -r .identity "$WORK/prepared.json")"
	assert_equals 1 "$(jq -r .version "$WORK/prepared.json")"
	assert_equals 8012 "$(jq -r .setup.grid.public_port "$WORK/prepared.json")"
	assert_equals fixture-admin-password "$(jq -r .answers.admin_password "$WORK/prepared.json")"
	assert_directory_not_exists "$WORK/etc/grids"
}
