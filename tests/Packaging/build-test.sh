#!/usr/bin/env bash
# Build and packaging tests for opensim-cli
#
# Run with: tests/lib/bashunit tests/
#
# Confirms that:
# - dev/build.sh works and produces valid packages
# - packages install correctly on Debian and Ubuntu

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

# Container-based packaging tests - only run if explicitly requested
# These require podman and will create containers to test package installation
function test_package_installs_on_debian_12() {
    # Only run if PACKAGING=1 is set
    if [[ -z "${PACKAGING:-}" ]]; then
        bashunit::skip "Set PACKAGING=1 to run container tests"
        return
    fi
    
    # Check we have podman
    if ! command -v podman >/dev/null 2>&1; then
        bashunit::skip "podman not available"
        return
    fi
    
    # Build packages first
    cd "$OPENSIM_ROOT"
    DIRTY=1 ./dev/build.sh >/dev/null 2>&1 || {
        bashunit::skip "Build failed, cannot test packaging"
        return
    }
    
    # Run packaging check on Debian 12
    local output status
    output=$(cd "$OPENSIM_ROOT" && tests/Packaging/check docker.io/library/debian:bookworm 2>&1)
    status=$?
    
    assert_equals 0 "$status" "Packaging check failed:\n$output"
}

function test_package_installs_on_ubuntu_2404() {
    # Only run if PACKAGING=1 is set
    if [[ -z "${PACKAGING:-}" ]]; then
        bashunit::skip "Set PACKAGING=1 to run container tests"
        return
    fi
    
    # Check we have podman
    if ! command -v podman >/dev/null 2>&1; then
        bashunit::skip "podman not available"
        return
    fi
    
    # Build packages first
    cd "$OPENSIM_ROOT"
    DIRTY=1 ./dev/build.sh >/dev/null 2>&1 || {
        bashunit::skip "Build failed, cannot test packaging"
        return
    }
    
    # Run packaging check on Ubuntu 24.04
    local output status
    output=$(cd "$OPENSIM_ROOT" && tests/Packaging/check docker.io/library/ubuntu:24.04 2>&1)
    status=$?
    
    assert_equals 0 "$status" "Packaging check failed:\n$output"
}
