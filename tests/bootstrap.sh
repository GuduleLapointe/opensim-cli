#!/usr/bin/env bash
# The environment of the tests, sourced by every script of tests/ that starts a container (and by bashunit, which sources the
# bootstrap of a tests folder itself: this file is plain bash, safe in strict mode, and changes nothing but the environment).
# Nothing specific to a machine is written in the tests: what is, is in tests/.env (see tests/.env.example), which is made from the
# example the first time.
#
#   CONTAINER_CONNECTION  the podman connection every container of the tests goes to, the machine that has the CPU and not the
#                         one the tests are started from. Every podman command that follows goes there, whoever runs it.
#   MEMORY                the memory of the container of a scenario
#
# The .env of the project, then tests/.env, are read; what the caller already set (MEMORY=1g tests/Packaging/run) is kept.
#
# Usage: source tests/bootstrap.sh   (from anywhere)

# The tests need bash 4 or later (the libraries use ${var,,}), the one `env bash` finds. Which one that is, is the choice of the person
# who runs them (the PATH): nothing here changes it, the tests stop with an older one.
if ((BASH_VERSINFO[0] < 4)); then
    echo "tests: bash 4 or later is needed, this is bash ${BASH_VERSION} ($BASH): make \`env bash\` find a newer one" >&2
    if [[ $- == *i* ]]; then return 1; else exit 1; fi
fi

__tests_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ! -f "$__tests_root/tests/.env" && -f "$__tests_root/tests/.env.example" ]]; then
    cp "$__tests_root/tests/.env.example" "$__tests_root/tests/.env"
    echo "tests: tests/.env made from tests/.env.example, edit it to run the containers on another machine" >&2
fi

for __tests_file in "$__tests_root/.env" "$__tests_root/tests/.env"; do
    [[ -f "$__tests_file" ]] || continue
    while IFS= read -r __tests_line || [[ -n "$__tests_line" ]]; do
        [[ "$__tests_line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
        __tests_name=${BASH_REMATCH[1]}
        __tests_value=${BASH_REMATCH[2]}
        __tests_value=${__tests_value%%[[:space:]]#*}
        __tests_value=${__tests_value%\"}
        __tests_value=${__tests_value#\"}
        __tests_value=${__tests_value%\'}
        __tests_value=${__tests_value#\'}
        # What the caller set wins over the files, tests/.env wins over the .env of the project
        if [[ -z "${!__tests_name+x}" || "${__tests_set:-}" == *" $__tests_name "* ]]; then
            export "$__tests_name=$__tests_value"
            __tests_set="${__tests_set:-} $__tests_name "
        fi
    done <"$__tests_file"
done

if [[ -n "${CONTAINER_CONNECTION:-}" ]]; then
    export CONTAINER_CONNECTION
    [[ -n "${__tests_said:-}" ]] || echo "tests: podman connection: $CONTAINER_CONNECTION" >&2
    export __tests_said=1
fi
unset __tests_root __tests_file __tests_line __tests_name __tests_value __tests_set
true
