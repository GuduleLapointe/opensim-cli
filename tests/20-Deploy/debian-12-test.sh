#!/usr/bin/env bash
# bashunit: no-parallel-tests

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-test-helpers.sh"
if deploy_load_platform debian-12; then
	function test_00_local_build_passed() { deploy_test_gate; }
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
	function test_08_package_builder_is_running() { deploy_run_step builder_running; }
	function test_09_package_manifest_is_available() { deploy_run_step sync_current; }
	function test_10_package_bundle_archive_is_created() { deploy_run_step sync_archive; }
	function test_11_previous_package_bundle_is_cleared() { deploy_run_step sync_clear; }
	function test_12_package_bundle_is_extracted() { deploy_run_step sync_extract; }
	function test_13_package_bundle_checksums_match() { deploy_run_step synced; }
	function test_14_quick_install_dependencies() { deploy_run_step dependencies; }
	function test_15_mariadb_is_available() { deploy_run_step mariadb; }
	function test_16_sql_accounts_are_created() { deploy_run_step accounts; }
	function test_17_sql_credentials_are_saved() { deploy_run_step credentials; }
	function test_18_dotnet_runtime_is_available() { deploy_run_step dotnet; }
	function test_19_opensim_packages_are_installed() { deploy_run_step opensim; }
	function test_20_installed_packages_are_complete() { deploy_run_step packages; }
	function test_21_setup_works_with_or_without_opensimrc() { deploy_run_step setup_credentials; }
fi

function tear_down_after_script() {
	deploy_cleanup_platform "$DEPLOY_PLATFORM"
}
