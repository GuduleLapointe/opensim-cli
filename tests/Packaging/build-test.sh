#!/usr/bin/env bash
# Build test for opensim-cli
#
# Run with: tests/lib/bashunit tests/
#
# Confirms that dev/build.sh works and produces valid packages

OPENSIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up() {
    WORK="$(mktemp -d)"
}

function tear_down() {
    rm -rf "$WORK"
}

function test_build_sh_produces_deb_and_zip() {
    # Only run if we're on a system that can build (has dpkg-deb, etc.)
    if ! command -v dpkg-deb >/dev/null 2>&1; then
        bashunit::skip "dpkg-deb not available"
        return
    fi
    
    # Run build
    cd "$OPENSIM_ROOT"
    local output status
    output=$(./dev/build.sh 2>&1)
    status=$?
    
    # Should succeed
    assert_equals 0 "$status"
    
    # Should produce .deb and .zip
    assert_equals 1 "$(ls dist/*.deb 2>/dev/null | wc -l)"
    assert_equals 1 "$(ls dist/*.zip 2>/dev/null | wc -l)"
}
