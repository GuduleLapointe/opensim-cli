#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"
deploy_load_platform ubuntu-26.04

function test_00_local_and_build_passed() { deploy_test_gate; }
function test_01_package_volume() { deploy_run_step volume; }
function test_02_created() { deploy_run_step created; }
function test_03_started() { deploy_run_step started; }
function test_04_running() { deploy_run_step running; }
function test_05_ready() { deploy_run_step ready; }
function test_06_os_id() { deploy_run_step id; }
function test_07_os_version() { deploy_run_step version; }
function test_08_packages_synced() { deploy_run_step synced; }
function test_09_quick_install() { deploy_run_step installed; }
function test_10_packages_installed() { deploy_run_step packages; }
