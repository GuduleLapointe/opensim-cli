#!/usr/bin/env bash

QUICK_INSTALL=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/quick-install.sh
QUICK_INSTALL_LIBRARY_LOADED=no

function quick_install_load_library() {
	if [[ "$QUICK_INSTALL_LIBRARY_LOADED" == yes ]]; then return 0; fi
	if ! bash -n "$QUICK_INSTALL"; then
		bashunit::skip 'quick-install syntax check failed'
		return 1
	fi
	QUICK_INSTALL_LIBRARY_ONLY=yes OPENSIM_RC=/dev/null source "$QUICK_INSTALL"
	QUICK_INSTALL_LIBRARY_LOADED=yes
	# write_magiiic_repositories normally installs the generated file as root.
	as_root() { "$@"; }
}

function set_up() {
	WORK=$(mktemp -d)
	MAGIIIC_SOURCE_FILE=$WORK/magiiic.list
	TMP=$WORK/quick-install
	mkdir -p "$WORK/bin"
	cat <<'APT_CACHE' >"$WORK/bin/apt-cache"
#!/usr/bin/env bash
printf 'libgdiplus:\n  Installed: (none)\n  Candidate: 6.1+dfsg-1\n'
APT_CACHE
	chmod +x "$WORK/bin/apt-cache"
	PATH="$WORK/bin:$PATH"
}

function tear_down() {
	rm -rf "$WORK"
}

function test_00_quick_install_has_valid_bash_syntax() {
	assert_exec "bash -n '$QUICK_INSTALL'"
}

function test_default_source_replaces_old_magiiic_distributions_and_preserves_other_sources() {
	quick_install_load_library || return
	cat <<'SOURCES' >"$MAGIIIC_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com stable main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com unstable main
deb [trusted=yes] https://apt.magiiic.com tests main
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable
deb [trusted=yes] https://apt.magiiic.com charm-tests dev
deb https://archive.ubuntu.com/ubuntu resolute main
SOURCES

	OPENSIM_KIT_APT_DIST=charm
	OPENSIM_KIT_APT_COMPONENT=stable
	MAGIIIC_REPOSITORIES=("deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable")
	write_magiiic_repositories "$MAGIIIC_SOURCE_FILE" "$TMP.sources"

	assert_contains 'deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_contains 'deb [trusted=yes] https://apt.magiiic.com charm-tests dev' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_contains 'deb https://archive.ubuntu.com/ubuntu resolute main' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com stable ' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com unstable ' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com tests ' "$(cat "$MAGIIIC_SOURCE_FILE")"
	assert_not_contains 'https://apt.magiiic.com main ' "$(cat "$MAGIIIC_SOURCE_FILE")"
}

function test_existing_components_are_merged_without_duplicates() {
	quick_install_load_library || return
	cat <<'SOURCES' >"$MAGIIIC_SOURCE_FILE"
deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable
SOURCES
	MAGIIIC_REPOSITORIES=('deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable')
	write_magiiic_repositories "$MAGIIIC_SOURCE_FILE" "$TMP.sources"

	assert_equals 1 "$(grep -Fc 'https://apt.magiiic.com charm stable unstable' "$MAGIIIC_SOURCE_FILE")"
}

function test_apt_candidate_detection_uses_localized_candidate_field() {
	quick_install_load_library || return
	assert_exec 'apt_has_candidate libgdiplus'
}

