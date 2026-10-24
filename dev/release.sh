#!/usr/bin/env bash
# Releases this project, from where it stands to the end (build-tools release).
# --tests publishes development packages to the APT tests suite only; it does
# not prepare or publish a version release.

here=$(cd "$(dirname "$0")/.." && pwd)
if [[ ${1:-} == --tests ]]; then
	shift
	tool=${APT_PACKAGE:-$here/vendor/magicoli/build-tools/bin/apt-package}
	[[ -x "$tool" ]] || { echo "apt-package is not installed: composer install" >&2; exit 1; }
	if [[ -z ${RELEASE_YES:-} ]]; then
		[[ -r /dev/tty ]] || { echo "release: cannot confirm publication without a terminal (set RELEASE_YES=1 to confirm)" >&2; exit 1; }
		printf 'Publish development packages to APT suite tests? (y/N) ' >/dev/tty
		answer=
		IFS= read -r answer </dev/tty || true
		[[ $answer == y || $answer == Y || $answer == yes || $answer == YES ]] || {
			echo 'release: stopped, nothing published' >&2
			exit 1
		}
	fi
	exec "$tool" --publish --tests "$@"
fi

tool="$here/vendor/bin/build-tools"
[[ -x "$tool" ]] || { echo "build-tools is not installed: composer install" >&2; exit 1; }
exec "$tool" release "$@"
