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
git clone --quiet --shared --no-checkout "$OPENSIM_ROOT/../opensim-engine" "$WORK/opensim-engine"
git -C "$WORK/opensim-engine" checkout --quiet --detach HEAD
git clone --quiet --shared --no-checkout "$OPENSIM_ROOT/../opensim-rest-php" "$WORK/opensim-rest-php"
git -C "$WORK/opensim-rest-php" checkout --quiet --detach HEAD
ln -s "$OPENSIM_ROOT/vendor" "$BUILD_PROJECT/vendor"

rm -rf "$DEPLOY_STAGE" "$ARTIFACT_STAGE"
mkdir -p "$DEPLOY_STAGE/debs" "$ARTIFACT_STAGE"
cd "$BUILD_PROJECT"
mkdir -p dist
find dist -mindepth 1 -maxdepth 1 -type f -delete
if ! DIRTY=1 ./dev/build.sh >"$WORK/build.log" 2>&1; then
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
cp "$OPENSIM_ROOT/quick-install.sh" "$DEPLOY_STAGE/quick-install.sh"

for repo_package in \
	"$OPENSIM_ROOT/../bash-tools:bash-tools" \
	"$OPENSIM_ROOT/vendor/magicoli/opensim-engine:opensim-engine" \
	"$OPENSIM_ROOT/vendor/magicoli/opensim-rest-php:opensim-rest-php" \
	"$OPENSIM_ROOT/../opensim-helpers:opensim-helpers"; do
	repo=${repo_package%:*}
	package=${repo_package##*:}
	version=$(cd "$repo" && "$BUILD_TOOLS" version | sed -n 's/^DEB_VERSION=//p')
	deb="$repo/dist/${package}_${version}_all.deb"
	if [[ ! -s "$deb" ]]; then
		printf '%s package is missing or does not match its current source hash: %s\n' "$package" "$deb" >&2
		exit 1
	fi
	cp "$deb" "$DEPLOY_STAGE/debs/"
done

[[ $(find "$DEPLOY_STAGE/debs" -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ') == 5 ]]
(cd "$DEPLOY_STAGE/debs" && shasum -a 256 ./*.deb >SHA256SUMS)
(cd "$DEPLOY_STAGE" && shasum -a 256 quick-install.sh debs/*.deb >MANIFEST)
printf 'Built OpenSim CLI .deb and .zip; staged five current .deb packages.\n'
