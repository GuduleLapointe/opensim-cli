#!/usr/bin/env bash
set -euo pipefail

OPENSIM_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD_TOOLS="$OPENSIM_ROOT/vendor/bin/build-tools"
DEPLOY_STAGE=${1:?Usage: build-packages.sh <package-stage> <artifact-stage>}
ARTIFACT_STAGE=${2:?Usage: build-packages.sh <package-stage> <artifact-stage>}
WORK=$(mktemp -d "$OPENSIM_ROOT/tests/.build-packages.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

BUILD_PROJECT="$WORK/project"
git clone --quiet --shared --no-checkout "$OPENSIM_ROOT" "$BUILD_PROJECT"
git -C "$BUILD_PROJECT" checkout --quiet --detach HEAD
ln -s "$OPENSIM_ROOT/vendor" "$BUILD_PROJECT/vendor"

# Build-tools stages path dependencies from the relative paths in composer.lock.
# Populate those paths from Composer's installed packages, regardless of whether
# Composer installed each package from a local path or from a distribution archive.
while IFS=$'\t' read -r composer_package repository_path; do
	[[ -n "$composer_package" ]] || continue
	case "$repository_path" in
	../*) relative_path=${repository_path#../} ;;
	*)
		printf 'unsupported Composer path repository for %s: %s\n' "$composer_package" "$repository_path" >&2
		exit 1
		;;
	esac
	[[ -n "$relative_path" && "$relative_path" != *../* && "$relative_path" != /* ]] || {
		printf 'Composer path repository escapes the build workspace: %s\n' "$repository_path" >&2
		exit 1
	}
	package_source="$BUILD_PROJECT/vendor/$composer_package"
	package_copy="$WORK/$relative_path"
	[[ -d "$package_source" ]] || {
		printf 'Composer package source is missing from vendor: %s\n' "$package_source" >&2
		exit 1
	}
	mkdir -p "$(dirname "$package_copy")"
	package_git_root=$(git -C "$package_source" rev-parse --show-toplevel 2>/dev/null || true)
	if [[ -n "$package_git_root" && "$package_git_root" != "$OPENSIM_ROOT" ]]; then
		git clone --quiet --shared --no-checkout "$package_source" "$package_copy"
		git -C "$package_copy" checkout --quiet --detach HEAD
	else
		mkdir -p "$package_copy"
		cp -R "$package_source/." "$package_copy/"
	fi
done < <(php -r '
$lock = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
foreach ($lock["packages"] ?? [] as $package) {
    if (($package["dist"]["type"] ?? "") === "path") {
        echo $package["name"], "\t", $package["dist"]["url"], "\n";
    }
}
' "$BUILD_PROJECT/composer.lock")

rm -rf "$DEPLOY_STAGE" "$ARTIFACT_STAGE"
mkdir -p "$DEPLOY_STAGE/debs" "$ARTIFACT_STAGE"
cd "$BUILD_PROJECT"
mkdir -p dist
find dist -mindepth 1 -maxdepth 1 -type f -delete
if ! GIT_CEILING_DIRECTORIES="$WORK" DIRTY=1 ./dev/build.sh >"$WORK/build.log" 2>&1; then
	cat "$WORK/build.log"
	exit 1
fi

cli_deb=$(find dist -maxdepth 1 -type f -name 'opensim-cli_*.deb' -size +0c -print -quit)
cli_zip=$(find dist -maxdepth 1 -type f -name '*.zip' -size +0c -print -quit)
[[ -n "$cli_deb" && -n "$cli_zip" ]] || {
	cat "$WORK/build.log"
	printf 'dev/build.sh did not produce a non-empty .deb and .zip\n' >&2
	exit 1
}
cp "$cli_deb" "$DEPLOY_STAGE/debs/"
cp "$cli_zip" "$ARTIFACT_STAGE/opensim-cli.zip"
cp "$OPENSIM_ROOT/kickstart.sh" "$DEPLOY_STAGE/kickstart.sh"

[[ $(find "$DEPLOY_STAGE/debs" -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ') == 1 ]]
(cd "$DEPLOY_STAGE/debs" && shasum -a 256 ./*.deb >SHA256SUMS)
(cd "$DEPLOY_STAGE" && shasum -a 256 kickstart.sh debs/*.deb >MANIFEST)
printf 'Built and staged the OpenSim CLI .deb and .zip from the Composer-installed sources.\n'
