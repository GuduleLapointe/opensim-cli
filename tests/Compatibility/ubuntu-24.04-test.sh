#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compatibility-test-helpers.sh"
compat_load_platform ubuntu-24.04

function test_00_local_and_build_passed() { compat_test_gate; }
function test_01_created() { compat_run_step created; }
function test_02_started() { compat_run_step started; }
function test_03_running() { compat_run_step running; }
function test_04_ready() { compat_run_step ready; }
function test_05_os_id() { compat_run_step id; }
function test_06_os_version() { compat_run_step version; }
