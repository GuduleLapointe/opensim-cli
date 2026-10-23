#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"
if deploy_load_platform debian-13; then
function test_00_local_and_build_passed() { deploy_test_gate; }
function test_01_created() { deploy_run_step created; }
function test_02_started() { deploy_run_step started; }
function test_03_running() { deploy_run_step running; }
function test_04_ready() { deploy_run_step ready; }
function test_05_os_id() { deploy_run_step id; }
function test_06_os_version() { deploy_run_step version; }
function test_07_packages_synced() { deploy_run_step synced; }
function test_08_opensim_packages() { deploy_run_step opensim; }
function test_09_dotnet_runtime() { deploy_run_step dotnet; }
function test_10_packages_installed() { deploy_run_step packages; }
fi
