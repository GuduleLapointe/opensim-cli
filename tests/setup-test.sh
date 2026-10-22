#!/usr/bin/env bash
# opensim setup, with a stand-in for the engine (tests/fixtures/opensim-api) that replays screens: the loop draws a screen, sends it back
# filled with the button pressed, and does the action it gets. What the screens say is the engine's business, tested there.
#
# Run with: tests/lib/bashunit tests/

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/opensim"

# The screens of the engine, as it gives them
MENU='{"data":{"attributes":{"action":"screen","kind":"menu","name":"type","title":"OpenSim setup","text":"","notice":"","items":[{"key":"grid","label":"Grid","note":""},{"key":"standalone","label":"Standalone","note":""},{"key":"speculoos","label":"Speculoos","note":"not implemented"}],"value":"","buttons":{"next":"OK","back":"Quit"},"state":"s1"}}}'
FORM='{"data":{"attributes":{"action":"screen","kind":"form","title":"Grid","text":"","notice":"","fields":[{"name":"name","label":"Grid name","value":"Amy","secret":false},{"name":"password","label":"Password","value":"","secret":true}],"buttons":{"next":"OK","back":"Back"},"state":"s2"}}}'
CHECKS='{"data":{"attributes":{"action":"screen","kind":"checks","title":"Options","text":"","notice":"","items":[{"name":"ssl","label":"SSL","checked":false,"note":"not implemented"},{"name":"hypergrid","label":"Hypergrid","checked":true,"note":""}],"buttons":{"next":"OK","back":"Back"},"state":"s3"}}}'
REVIEW='{"data":{"attributes":{"action":"screen","kind":"review","title":"Review","text":"","notice":"","rows":[{"section":"grid","label":"Grid name","value":"Amy"},{"section":"grid","label":"Login URI","value":"http://amy.example.org:8002"},{"section":"options","label":"Hypergrid","value":"yes"}],"buttons":{"next":"Install","back":"Back"},"state":"s4"}}}'
QUIT='{"data":{"attributes":{"action":"quit","message":"Grid name:  Amy\nWritten in /etc/opensim/grids/amy."}}}'
ABORT='{"data":{"attributes":{"action":"abort","error":"Cancelled"}}}'

function set_up() {
    WORK="$(mktemp -d)"
    export HOME="$WORK"
    export OPENSIM_API="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/opensim-api"
    export ENGINE_REPLIES="$WORK/replies" ENGINE_LOG="$WORK/requests"
    mkdir -p "$ENGINE_REPLIES"
}
function tear_down() {
    rm -rf "$WORK"
}

# The engine gives these replies, one for each call
function engine_says() {
    local n=0 reply
    rm -f "$ENGINE_REPLIES"/* "$ENGINE_REPLIES"/.count "$ENGINE_LOG"
    for reply in "$@"; do
        printf '%s' "$reply" >"$ENGINE_REPLIES/$((++n)).json"
    done
}

# The requests the engine got: one thing of the n-th (jq filter)
function request() { # n filter
    sed -n "${1}p" "$ENGINE_LOG" | jq -r ".data.attributes$2"
}

# opensim setup with these lines as the answers, in plain text (a form is a list, a number changes one answer)
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

function test_the_screens_of_the_engine_are_drawn_one_after_the_other_and_sent_back_filled() {
    local out
    engine_says "$MENU" "$FORM" "$CHECKS" "$REVIEW" "$QUIT"
    out=$(setup_with 2 1 "My Island" 2 secret123 "" "" no "")
    assert_contains "Grid name:  Amy" "$out"
    assert_contains "Written in /etc/opensim/grids/amy." "$out"
    # The first request asks for the first screen, the others carry the state of the screen before and its answers
    assert_equals "" "$(request 1 .state)"
    assert_equals "next" "$(request 1 .button)"
    assert_equals "s1" "$(request 2 .state)"
    assert_equals '{"type":"standalone"}' "$(request 2 '.answers | tojson')"
    assert_equals "s2" "$(request 3 .state)"
    assert_equals '{"name":"My Island","password":"secret123"}' "$(request 3 '.answers | tojson')"
    assert_equals '{"ssl":false,"hypergrid":false}' "$(request 4 '.answers | tojson')"
    assert_equals "s4" "$(request 5 .state)"
    assert_equals "next" "$(request 5 .button)"
    assert_equals 5 "$(grep -c '' "$ENGINE_LOG")"
}

function test_what_the_engine_says_is_shown_with_the_screen() {
    local out notice
    notice=$(jq -c '.data.attributes.notice = "Error: Avatar name invalid (First Last)"' <<<"$FORM")
    engine_says "$MENU" "$notice" "$ABORT"
    out=$(setup_with 1 "" :quit) || true
    assert_contains "Error: Avatar name invalid (First Last)" "$out"
    assert_contains "3) Speculoos (not implemented)" "$out"
}

function test_the_options_not_implemented_say_it() {
    local out
    engine_says "$CHECKS" "$ABORT"
    out=$(setup_with "" "") || true
    assert_contains "SSL (not implemented) [no]" "$out"
    assert_contains "Hypergrid [yes]" "$out"
}

function test_a_name_of_the_engine_is_not_taken_for_a_name_of_variable() {
    local out checks
    checks=$(jq -c '.data.attributes.items += [{"name":"economy-gloebit","label":"Economy: Gloebit","checked":false,"note":""}]' <<<"$CHECKS")
    engine_says "$checks" "$ABORT"
    out=$(setup_with "" "" yes) || true
    assert_not_contains "variable" "$out"
    assert_equals '{"ssl":false,"hypergrid":true,"economy-gloebit":true}' "$(request 2 '.answers | tojson')"
}

function test_the_password_is_not_shown_in_the_list_of_the_form() {
    local out
    engine_says "$MENU" "$FORM" "$ABORT"
    out=$(setup_with 1 2 secret123 "" ) || true
    assert_not_contains "secret123" "$out"
    assert_contains "********" "$out"
}

function test_the_button_pressed_goes_back_to_the_engine_which_decides_what_comes() {
    engine_says "$MENU" "$FORM" "$CHECKS" "$FORM" "$ABORT"
    setup_with 1 "" :back "" >/dev/null || true
    assert_equals "back" "$(request 4 .button)"
    assert_equals "s3" "$(request 4 .state)"
}

function test_quit_is_a_button_too() {
    engine_says "$MENU" "$ABORT"
    setup_with :quit >/dev/null || true
    assert_equals "quit" "$(request 2 .button)"
}

function test_an_abort_ends_with_the_error_of_the_engine_and_a_failure() {
    local out status=0
    engine_says "$ABORT"
    out=$(setup_with) || status=$?
    assert_contains "Cancelled" "$out"
    assert_not_equals 0 "$status"
}

function test_a_quit_ends_with_its_message_and_a_success() {
    local out status=0
    engine_says "$QUIT"
    out=$(setup_with) || status=$?
    assert_contains "Written in /etc/opensim/grids/amy." "$out"
    assert_equals 0 "$status"
}

function test_a_reply_that_is_not_one_ends_the_setup() {
    local out status=0
    engine_says "not json at all"
    out=$(setup_with) || status=$?
    assert_contains "does not answer as it should" "$out"
    assert_not_equals 0 "$status"
}

function test_a_screen_nobody_knows_ends_the_setup() {
    local out status=0
    engine_says "$(jq -c '.data.attributes.kind = "carousel"' <<<"$MENU")"
    out=$(setup_with) || status=$?
    assert_contains "screen this command does not know: carousel" "$out"
    assert_not_equals 0 "$status"
}

function test_no_command_says_the_usage() {
    local out
    out=$("$OPENSIM" 2>&1)
    assert_contains "usage: opensim" "$out"
    assert_contains "setup" "$out"
}

function test_the_help_of_a_command() {
    # Currently setup --help shows the general usage, not the subcommand usage
    # This test confirms the current behavior
    assert_contains "usage: opensim" "$("$OPENSIM" setup --help 2>&1)"
}

function test_dialog_draws_each_kind_of_screen_with_the_buttons_the_engine_names() {
    local out log
    make_fake_dialog
    engine_says "$MENU" "$FORM" "$CHECKS" "$REVIEW" "$QUIT"
    printf '%s\n' '0:standalone' '0:My Island\nsecret123\n' '0:c_hypergrid\n' '0:' >"$DIALOG_ANSWERS"
    out=$(setup_with_dialog)
    log=$(cat "$DIALOG_LOG")
    assert_contains "Written in /etc/opensim/grids/amy." "$out"
    assert_contains "--title OpenSim setup --cancel-label Quit --no-tags --menu  10 60 3 grid Grid standalone Standalone speculoos Speculoos (not implemented)" "$log"
    assert_contains "--title Grid --cancel-label Back --insecure --mixedform  11 72 2 Grid name 1 1 Amy 1" "$log"
    assert_contains "Password 2 1  2" "$(grep mixedform "$DIALOG_LOG")"
    assert_contains "--title Options --cancel-label Back --no-tags --separate-output --checklist  10 50 2 c_ssl SSL (not implemented) off c_hypergrid Hypergrid on" "$log"
    assert_contains "--title Review --ok-label Install --cancel-label Back --scrollbar --no-tags --menu  12 78 5" "$log"
    assert_not_contains "--ok-label OK" "$log"
    assert_equals "menu mixedform checklist menu" "$(grep -oE -- '--(menu|mixedform|checklist)' "$DIALOG_LOG" | sed 's/--//' | tr '\n' ' ' | sed 's/ $//')"
    assert_equals '{"type":"standalone"}' "$(request 2 '.answers | tojson')"
    assert_equals '{"name":"My Island","password":"secret123"}' "$(request 3 '.answers | tojson')"
    assert_equals '{"ssl":false,"hypergrid":true}' "$(request 4 '.answers | tojson')"
    assert_contains "bindkey formfield ENTER form_NEXT" "$log"
}

function test_dialog_the_cancel_button_is_back_and_escape_is_quit() {
    make_fake_dialog
    engine_says "$MENU" "$FORM" "$CHECKS" "$ABORT"
    printf '%s\n' '0:grid' '0:Amy\n\n' '1:' '255:' >"$DIALOG_ANSWERS"
    setup_with_dialog >/dev/null || true
    assert_equals "back" "$(request 4 .button)"
    assert_equals "next" "$(request 3 .button)"
}

function test_dialog_shows_the_notice_above_the_screen() {
    local notice
    make_fake_dialog
    notice=$(jq -c '.data.attributes.notice = "Error: Passwords differ"' <<<"$FORM")
    engine_says "$MENU" "$notice" "$ABORT"
    printf '%s\n' '0:grid' '255:' >"$DIALOG_ANSWERS"
    setup_with_dialog >/dev/null || true
    assert_contains "Error: Passwords differ" "$(grep mixedform "$DIALOG_LOG")"
    assert_contains "--mixedform Error: Passwords differ 11 72 2" "$(grep mixedform "$DIALOG_LOG")"
}

function test_what_the_engine_says_on_its_error_output_is_not_part_of_its_answer() {
    local out status=0
    engine_says "$QUIT"
    out=$(ENGINE_NOISE="Deprecated: a library is old" setup_with) || status=$?
    assert_equals 0 "$status"
    assert_contains "Written in /etc/opensim/grids/amy." "$out"
    assert_not_contains "Deprecated" "$out"
}

function test_it_is_shown_when_the_answer_is_not_one() {
    local out status=0
    engine_says "not json at all"
    out=$(ENGINE_NOISE="Fatal: the engine is broken" setup_with) || status=$?
    assert_contains "Fatal: the engine is broken" "$out"
    assert_not_equals 0 "$status"
}

function test_a_field_that_is_only_shown_is_not_asked_nor_sent_back() {
    local out form
    form=$(jq -c '.data.attributes.fields = [{"name":"preset_grid","label":"Grid","value":"Speculoos","secret":false,"readonly":true},{"name":"name","label":"Region name","value":"Welcome","secret":false,"readonly":false}]' <<<"$FORM")
    engine_says "$MENU" "$form" "$ABORT"
    out=$(setup_with 1 1 2 Plaza "") || true
    assert_contains "1) Grid                       Speculoos" "$out"
    assert_equals '{"name":"Plaza"}' "$(request 3 '.answers | tojson')"
}

function test_dialog_draws_a_field_that_is_only_shown_read_only() {
    local form
    make_fake_dialog
    form=$(jq -c '.data.attributes.fields = [{"name":"preset_grid","label":"Grid","value":"Speculoos","secret":false,"readonly":true},{"name":"name","label":"Region name","value":"Welcome","secret":false,"readonly":false}]' <<<"$FORM")
    engine_says "$MENU" "$form" "$ABORT"
    printf '%s\n' '0:grid' '0:Speculoos\nPlaza\n' >"$DIALOG_ANSWERS"
    setup_with_dialog >/dev/null || true
    assert_contains "Grid 1 1 Speculoos 1 13 40 200 2 Region name 2 1 Welcome 2 13 40 200 0" "$(grep mixedform "$DIALOG_LOG")"
    assert_equals '{"name":"Plaza"}' "$(request 3 '.answers | tojson')"
}

function test_what_takes_time_is_said_before_it_is_asked() {
    local out review
    review=$(jq -c '.data.attributes.wait = "Installing, this can take a few minutes…"' <<<"$REVIEW")
    engine_says "$review" "$QUIT"
    out=$(setup_with "") || true
    assert_contains "Installing, this can take a few minutes…" "$out"
    assert_contains "Written in /etc/opensim/grids/amy." "$out"
}
