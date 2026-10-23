#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"
if deploy_load_platform debian-12; then
	function test_00_local_and_build_passed() { deploy_test_gate; }
	function test_01_image_available() { deploy_run_step image; }
	function test_02_created() { deploy_run_step created; }
	function test_03_started() { deploy_run_step started; }
	function test_04_running() { deploy_run_step running; }
	function test_05_ready() { deploy_run_step ready; }
	function test_06_os_id() { deploy_run_step id; }
	function test_07_os_version() { deploy_run_step version; }
	function test_08_packages_synced() { deploy_run_step synced; }
	function test_09_quick_install_dependencies() { deploy_run_step dependencies; }
	function test_10_mariadb() { deploy_run_step mariadb; }
	function test_11_sql_accounts() { deploy_run_step accounts; }
	function test_12_sql_settings_saved() { deploy_run_step credentials; }
	function test_13_dotnet_runtime() { deploy_run_step dotnet; }
	function test_14_opensim_packages() { deploy_run_step opensim; }
	function test_15_packages_installed() { deploy_run_step packages; }
	function test_16_setup_works_with_or_without_opensimrc() { deploy_run_step setup_credentials; }
fi

function tear_down_after_script() {
	deploy_cleanup_platform "$DEPLOY_PLATFORM"
}
