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
echo "rc: $(tr '\n' ';' <"$DIALOGRC")" >>"$DIALOG_LOG"
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

# The five options of the stub engine are asked one by one in plain text, Enter keeps the proposal
OPTS=("" "" "" "" "")

function test_a_grid_is_asked_in_one_form_then_the_options_then_shown_to_confirm() {
    local out
    out=$(setup_with 1 1 "Magic Grid" 3 "Ada Love" 4 secret123 5 secret123 6 ada@example.org "" "${OPTS[@]}" "")
    assert_contains "Magic Grid" "$(grep '1) Grid name' <<<"$out" | tail -1)"
    assert_contains "amy.example.org:8002" "$(grep '2) Login URI' <<<"$out" | tail -1)"
    assert_contains "* Grid name: Magic Grid (magic_grid)" "$out"
    assert_contains "* Login URI: http://amy.example.org:8002" "$out"
    assert_contains "* Hypergrid: yes" "$out"
    assert_contains "* Simulator: Welcome" "$out"
    assert_contains "* Avatar: Ada Love" "$out"
}

function test_the_options_say_what_is_not_implemented() {
    local out
    out=$(setup_with 1 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains "SSL (not implemented) [no]" "$out"
    assert_contains "Hypergrid [yes]" "$out"
    assert_contains "Cross-grid Search (not implemented) [no]" "$out"
    assert_contains "Economy: Gloebit (not implemented) [no]" "$out"
    assert_contains "Extended OSSL (not implemented) [no]" "$out"
    assert_contains "* SSL: no (not implemented)" "$out"
}

function test_the_sections_of_the_review_are_separated_by_a_blank_line() {
    local out
    out=$(setup_with 1 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains $'* Login URI: http://amy.example.org:8002\n\n* Options\n* Hypergrid: yes' "$out"
    assert_contains $'* SSL: no (not implemented)\n\n* Simulator\n* Simulator: Welcome\n\n* Owner\n* Avatar: Ada Love' "$out"
}

function test_what_to_keep_is_said_at_the_end() {
    local out
    out=$(setup_with 1 1 "Magic Grid" 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains $'Grid name:  Magic Grid\nLogin URI:  http://amy.example.org:8002\nAvatar:     Ada Love\n\nNothing was created yet.' "$out"
}

function test_a_standalone_names_its_region_and_hypergrid_is_an_option() {
    local out
    out=$(setup_with 2 1 "My Island" 3 "Ada Love" 4 secret123 5 secret123 "" "" no "" "" "" "")
    assert_contains "My Island" "$(grep '1) Region name' <<<"$out" | tail -1)"
    assert_contains "* Hypergrid: no" "$out"
    assert_contains "* Simulator: My Island" "$out"
}

function test_what_the_engine_refuses_comes_back_with_the_form_and_its_answers() {
    local out
    out=$(setup_with 1 3 "Ada" 4 secret123 5 secret123 "" 3 "Ada Love" "" "${OPTS[@]}" "")
    assert_contains "Error: Avatar name invalid (First Last)" "$out"
    assert_contains "* Avatar: Ada Love" "$out"
    assert_not_contains "Error: Password" "$out"
}

function test_two_different_passwords_are_not_sent() {
    local out
    out=$(setup_with 1 3 "Ada Love" 4 secret123 5 other "" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains "Error: Passwords differ" "$out"
    assert_contains "* Avatar: Ada Love" "$out"
}

function test_a_choice_is_asked_until_it_is_one() {
    local out
    out=$(setup_with 9 2 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains "* Grid name: Amy" "$out"
}

function test_the_types_come_from_the_engine_and_the_ones_not_implemented_are_refused() {
    local out
    out=$(setup_with 3 2 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains "1) Grid" "$out"
    assert_contains "3) Simulator (join other grid) (not implemented)" "$out"
    assert_contains "4) Speculoos (not implemented)" "$out"
    assert_contains "Not implemented yet" "$out"
    assert_contains "* Grid name: Amy" "$out"
}

function test_back_goes_one_step_back() {
    local out
    # From the options to the form (the answers stay), from the review to the options, from the form to the type
    out=$(setup_with 1 3 "Ada Love" 4 secret123 5 secret123 "" :back 6 ada@example.org "" "" no "" "" "" "")
    assert_contains "* Hypergrid: no" "$out"
    assert_contains "* Avatar: Ada Love" "$out"
    out=$(setup_with 1 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" :back "" no "" "" "" "")
    assert_contains "Nothing was created yet." "$out"
    assert_contains "* Hypergrid: yes" "$out"
    assert_contains "* Hypergrid: no" "$out"
    out=$(setup_with 1 :back 2 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains "* Simulator: Amy" "$out"
}

function test_quit_ends_the_setup() {
    local out status=0
    out=$(setup_with 1 :quit) || status=$?
    assert_contains "Cancelled" "$out"
    assert_not_equals 0 "$status"
}

function test_nothing_is_said_at_the_end_when_the_setup_is_cancelled_in_the_review() {
    local out status=0
    out=$(setup_with 1 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" :quit) || status=$?
    assert_contains "Cancelled" "$out"
    assert_not_contains "Nothing was created yet." "$out"
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

function test_dialog_shows_a_menu_one_form_the_options_then_a_review_that_scrolls() {
    local out log
    make_fake_dialog
    printf '%s\n' '0:standalone' '0:My Island\namy.example.org:8002\nAda Love\nsecret123\nsecret123\nada@example.org\n' '0:opt_hypergrid\n' '0:' >"$DIALOG_ANSWERS"
    out=$(setup_with_dialog)
    log=$(cat "$DIALOG_LOG")
    assert_contains "Grid name:  My Island" "$out"
    assert_contains "Nothing was created yet." "$out"
    assert_contains "--title OpenSim setup --ok-label OK --cancel-label Quit --no-tags --menu  11 50 4 grid Grid standalone Standalone simulator Simulator (join other grid) (not implemented) speculoos Speculoos (not implemented)" "$log"
    assert_contains "--title Options" "$log"
    assert_contains "--no-tags --separate-output --checklist  13 50 5 opt_ssl SSL (not implemented) off opt_hypergrid Hypergrid on opt_search Cross-grid Search (not implemented) off opt_gloebit Economy: Gloebit (not implemented) off opt_ossl Extended OSSL (not implemented) off" "$log"
    assert_contains "--title Review --ok-label Install --cancel-label Back --scrollbar --no-tags --menu  17 78 10 h1 -- Grid -- r2 Grid name: My Island (my_island)" "$log"
    assert_contains "Region name" "$(grep mixedform "$DIALOG_LOG")"
    assert_contains "--title Standalone" "$(grep mixedform "$DIALOG_LOG")"
    assert_equals "menu mixedform checklist menu" "$(grep -oE -- '--(menu|mixedform|checklist)' "$DIALOG_LOG" | sed 's/--//' | tr '\n' ' ' | sed 's/ $//')"
    assert_contains "bindkey formfield ENTER form_NEXT" "$log"
}

function test_dialog_unchecked_hypergrid_is_no_and_back_returns_one_screen() {
    local out
    make_fake_dialog
    printf '%s\n' '0:grid' \
        '0:Magic Grid\namy.example.org:8002\nAda Love\nsecret123\nsecret123\n\n' '1:' \
        '0:Magic Grid\namy.example.org:8002\nAda Love\nsecret123\nsecret123\n\n' '0:' '0:' >"$DIALOG_ANSWERS"
    out=$(setup_with_dialog)
    assert_contains "Hypergrid: no" "$(grep -- '--scrollbar' "$DIALOG_LOG")"
    assert_equals "menu mixedform checklist mixedform checklist menu" "$(grep -oE -- '--(menu|mixedform|checklist)' "$DIALOG_LOG" | sed 's/--//' | tr '\n' ' ' | sed 's/ $//')"
}

function test_dialog_back_from_the_review_returns_to_the_options() {
    local out
    make_fake_dialog
    printf '%s\n' '0:grid' '0:Magic Grid\namy.example.org:8002\nAda Love\nsecret123\nsecret123\n\n' '0:opt_hypergrid\n' '1:' '0:opt_hypergrid\nopt_ssl\n' '0:' >"$DIALOG_ANSWERS"
    out=$(setup_with_dialog)
    assert_equals "menu mixedform checklist menu checklist menu" "$(grep -oE -- '--(menu|mixedform|checklist)' "$DIALOG_LOG" | sed 's/--//' | tr '\n' ' ' | sed 's/ $//')"
    assert_contains "SSL: yes (not implemented)" "$(grep -- '--scrollbar' "$DIALOG_LOG" | tail -1)"
}

function test_dialog_engine_problems_come_back_in_the_form() {
    local out
    make_fake_dialog
    printf '%s\n' '0:grid' \
        '0:Magic Grid\namy.example.org:8002\nAda\nsecret123\nsecret123\n\n' \
        '0:Magic Grid\namy.example.org:8002\nAda Love\nsecret123\nsecret123\n\n' '0:opt_hypergrid\n' '0:' >"$DIALOG_ANSWERS"
    out=$(setup_with_dialog)
    assert_contains "Grid name:  Magic Grid" "$out"
    assert_contains "Error: Avatar name invalid (First Last)" "$(grep mixedform "$DIALOG_LOG" | tail -1)"
}

function test_every_error_comes_at_once_the_engines_and_ours() {
    local out
    out=$(setup_with 1 4 secret123 5 other "" 3 "Ada Love" 4 secret123 5 secret123 "" "${OPTS[@]}" "")
    assert_contains $'Error: Avatar name invalid (First Last)\nError: Passwords differ' "$out"
    assert_contains "* Avatar: Ada Love" "$out"
}

function test_the_accents_of_an_avatar_name_are_replaced_and_the_person_validates_the_change() {
    local out
    out=$(setup_with 1 3 "José García" 4 secret123 5 secret123 "" "" "${OPTS[@]}" "")
    assert_contains "Error: Avatar name transliterated" "$out"
    assert_contains "Jose Garcia" "$(grep '3) Avatar name' <<<"$out" | tail -1)"
    assert_contains "* Avatar: Jose Garcia" "$out"
}
