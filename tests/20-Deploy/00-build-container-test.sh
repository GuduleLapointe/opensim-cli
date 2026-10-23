#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"

function test_00_local_and_build_passed() {
	DEPLOY_PLATFORM='package builder'
	deploy_test_gate
}

function test_01_package_builder_created() { deploy_builder_step created; }
function test_02_package_builder_started() { deploy_builder_step started; }
function test_03_package_builder_ready() { deploy_builder_step ready; }
function test_04_package_indexer_ready() { deploy_builder_step scanner; }
function test_05_packages_synced_and_indexed() { deploy_builder_step synced; }
function test_06_current_local_package_index_is_left_alone() { deploy_builder_step index_unchanged; }
function test_07_stale_local_package_index_is_refreshed() { deploy_builder_step index_refresh; }
function test_08_stale_local_package_source_is_replaced() { deploy_builder_step source_refresh; }
