#!/usr/bin/env bash
# The test environment, also sourced by Bashunit in strict mode. It loads the shared user and project configuration, then
# tests/.env for test-only overrides. Caller-provided environment variables keep precedence.
#
# Usage: source tests/bootstrap.sh   (from anywhere)

# The tests need bash 4 or later (the libraries use ${var,,}), the one `env bash` finds. Which one that is, is the choice of the person
# who runs them (the PATH): nothing here changes it, the tests stop with an older one.
if ((BASH_VERSINFO[0] < 4)); then
	echo "tests: bash 4 or later is needed, this is bash ${BASH_VERSION} ($BASH): make \`env bash\` find a newer one" >&2
	if [[ $- == *i* ]]; then return 1; else exit 1; fi
fi

__tests_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Keep caller-provided values so command-line environment assignments win over config files.
declare -A __tests_caller_env=()
while IFS='=' read -r __tests_name __tests_value; do
	[[ "$__tests_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
	__tests_caller_env["$__tests_name"]=$__tests_value
done < <(env)

if [[ ! -f "$__tests_root/tests/.env" && -f "$__tests_root/tests/.env.example" ]]; then
	cp "$__tests_root/tests/.env.example" "$__tests_root/tests/.env"
	echo "tests: tests/.env made from tests/.env.example; edit it for local test overrides" >&2
fi

# Let the shared helper load ~/.opensimrc and project .env with its standard rules, then add test-only overrides.
__tests_rc_helpers="$__tests_root/vendor/magicoli/opensim-engine/lib/rc-helpers"
if [[ -r "$__tests_rc_helpers" ]]; then
	# shellcheck source=/dev/null
	source "$__tests_rc_helpers"
	read_rc "$__tests_root"
fi

__tests_source_env() {
	local file=$1 was_allexport=
	[[ -r "$file" ]] || return 0
	[[ $- == *a* ]] && was_allexport=1
	set -a
	# shellcheck disable=SC1090
	source "$file"
	[[ -n "$was_allexport" ]] || set +a
}

__tests_source_env "$__tests_root/tests/.env"

# PATH is intentionally taken from the configuration layer: ~/.opensimrc may remove development shims before tests run.
# Other caller values, including inline assignments such as FOO=baz, override every config file.
for __tests_name in "${!__tests_caller_env[@]}"; do
	[[ "$__tests_name" == PATH ]] && continue
	__tests_declaration=$(declare -p "$__tests_name" 2>/dev/null || true)
	[[ "$__tests_declaration" =~ ^declare\ -[^[:space:]]*r ]] && continue
	export "$__tests_name=${__tests_caller_env[$__tests_name]}"
done

unset -f __tests_source_env
unset __tests_root __tests_name __tests_value __tests_declaration __tests_rc_helpers __tests_caller_env
true
