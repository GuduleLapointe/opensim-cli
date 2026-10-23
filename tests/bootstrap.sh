#!/usr/bin/env bash
# The environment of the tests, sourced by every script of tests/ that starts a container (and by bashunit, which sources the
# bootstrap of a tests folder itself: this file is plain bash, safe in strict mode, and changes nothing but the environment).
# Nothing specific to a machine is written in the tests: what is, is in tests/.env (see tests/.env.example), which is made from the
# example the first time.
#
#   CONTAINER_CONNECTION  the podman connection every container of the tests goes to, the machine that has the CPU and not the
#                         one the tests are started from. Every podman command that follows goes there, whoever runs it.
#   MEMORY                optional memory limit for a container; unset means no limit
#
# The project's rc-helpers read the project .env and ~/.opensimrc; tests/.env then adds test-specific defaults. What the caller
# already set (MEMORY=1g tests/Packaging/run) is kept.
#
# Usage: source tests/bootstrap.sh   (from anywhere)

# The tests need bash 4 or later (the libraries use ${var,,}), the one `env bash` finds. Which one that is, is the choice of the person
# who runs them (the PATH): nothing here changes it, the tests stop with an older one.
if ((BASH_VERSINFO[0] < 4)); then
	echo "tests: bash 4 or later is needed, this is bash ${BASH_VERSION} ($BASH): make \`env bash\` find a newer one" >&2
	if [[ $- == *i* ]]; then return 1; else exit 1; fi
fi

__tests_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Keep the caller's environment across rc-helpers, which may define the same settings. Command-line assignments must win over rc
# and test .env files.
declare -A __tests_caller_env=()
while IFS='=' read -r __tests_name __tests_value; do
	[[ "$__tests_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
	__tests_caller_env["$__tests_name"]=$__tests_value
done < <(env)

if [[ ! -f "$__tests_root/tests/.env" && -f "$__tests_root/tests/.env.example" ]]; then
	cp "$__tests_root/tests/.env.example" "$__tests_root/tests/.env"
	echo "tests: tests/.env made from tests/.env.example, edit it to run the containers on another machine" >&2
fi

# Use the ecosystem configuration loader rather than reading ~/.opensimrc here. Scripts may also be invoked independently and
# follow the same read_rc contract.
__tests_rc_helpers="$__tests_root/vendor/magicoli/opensim-engine/lib/rc-helpers"
if [[ -r "$__tests_rc_helpers" ]]; then
	# shellcheck source=/dev/null
	source "$__tests_rc_helpers"
	read_rc "$__tests_root"
fi
for __tests_name in "${!__tests_caller_env[@]}"; do
	__tests_declaration=$(declare -p "$__tests_name" 2>/dev/null || true)
	[[ "$__tests_declaration" =~ ^declare\ -[^[:space:]]*r ]] && continue
	export "$__tests_name=${__tests_caller_env[$__tests_name]}"
done

__tests_file="$__tests_root/tests/.env"
if [[ -f "$__tests_file" ]]; then
	while IFS= read -r __tests_line || [[ -n "$__tests_line" ]]; do
		[[ "$__tests_line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
		__tests_name=${BASH_REMATCH[1]}
		__tests_value=${BASH_REMATCH[2]}
		__tests_value=${__tests_value%%[[:space:]]#*}
		__tests_value=${__tests_value%\"}
		__tests_value=${__tests_value#\"}
		__tests_value=${__tests_value%\'}
		__tests_value=${__tests_value#\'}
		# Caller environment wins; tests/.env overrides project .env and ~/.opensimrc.
		if [[ -z "${__tests_caller_env[$__tests_name]+x}" ]]; then
			export "$__tests_name=$__tests_value"
		fi
	done <"$__tests_file"
fi

if [[ -n "${CONTAINER_CONNECTION:-}" ]]; then
	export CONTAINER_CONNECTION
	[[ -n "${__tests_said:-}" ]] || echo "tests: podman connection: $CONTAINER_CONNECTION" >&2
	export __tests_said=1
fi
unset __tests_root __tests_file __tests_line __tests_name __tests_value __tests_declaration __tests_caller_env
true
