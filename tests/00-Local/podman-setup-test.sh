#!/usr/bin/env bash

PODMAN_SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/libexec/podman-setup"

function set_up() {
	WORK=$(mktemp -d)
	export HOME="$WORK" COMMAND_LOG="$WORK/commands.log"
	export PODMAN_SETUP_SUBUID_FILE="$WORK/subuid" PODMAN_SETUP_SUBGID_FILE="$WORK/subgid"
	mkdir -p "$WORK/bin"
	cat >"$WORK/subuid" <<'IDS'
magic:100000:65536
other:165536:65536
IDS
	cat >"$WORK/subgid" <<'IDS'
magic:100000:65536
other:165536:65536
IDS
	cat >"$WORK/bin/getent" <<'GETENT'
#!/usr/bin/env bash
[[ "$1 $2" == 'passwd test-user' ]] || exit 2
printf 'test-user:x:2000:2000:Test User:/home/test-user:/bin/bash\n'
GETENT
	cat >"$WORK/bin/podman" <<'PODMAN'
#!/usr/bin/env bash
exit 0
PODMAN
	cat >"$WORK/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COMMAND_LOG"
[[ "${1:-}" == --preserve-env=* ]] && shift
if [[ "${1:-}" == -u ]]; then
	shift 2
	[[ "${1:-}" == -- ]] && shift
	if [[ "${1:-}" == podman ]]; then
		case "${2:-}" in
			ps | system) exit 0 ;;
			unshare) printf '0 2000 1\n' ;;
		esac
	fi
fi
exit 0
SUDO
	chmod +x "$WORK/bin/getent" "$WORK/bin/podman" "$WORK/bin/sudo"
}

function tear_down() {
	rm -rf "$WORK"
}

function test_assigns_first_range_free_in_both_subid_files_to_the_requested_user() {
	assert_exec "PATH='$WORK/bin:$PATH' '$PODMAN_SETUP' test-user" \
		--stdout-contains 'Assigning subuid/subgid range 231072-296607 to test-user' \
		--stdout-contains 'Rootless Podman is configured for test-user'
	assert_file_contains "$COMMAND_LOG" 'usermod --add-subuids 231072-296607 --add-subgids 231072-296607 test-user'
}

function test_requires_a_username_argument() {
	assert_exec "PATH='$WORK/bin:$PATH' '$PODMAN_SETUP'" --exit 2 --stderr-contains 'usage: podman-setup USER'
}

function test_does_not_add_a_second_range_when_the_user_already_has_one() {
	printf 'test-user:231072:65536\n' >>"$WORK/subuid"
	printf '2000:231072:65536\n' >>"$WORK/subgid"
	assert_exec "PATH='$WORK/bin:$PATH' '$PODMAN_SETUP' test-user" \
		--stdout-contains 'test-user already has rootless Podman subuid/subgid ranges'
	assert_file_not_exists "$COMMAND_LOG"
}
