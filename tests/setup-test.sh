#!/usr/bin/env bash
# opensim setup, with a stand-in for the engine (tests/fixtures/opensim-api): the questions, what the engine refuses, the summary.
#
# Run with: tests/lib/bashunit tests/

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/opensim"

function set_up() {
    export OPENSIM_API="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/opensim-api"
    WORK="$(mktemp -d)"
    export HOME="$WORK"
}
function tear_down() {
    rm -rf "$WORK"
}

# opensim setup with these lines as the answers, in plain text (the form is a list, a number changes one answer)
function setup_with() {
    printf '%s\n' "$@" >"$WORK/answers"
    (
        exec 7<"$WORK/answers"
        export FE_INPUT_FD=7 FE_TTY="$WORK/none" OPENSIM_SETUP_UI=plain
        "$OPENSIM" setup 2>&1
    )
}

# A dialog that answers what $DIALOG_ANSWERS lists, one line each: the exit code, a colon, what it prints (\n for a new line)
function make_fake_dialog() {
    mkdir -p "$WORK/bin"
    cat >"$WORK/bin/dialog" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$DIALOG_LOG"
answer=$(head -n 1 "$DIALOG_ANSWERS")
sed -i.bak 1d "$DIALOG_ANSWERS" && rm -f "$DIALOG_ANSWERS.bak"
code=${answer%%:*}
text=${answer#*:}
while [ $# -gt 0 ]; do [ "$1" = --output-fd ] && fd=$2; shift; done
[ -n "${fd:-}" ] && [ -n "$text" ] && printf '%b' "$text" >&"$fd"
exit "$code"
FAKE
    chmod +x "$WORK/bin/dialog"
    export DIALOG_LOG="$WORK/dialog.log" DIALOG_ANSWERS="$WORK/dialog.answers"
}

# opensim setup with dialog (the fake one) and no terminal
function setup_with_dialog() {
    (
        export PATH="$WORK/bin:$PATH" OPENSIM_SETUP_UI=dialog FE_TTY=/dev/null FE_SCREEN=/dev/null
        "$OPENSIM" setup 2>&1
    )
}

function test_a_grid_is_asked_in_one_form_then_shown_with_what_the_engine_proposes() {
    local out
    out=$(setup_with 1 1 "Magic Grid" 4 "Ada Love" 5 secret123 6 secret123 7 ada@example.org "")
    assert_contains "Magic Grid" "$(grep '1) Grid name' <<<"$out" | tail -1)"
    assert_contains "yes" "$(grep '3) Hypergrid' <<<"$out" | tail -1)"
    assert_contains "Grid Magic Grid (magic_grid)" "$out"
    assert_contains "Login       http://amy.example.org:8002" "$out"
    assert_contains "Simulator   Welcome, region Welcome" "$out"
    assert_contains "Databases   amy_robust and amy_welcome (user opensim)" "$out"
    assert_contains "Owner       Ada Love <ada@example.org>" "$out"
}

function test_a_standalone_is_the_simulator_and_the_grid() {
    local out
    out=$(setup_with 2 1 "My Island" 3 no 4 "Ada Love" 5 secret123 6 secret123 "")
    assert_contains "My Island" "$(grep '1) Simulator name' <<<"$out" | tail -1)"
    assert_contains "Standalone My Island (my_island)" "$out"
    assert_contains "Hypergrid   no" "$out"
    assert_contains "Simulator   My Island" "$out"
    assert_contains "Database    amy_welcome (user opensim)" "$out"
}

function test_what_the_engine_refuses_comes_back_with_the_form_and_its_answers() {
    local out
    out=$(setup_with 1 4 "Ada" 5 secret123 6 secret123 "" 4 "Ada Love" "")
    assert_contains "! Avatar name: First and last name, e.g. Jane Doe." "$out"
    assert_contains "Owner       Ada Love" "$out"
    assert_not_contains "! Avatar password" "$out"
}

function test_two_different_passwords_are_not_sent() {
    local out
    out=$(setup_with 1 4 "Ada Love" 5 secret123 6 other "" 5 secret123 6 secret123 "")
    assert_contains "! Passwords differ" "$out"
    assert_contains "Owner       Ada Love" "$out"
}

function test_a_choice_is_asked_until_it_is_one() {
    local out
    out=$(setup_with 9 2 4 "Ada Love" 5 secret123 6 secret123 "")
    assert_contains "Standalone" "$out"
}

function test_no_command_says_the_usage() {
    local out
    out=$("$OPENSIM" 2>&1)
    assert_contains "usage: opensim COMMAND" "$out"
    assert_contains "setup" "$out"
}

function test_the_help_of_a_command() {
    assert_contains "usage: opensim setup" "$("$OPENSIM" setup --help 2>&1)"
}

function test_back_from_the_form_is_the_menu_again() {
    local out
    out=$(setup_with 1 :back 2 4 "Ada Love" 5 secret123 6 secret123 "")
    assert_contains "Standalone" "$out"
    assert_contains "Owner       Ada Love" "$out"
}

function test_quit_ends_the_setup() {
    local out status=0
    out=$(setup_with 1 :quit) || status=$?
    assert_contains "Cancelled" "$out"
    assert_not_equals 0 "$status"
}

function test_dialog_shows_the_form_with_all_the_questions_at_once() {
    local out
    make_fake_dialog
    printf '%s\n' '0:standalone' '0:My Island\nhttp://amy.example.org:8002\nyes\nAda Love\nsecret123\nsecret123\nada@example.org\n' >"$DIALOG_ANSWERS"
    out=$(setup_with_dialog)
    assert_contains "Standalone My Island (my_island)" "$out"
    assert_contains "Owner       Ada Love <ada@example.org>" "$out"
    assert_contains "--menu" "$(cat "$DIALOG_LOG")"
    assert_contains "--mixedform" "$(cat "$DIALOG_LOG")"
    assert_contains "Avatar name" "$(grep mixedform "$DIALOG_LOG")"
    assert_equals 2 "$(wc -l <"$DIALOG_LOG" | tr -d ' ')"
}

function test_dialog_back_from_the_form_is_the_menu_again_and_the_engine_problems_come_back_in_the_form() {
    local out
    make_fake_dialog
    printf '%s\n' '0:grid' '1:' '0:grid' \
        '0:Magic Grid\nhttp://amy.example.org:8002\nyes\nAda\nsecret123\nsecret123\n\n' \
        '0:Magic Grid\nhttp://amy.example.org:8002\nyes\nAda Love\nsecret123\nsecret123\n\n' >"$DIALOG_ANSWERS"
    out=$(setup_with_dialog)
    assert_contains "Grid Magic Grid (magic_grid)" "$out"
    assert_contains "! Avatar name: First and last name" "$(grep mixedform "$DIALOG_LOG" | tail -1)"
}

