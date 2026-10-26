#!/usr/bin/env bash

RELEASE_WRAPPER=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/dev/release.sh

function set_up() {
    WORK=$(mktemp -d)
    mkdir -p "$WORK/dev" "$WORK/vendor/bin"
    cp "$RELEASE_WRAPPER" "$WORK/dev/release.sh"
    cat >"$WORK/vendor/bin/build-tools" <<'TOOL'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
TOOL
    chmod +x "$WORK/vendor/bin/build-tools"
}

function tear_down() {
    rm -rf "$WORK"
}

function test_release_delegates_to_build_tools() {
    assert_exec "bash '$WORK/dev/release.sh' beta" --stdout-contains '<release>' --stdout-contains '<beta>'
}

function test_test_publication_delegates_to_build_tools() {
    assert_exec "bash '$WORK/dev/release.sh' --tests" --stdout-contains '<release>' --stdout-contains '<--tests>'
}
