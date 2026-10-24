#!/usr/bin/env bash
# Releases this project, from where it stands to the end (build-tools release).
# --tests publishes development packages to the APT tests suite only; it does
# not prepare or publish a version release.

here=$(cd "$(dirname "$0")/.." && pwd)
if [[ ${1:-} == --tests ]]; then
	shift
	tool=${APT_PACKAGE:-$here/vendor/magicoli/build-tools/bin/apt-package}
	[[ -x "$tool" ]] || { echo "apt-package is not installed: composer install" >&2; exit 1; }
	exec "$tool" --publish --tests "$@"
fi

tool="$here/vendor/bin/build-tools"
[[ -x "$tool" ]] || { echo "build-tools is not installed: composer install" >&2; exit 1; }
exec "$tool" release "$@"
