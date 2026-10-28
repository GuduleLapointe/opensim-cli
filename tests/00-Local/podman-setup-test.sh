#!/usr/bin/env bash

PODMAN_SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/libexec/podman-setup"

function set_up() {
	WORK=$(mktemp -d)
	mkdir -p "$WORK/bin"
	printf 'magic:100000:65536\nother:165536:65536\n' >"$WORK/subuid"
	printf 'magic:100000:65536\nother:165536:65536\n' >"$WORK/subgid"
	cat >"$WORK/bin/id" <<'ID'
#!/usr/bin/env bash
[[ "${1:-}" == test-user ]] && exit 0
exec /usr/bin/id "$@"
ID
	cat >"$WORK/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
exit 0
SUDO
	chmod +x "$WORK/bin/id" "$WORK/bin/sudo"
}

function tear_down() {
	rm -rf "$WORK"
}

function test_selects_a_range_free_in_both_subid_files() {
	assert_exec "PATH='$WORK/bin:$PATH' PODMAN_SUBUID_FILE='$WORK/subuid' PODMAN_SUBGID_FILE='$WORK/subgid' DRY_RUN=yes USER=magic '$PODMAN_SETUP' test-user" \
		--stderr-contains 'sudo usermod --add-subuids 231072-296607 --add-subgids 231072-296607 test-user'
}
