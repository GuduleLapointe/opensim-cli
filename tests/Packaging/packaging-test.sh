#!/usr/bin/env bash
# Packaging tests for opensim-cli
#
# Run with: PACKAGING=1 tests/lib/bashunit tests/
#
# These tests are slow and require podman and packages in dist/
# They test that packages install and run on different distributions

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# Only run if explicitly requested via PACKAGING=1
if [[ -z "${PACKAGING:-}" ]]; then
    echo "Packaging tests are slow, set PACKAGING=1 to run" >&2
    # Skip all tests in this file by returning success
    # bashunit will see no tests ran and mark as skipped
    exit 0
fi

# Check we have podman
if ! command -v podman >/dev/null 2>&1; then
    echo "podman not available" >&2
    exit 0
fi

# Check we have packages
if ! ls dist/opensim-cli_*.deb >/dev/null 2>&1; then
    echo "no Debian package in dist/: build it first (dev/build.sh)" >&2
    exit 0
fi

# Source the test environment
source tests/bootstrap.sh

# Define test functions
function test_packages_install_on_debian_12() {
    local output status
    output=$(tests/Packaging/check docker.io/library/debian:bookworm 2>&1)
    status=$?
    
    assert_equals 0 "$status" "$output"
}

function test_packages_install_on_ubuntu_2404() {
    local output status
    output=$(tests/Packaging/check docker.io/library/ubuntu:24.04 2>&1)
    status=$?
    
    assert_equals 0 "$status" "$output"
}
