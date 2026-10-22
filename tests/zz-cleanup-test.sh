#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/20-Deploy" && pwd)/deploy-test-helpers.sh"

function test_01_cleanup_debian_12() { deploy_cleanup_platform debian-12; }
function test_02_cleanup_debian_13() { deploy_cleanup_platform debian-13; }
function test_03_cleanup_ubuntu_24_04() { deploy_cleanup_platform ubuntu-24.04; }
function test_04_cleanup_ubuntu_26_04() { deploy_cleanup_platform ubuntu-26.04; }
