#!/usr/bin/env bash
# opensim setup, with a stand-in for the engine (tests/fixtures/opensim-api): the questions, what the engine refuses, the summary.
#
# Run with: tests/lib/bashunit tests/

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/opensim"

function set_up() {
    export OPENSIM_API="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/opensim-api"
    export HOME="$(mktemp -d)"
}
function tear_down() {
    rm -rf "$HOME"
}

# opensim setup with these lines as the answers
function setup_with() {
    printf '%s\n' "$@" | "$OPENSIM" setup 2>&1
}

function test_a_grid_is_asked_then_shown_with_what_the_engine_proposes() {
    local out
    out=$(setup_with 1 "Magic Grid" "" "" "Ada Love" secret123 secret123 ada@example.org)
    assert_contains "Grid Magic Grid (magic_grid)" "$out"
    assert_contains "Login       http://amy.example.org:8002" "$out"
    assert_contains "Hypergrid   yes" "$out"
    assert_contains "Simulator   Welcome, region Welcome" "$out"
    assert_contains "Databases   amy_robust and amy_welcome (user opensim)" "$out"
    assert_contains "Owner       Ada Love <ada@example.org>" "$out"
}

function test_a_standalone_is_the_simulator_and_the_grid() {
    local out
    out=$(setup_with 2 "My Island" "" n "Ada Love" secret123 secret123 "")
    assert_contains "Standalone My Island (my_island)" "$out"
    assert_contains "Hypergrid   no" "$out"
    assert_contains "Simulator   My Island (it is the grid)" "$out"
    assert_contains "Database    amy_welcome (user opensim)" "$out"
}

function test_what_the_engine_refuses_is_asked_again_by_its_name() {
    local out
    out=$(setup_with 1 "Magic Grid" "" "" "Ada" secret123 secret123 "" "Ada Love")
    assert_contains "Avatar name (First Last): First and last name, e.g. Jane Doe." "$out"
    assert_contains "Owner       Ada Love" "$out"
    assert_not_contains "Password" "$out"
}

function test_two_different_passwords_are_not_sent() {
    local out
    out=$(setup_with 1 "Magic Grid" "" "" "Ada Love" secret123 other "" secret123 secret123)
    assert_contains "Avatar password: This field is required." "$out"
    assert_contains "Owner       Ada Love" "$out"
}

function test_a_choice_is_asked_until_it_is_one() {
    local out
    out=$(setup_with 9 2 "My Island" "" "" "Ada Love" secret123 secret123 "")
    assert_contains "Standalone My Island" "$out"
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
