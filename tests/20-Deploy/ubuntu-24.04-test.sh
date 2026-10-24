#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"
if deploy_load_platform ubuntu-24.04; then
	function test_00_deployment_mode_is_valid() { deploy_test_gate; }
	# @retry 1
	function test_01_container_image_is_available() { deploy_run_step image; }
	# @retry 1
	function test_02_container_is_created() { deploy_run_step created; }
	# @retry 1
	function test_03_container_start_succeeds() { deploy_run_step started; }
	# @retry 1
	function test_04_container_reports_running() { deploy_run_step running; }
	# @retry 1
	function test_05_container_is_ready() { deploy_run_step ready; }
	# @retry 1
	function test_06_os_id_matches_platform() { deploy_run_step id; }
	# @retry 1
	function test_07_os_version_matches_platform() { deploy_run_step version; }
	# @retry 1
	function test_08_quick_install_dependencies() { deploy_run_step dependencies; }
	function test_09_signed_charm_stable_and_unstable_sources_are_configured() { deploy_run_step apt_source_family; }
	function test_10_unsigned_charm_tests_dev_source_is_configured() { deploy_run_step apt_source_tests; }
	function test_11_obsolete_main_source_is_absent() { deploy_run_step apt_source_no_main; }
	function test_12_mariadb_is_available() { deploy_run_step mariadb; }
	function test_13_sql_accounts_are_created() { deploy_run_step accounts; }
	function test_14_sql_credentials_are_saved() { deploy_run_step credentials; }
	function test_15_dotnet_runtime_is_available() { deploy_run_step dotnet; }
	function test_16_opensim_packages_are_installed() { deploy_run_step opensim; }
	function test_17_installed_packages_are_complete() { deploy_run_step packages; }
	function test_18_setup_works_with_or_without_opensimrc() { deploy_run_step setup_credentials; }
fi

function tear_down_after_script() {
	deploy_cleanup_platform "$DEPLOY_PLATFORM"
}
