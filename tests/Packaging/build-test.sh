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
    # Run build - it should work on any system that has nfpm (build-tools handles this)
    # Use DIRTY=1 to allow building with uncommitted changes
    cd "$OPENSIM_ROOT"
    local output status
    output=$(DIRTY=1 ./dev/build.sh 2>&1)
    status=$?
    
    # Should succeed
    assert_equals 0 "$status" "Build failed with:\n$output"
    
    # Should produce .deb and .zip
    assert_equals 1 "$(ls dist/*.deb 2>/dev/null | wc -l | tr -d ' ')" "No .deb file produced"
    assert_equals 1 "$(ls dist/*.zip 2>/dev/null | wc -l | tr -d ' ')" "No .zip file produced"
}
