#!/usr/bin/env bash
set -euo pipefail

OPENSIM_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DEB_DIR=${1:?Usage: publish-test-packages.sh <debs-directory>}

source "$OPENSIM_ROOT/tests/bootstrap.sh"

[[ -n "${APT_REPO_DIR:-}" && -d "$APT_REPO_DIR/conf" ]] || {
	printf 'APT_REPO_DIR must name the local official APT repository clone\n' >&2
	exit 1
}

git -C "$APT_REPO_DIR" pull -q --rebase --autostash
grep -Eq '^Codename:[[:space:]]*charm-tests$' "$APT_REPO_DIR/conf/distributions" || {
	printf 'APT repository has no charm-tests distribution in conf/distributions\n' >&2
	exit 1
}

packages=()
for deb in "$DEB_DIR"/*.deb; do
	[[ -s "$deb" ]] || continue
	name=$(dpkg-deb -f "$deb" Package)
	version=$(dpkg-deb -f "$deb" Version)
	if ! reprepro -b "$APT_REPO_DIR" list charm-tests "$name" | grep -Fq ": $name $version"; then
		packages+=("$deb")
	fi
done

if ((${#packages[@]} == 0)); then
	printf 'All current package versions are already in APT distribution charm-tests\n'
	exit 0
fi

APT_REPO_DIST=charm-tests APT_REPO_COMPONENT=dev "$OPENSIM_ROOT/vendor/bin/apt-publish" "${packages[@]}"
