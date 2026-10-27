#!/usr/bin/env bash
# opensim setup, with a stand-in for the engine (tests/fixtures/opensim-api) that replays screens: the loop draws a screen, sends it back
# filled with the button pressed, and does the action it gets. What the screens say is the engine's business, tested there.
#
# Run with: composer test

OPENSIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/opensim"
SETUP_CONFIG=
ENGINE_CAPABILITIES='{"data":{"attributes":{"capabilities":["prepare","apply_prepared","existing_region"]}}}'

# The screens of the engine, as it gives them
MENU='{"data":{"attributes":{"action":"screen","kind":"menu","name":"type","title":"OpenSim setup","text":"","notice":"","items":[{"key":"grid","label":"Grid","note":""},{"key":"standalone","label":"Standalone","note":""},{"key":"speculoos","label":"Speculoos","note":"not implemented"}],"value":"","buttons":{"next":"OK","back":"Quit"},"state":"s1"}}}'
FORM='{"data":{"attributes":{"action":"screen","kind":"form","title":"Grid","text":"","notice":"","fields":[{"name":"name","label":"Grid name","value":"Amy","secret":false},{"name":"password","label":"Password","value":"","secret":true}],"buttons":{"next":"OK","back":"Back"},"state":"s2"}}}'
CHECKS='{"data":{"attributes":{"action":"screen","kind":"checks","title":"Options","text":"","notice":"","items":[{"name":"ssl","label":"SSL","checked":false,"note":"not implemented"},{"name":"hypergrid","label":"Hypergrid","checked":true,"note":""}],"buttons":{"next":"OK","back":"Back"},"state":"s3"}}}'
REVIEW='{"data":{"attributes":{"action":"screen","kind":"review","title":"Review","text":"","notice":"","rows":[{"section":"grid","label":"Grid name","value":"Amy"},{"section":"grid","label":"Login URI","value":"http://amy.example.org:8002"},{"section":"options","label":"Hypergrid","value":"yes"}],"buttons":{"next":"Install","back":"Back"},"state":"s4"}}}'
QUIT='{"data":{"attributes":{"action":"quit","message":"Grid name:  Amy\nWritten in /etc/opensim/grids/amy."}}}'
ABORT='{"data":{"attributes":{"action":"abort","error":"Cancelled"}}}'
DATABASE_FORM='{"data":{"attributes":{"action":"screen","kind":"form","title":"Database","text":"","notice":"","fields":[{"name":"database_host","label":"Database host","value":"localhost","secret":false},{"name":"database_name","label":"Database name","value":"opensim","secret":false},{"name":"database_user","label":"Database user","value":"opensim","secret":false},{"name":"database_password","label":"Database password","value":"db-pass","secret":true},{"name":"admin_user","label":"Administrator","value":"","secret":false},{"name":"admin_password","label":"Administrator password","value":"","secret":true}],"buttons":{"next":"OK","back":"Back"},"state":"database-state"}}}'

function set_up() {
	WORK="$(mktemp -d)"
	export HOME="$WORK"
	export OPENSIM_SYSTEM_USER=
	unset OPENSIM_CONF OPENSIM_RC OPENSIM_DB_HOST OPENSIM_DB_USER OPENSIM_DB_PASS OPENSIM_DB_ADMIN_USER OPENSIM_DB_ADMIN_PASS
	mkdir -p "$WORK/etc"
	cat >"$WORK/.opensim.conf" <<-INI
		[Defaults]
		EtcRoot = $WORK/etc
		SystemUser =
	INI
	local fixtures
	fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures"
	mkdir -p "$WORK/engine/bin" "$WORK/engine/lib"
	ln -s "$fixtures/opensim-api" "$WORK/engine/bin/opensim-api"
	cp "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../vendor/magicoli/opensim-engine/lib" && pwd)/rc-helpers" "$WORK/engine/lib/rc-helpers"
	export OPENSIM_API="$WORK/engine/bin/opensim-api"
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

function engine_prepares() {
	engine_says "$@"
	local file reply
	for file in "$ENGINE_REPLIES"/*.json; do
		reply=$(jq '.data.attributes.mode = "prepare"' "$file")
		printf '%s\n' "$reply" >"$file"
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
		if [[ -n "$SETUP_CONFIG" ]]; then
			"$OPENSIM" setup --config "$SETUP_CONFIG" 2>&1
		else
			"$OPENSIM" setup 2>&1
		fi
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

function test_setup_screens_drawn_and_sent_back_filled() {
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

function test_setup_prepare_saves_answers_without_system_setup() {
	local config=$WORK/prepared.json
	engine_prepares "$MENU" "$FORM" "$CHECKS" "$REVIEW" "$DATABASE_FORM" \
		'{"data":{"attributes":{"action":"prepared","configuration":{"answers":{"type":"grid","name":"Example","admin_password":"test-secret"},"setup":{"grid":{"nick":"example"}}},"message":"Setup configuration prepared."}}}'
	printf '%s\n' 1 '' '' '' '' >"$WORK/answers"
	assert_exec "FE_INPUT_FD=7 FE_TTY='$WORK/none' OPENSIM_SETUP_UI=plain OPENSIM_SYSTEM_USER=nobody OPENSIM_ETC_ROOT='$WORK/missing' '$OPENSIM' setup --prepare '$config' 7<'$WORK/answers'" \
		--stdout "Setup configuration saved in $config"
	assert_file_exists "$config"
	assert_equals 'Example' "$(jq -r .answers.name "$config")"
	assert_equals 'test-secret' "$(jq -r .answers.admin_password "$config")"
	assert_equals 0 "$(jq -s '[.[] | select(.data.attributes.mode != "prepare")] | length' "$ENGINE_LOG")"
	assert_directory_not_exists "$WORK/missing"
	if [[ $(uname) == Darwin ]]; then
		assert_equals 600 "$(stat -f '%Lp' "$config")"
	else
		assert_equals 600 "$(stat -c '%a' "$config")"
	fi
}

function test_setup_prepare_cancellation_preserves_existing_file() {
	local config=$WORK/prepared.json
	printf '%s\n' 'keep this configuration' >"$config"
	engine_prepares "$MENU" '{"data":{"attributes":{"action":"abort","error":"Cancelled"}}}'
	printf '%s\n' ':quit' >"$WORK/answers"
	assert_exec "FE_INPUT_FD=7 FE_TTY='$WORK/none' OPENSIM_SETUP_UI=plain '$OPENSIM' setup --prepare='$config' 7<'$WORK/answers' 2>&1" \
		--exit 1 --stdout-contains 'Cancelled'
	assert_equals 'keep this configuration' "$(cat "$config")"
}

function test_setup_prepare_rejects_an_older_engine_before_confirmation() {
	engine_says "$MENU"
	assert_exec "FE_TTY='$WORK/none' OPENSIM_SETUP_UI=plain '$OPENSIM' setup --prepare '$WORK/prepared.json' 2>&1" \
		--exit 1 --stdout-contains 'engine does not support setup preparation'
	assert_file_not_exists "$WORK/prepared.json"
	assert_equals 1 "$(cat "$ENGINE_REPLIES/.count")"
}

function test_setup_prepare_rejects_invalid_output_without_replacing_file() {
	local config=$WORK/prepared.json
	printf '%s\n' 'keep this configuration' >"$config"
	engine_prepares '{"data":{"attributes":{"action":"prepared","configuration":{"answers":"invalid"}}}}'
	assert_exec "'$OPENSIM' setup --prepare '$config' 2>&1" \
		--exit 1 --stdout-contains 'invalid setup configuration'
	assert_equals 'keep this configuration' "$(cat "$config")"
}

function test_setup_applies_prepared_config_without_questions() {
	local config=$WORK/prepared.json
	printf '%s\n' '{"version":1,"identity":"example","answers":{"type":"grid","password":"secret"},"setup":{}}' >"$config"
	chmod 600 "$config"
	engine_says "$QUIT"
	assert_exec "OPENSIM_SETUP_CONFIG_FILE='$WORK/ignored.json' OPENSIM_DB_ADMIN_USER=example_admin OPENSIM_DB_ADMIN_PASS=admin-fixture FE_TTY='$WORK/none' '$OPENSIM' setup --apply '$config' </dev/null" --stdout-contains 'Grid name:'
	assert_equals example "$(request 1 .configuration.identity)"
	assert_equals secret "$(request 1 .configuration.answers.password)"
	assert_equals example_admin "$(request 1 .configuration.answers.admin_user)"
	assert_equals admin-fixture "$(request 1 .configuration.answers.admin_password)"
	assert_equals 1 "$(cat "$ENGINE_REPLIES/.count")"
}

function test_setup_apply_rejects_a_questionnaire_response() {
	local config=$WORK/prepared.json
	printf '%s\n' '{"version":1,"identity":"example","answers":{},"setup":{}}' >"$config"
	engine_says "$MENU"
	assert_exec "FE_TTY='$WORK/none' '$OPENSIM' setup --apply='$config' </dev/null 2>&1" --exit 1 --stdout-contains 'could not apply the prepared configuration'
	assert_equals 1 "$(cat "$ENGINE_REPLIES/.count")"
}

function test_setup_apply_transfers_private_config_before_elevation() {
	local config=$WORK/prepared.json
	printf '%s\n' '{"version":1,"identity":"example","answers":{},"setup":{}}' >"$config"
	chmod 600 "$config"
	mkdir -p "$WORK/bin"
	cat >"$WORK/bin/sudo" <<-SUDO
	#!/usr/bin/env bash
	cat >"$WORK/received-config"
	SUDO
	chmod +x "$WORK/bin/sudo"
	assert_exec "PATH='$WORK/bin:$PATH' OPENSIM_SYSTEM_USER=nobody '$OPENSIM' setup --apply '$config'"
	assert_equals "$(cat "$config")" "$(cat "$WORK/received-config")"
}

function test_setup_adoption_requires_engine_support_before_apply() {
	local config=$WORK/prepared.json
	cat >"$config" <<'JSON'
{"version":1,"identity":"example.existing","answers":{"existing_region":"[Existing]\nRegionUUID=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee\nLocation=120,130\nInternalPort=9101\n"},"setup":{}}
JSON
	engine_says "$QUIT"
	assert_exec "'$OPENSIM' setup --apply '$config' </dev/null 2>&1" --exit 1 --stdout-contains 'engine does not support existing-region setup'
	assert_equals 1 "$(cat "$ENGINE_REPLIES/.count")"
}

function test_setup_prepares_an_existing_region_file() {
	local region=$WORK/existing.ini config=$WORK/prepared.json prepared
	cat >"$region" <<'INI'
[Existing Island]
RegionUUID = aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee
Location = 120,130
InternalPort = 9101
INI
	prepared=$(jq -cn --rawfile region "$region" '{data:{attributes:{action:"prepared",configuration:{version:1,identity:"example.existing_island",answers:{type:"simulator",existing_region:$region},setup:{}}}}}')
	engine_prepares "$ENGINE_CAPABILITIES" "$MENU" "$FORM" "$REVIEW" "$DATABASE_FORM" "$prepared"
	printf '\n\n\n' >"$WORK/answers"
	assert_exec "FE_INPUT_FD=7 FE_TTY='$WORK/none' OPENSIM_SETUP_UI=plain '$OPENSIM' setup --region-config '$region' --prepare '$config' 7<'$WORK/answers'" --stdout-contains 'Setup configuration saved'
	assert_equals simulator "$(request 3 .answers.type)"
	assert_equals "$(cat "$region")" "$(request 3 .answers.existing_region)"
	assert_equals "$(cat "$region")" "$(jq -r .answers.existing_region "$config")"
}

function test_setup_rejects_an_unreadable_region_file() {
	engine_prepares "$MENU"
	assert_exec "'$OPENSIM' setup --region-config='$WORK/missing.ini' --prepare '$WORK/setup.json' 2>&1" --exit 1 --stdout-contains 'cannot read region configuration'
	assert_file_not_exists "$ENGINE_REPLIES/.count"
}

function make_setup_sudo_executor() {
	mkdir -p "$WORK/bin"
	cat >"$WORK/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SUDO_LOG"
[[ "$1" != -u ]] || shift 2
preserved=
if [[ "$1" == --preserve-env=* ]]; then preserved=${1#*=}; shift; fi
[[ ",$preserved," == *,OPENSIM_API,* ]] || unset OPENSIM_API
exec "$@"
SUDO
	chmod +x "$WORK/bin/sudo"
}

function test_setup_stages_private_inputs_before_elevation() {
	local config=$WORK/answers.json region=$WORK/region.ini
	printf '%s\n' '{"type":"simulator","name":"Existing"}' >"$config"
	printf '%s\n' '[Existing]' 'RegionUUID = aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' >"$region"
	chmod 600 "$config" "$region"
	make_setup_sudo_executor
	engine_says "$ENGINE_CAPABILITIES" "$QUIT"
	assert_exec "SUDO_LOG='$WORK/sudo.log' PATH='$WORK/bin:$PATH' OPENSIM_SYSTEM_USER=nobody '$OPENSIM' setup --config '$config' --region-config '$region' </dev/null" --stdout-contains 'Grid name:'
	local forwarded
	forwarded=$(cat "$WORK/sudo.log")
	assert_not_contains "$config" "$forwarded"
	assert_not_contains "$region" "$forwarded"
	local staged
	staged=$(sed -n 's#.*\(/tmp/opensim-setup\.[^ /]*\)/input-[0-9]*.*#\1#p' "$WORK/sudo.log" | head -n 1)
	assert_not_empty "$staged"
	assert_directory_not_exists "$staged"
}

function test_setup_keeps_engine_override_when_elevating() {
	make_setup_sudo_executor
	engine_says "$QUIT"
	assert_exec "SUDO_LOG='$WORK/sudo.log' PATH='$WORK/bin:$PATH' OPENSIM_SYSTEM_USER=nobody '$OPENSIM' setup </dev/null" --stdout-contains 'Grid name:'
	assert_equals 1 "$(cat "$ENGINE_REPLIES/.count")"
}

function test_setup_preflights_private_inputs_before_copying() {
	local config=$WORK/answers.json
	printf '%s\n' '{"type":"simulator"}' >"$config"
	make_setup_sudo_executor
	engine_says "$QUIT"
	assert_exec "SUDO_LOG='$WORK/sudo.log' PATH='$WORK/bin:$PATH' OPENSIM_SYSTEM_USER=nobody '$OPENSIM' setup --config '$config' --region-config '$WORK/missing.ini' </dev/null 2>&1" --exit 1 --stdout-contains 'cannot read setup input'
	assert_file_not_exists "$WORK/sudo.log"
	assert_file_not_exists "$ENGINE_REPLIES/.count"
}

function test_setup_apply_reads_unexported_admin_settings() {
	local config=$WORK/prepared.json
	printf '%s\n' '{"version":1,"identity":"example","answers":{},"setup":{}}' >"$config"
	cat >"$WORK/.opensimrc" <<'RC'
OPENSIM_DB_ADMIN_USER=example_admin
OPENSIM_DB_ADMIN_PASS=admin-fixture
RC
	engine_says "$QUIT"
	assert_exec "'$OPENSIM' setup --apply '$config' </dev/null" --stdout-contains 'Grid name:'
	assert_equals example_admin "$(request 1 .configuration.answers.admin_user)"
	assert_equals admin-fixture "$(request 1 .configuration.answers.admin_password)"
}

function test_setup_config_selects_type_and_prefills_answers() {
	local out
	SETUP_CONFIG=$WORK/setup.json
	cat >"$WORK/setup.json" <<'JSON'
{"type":"grid","name":"Config Grid","password":"secret-pass","hypergrid":false}
JSON
	engine_says "$MENU" "$FORM" "$CHECKS" "$REVIEW" "$QUIT"
	out=$(setup_with '' no no '')
	assert_contains 'Grid name:  Amy' "$out"
	assert_equals 'grid' "$(request 2 '.answers.type')"
	assert_equals 'Config Grid' "$(request 3 '.answers.name')"
	assert_equals 'secret-pass' "$(request 3 '.answers.password')"
	assert_equals false "$(request 4 '.answers.hypergrid')"
	SETUP_CONFIG=
}

function test_setup_screens_mark_unimplemented_options_properly() {
	local out notice
	notice=$(jq -c '.data.attributes.notice = "Error: Avatar name invalid (First Last)"' <<<"$FORM")
	engine_says "$MENU" "$notice" "$ABORT"
	out=$(setup_with 1 "" :quit) || true
	assert_contains "Error: Avatar name invalid (First Last)" "$out"
	assert_contains "3) Speculoos (not implemented)" "$out"
}

function test_unimplemented_options_properly_marked_as_not_implemented() {
	local out
	engine_says "$CHECKS" "$ABORT"
	out=$(setup_with "" "") || true
	assert_contains "SSL (not implemented) [no]" "$out"
	assert_contains "Hypergrid [yes]" "$out"
}

function test_a_name_of_the_engine_is_not_mistaken_for_a_name_of_variable() {
	local out checks
	checks=$(jq -c '.data.attributes.items += [{"name":"economy-gloebit","label":"Economy: Gloebit","checked":false,"note":""}]' <<<"$CHECKS")
	engine_says "$checks" "$ABORT"
	out=$(setup_with "" "" yes) || true
	assert_not_contains "variable" "$out"
	assert_equals '{"ssl":false,"hypergrid":true,"economy-gloebit":true}' "$(request 2 '.answers | tojson')"
}

function test_form_passwords_are_hidden() {
	local out
	engine_says "$MENU" "$FORM" "$ABORT"
	out=$(setup_with 1 2 secret123 "") || true
	assert_not_contains "secret123" "$out"
	assert_contains "********" "$out"
}

function test_saved_database_admin_credentials_are_sent_to_the_engine() {
	local out
	cat <<-OPENSIM_RC >"$HOME/.opensimrc"
		export OPENSIM_DB_HOST=localhost
		export OPENSIM_DB_USER=opensim
		export OPENSIM_DB_PASS=app-secret
		export OPENSIM_DB_ADMIN_USER=opensim_admin
		export OPENSIM_DB_ADMIN_PASS=saved-secret
	OPENSIM_RC
	engine_says "$DATABASE_FORM" "$QUIT"
	out=$(setup_with "")
	assert_equals "opensim_admin" "$(request 2 '.answers.admin_user')"
	assert_equals "saved-secret" "$(request 2 '.answers.admin_password')"
	assert_contains "opensim_admin" "$out"
	assert_contains "Administrator password" "$out"
	assert_contains "********" "$out"
	assert_not_contains "saved-secret" "$out"
}

function test_saved_database_admin_credentials_are_sent_with_review_confirmation() {
	local out
	cat <<-OPENSIM_RC >"$HOME/.opensimrc"
		export OPENSIM_DB_HOST=localhost
		export OPENSIM_DB_USER=opensim
		export OPENSIM_DB_PASS=app-secret
		export OPENSIM_DB_ADMIN_USER=opensim_admin
		export OPENSIM_DB_ADMIN_PASS=saved-secret
	OPENSIM_RC
	engine_says "$MENU" "$FORM" "$CHECKS" "$REVIEW" "$QUIT"
	out=$(setup_with 1 "" no yes "")
	assert_equals "localhost" "$(request 5 '.answers.database_host')"
	assert_equals "opensim" "$(request 5 '.answers.database_user')"
	assert_equals "app-secret" "$(request 5 '.answers.database_password')"
	assert_equals "opensim_admin" "$(request 5 '.answers.admin_user')"
	assert_equals "saved-secret" "$(request 5 '.answers.admin_password')"
	assert_not_contains "saved-secret" "$out"
}

function test_dialog_is_only_selected_when_the_terminal_is_wide_enough() {
	local ui="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/lib/ui"
	assert_exec "bash -c 'source \"\$1\"; fe_dialog_fits_terminal 78' _ '$ui'"
	assert_exec "bash -c 'source \"\$1\"; fe_dialog_fits_terminal 37' _ '$ui'" --exit 1
	assert_exec "bash -c 'source \"\$1\"; fe_dialog_fits_terminal unknown' _ '$ui'" --exit 1
}

function test_database_admin_credentials_can_be_entered_without_opensimrc() {
	local out
	engine_says "$DATABASE_FORM" "$QUIT"
	out=$(setup_with 5 opensim_admin 6 interactive-secret "")
	assert_equals "opensim_admin" "$(request 2 '.answers.admin_user')"
	assert_equals "interactive-secret" "$(request 2 '.answers.admin_password')"
	assert_not_contains "interactive-secret" "$out"
}

function test_button_processing_is_left_to_the_engine_for_processing() {
	engine_says "$MENU" "$FORM" "$CHECKS" "$FORM" "$ABORT"
	setup_with 1 "" :back "" >/dev/null || true
	assert_equals "back" "$(request 4 .button)"
	assert_equals "s3" "$(request 4 .state)"
}

function test_quit_button_is_present() {
	engine_says "$MENU" "$ABORT"
	setup_with :quit >/dev/null || true
	assert_equals "quit" "$(request 2 .button)"
}

function test_abort_ends_with_the_error_of_the_engine_and_a_failure() {
	local out status=0
	engine_says "$ABORT"
	out=$(setup_with) || status=$?
	assert_contains "Cancelled" "$out"
	assert_exit_code 1 '' "$status"
}

function test_quit_ends_with_its_message_and_a_success() {
	local out status=0
	engine_says "$QUIT"
	out=$(setup_with) || status=$?
	assert_contains "Written in /etc/opensim/grids/amy." "$out"
	assert_exit_code 0 '' "$status"
}

function test_invalid_reply_from_engine_ends_the_setup_with_error() {
	local out status=0
	engine_says "not json at all"
	out=$(setup_with) || status=$?
	assert_contains "does not answer as it should" "$out"
	assert_exit_code 1 '' "$status"
}

function test_unknown_screen_ends_the_setup_with_error() {
	local out status=0
	engine_says "$(jq -c '.data.attributes.kind = "carousel"' <<<"$MENU")"
	out=$(setup_with) || status=$?
	assert_contains "screen this command does not know: carousel" "$out"
	assert_exit_code 1 '' "$status"
}

# Does not belong in setup tests
# function test_missing_command_triggers_usage_message() {
# 	local out
# 	out=$("$OPENSIM" 2>&1)
# 	assert_contains "usage: opensim" "$out"
# 	assert_contains "setup" "$out"
# }

# Does not belong in setup tests
# function test_help_option_triggers_help_message() {
# 	# Currently setup --help shows the general usage, not the subcommand usage
# 	# This test confirms the current behavior
# 	assert_contains "usage: opensim" "$("$OPENSIM" setup --help 2>&1)"
# }

function test_screen_title_describes_the_current_step() {
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

function test_cancel_button_is_back_and_escape_is_quit() {
	make_fake_dialog
	engine_says "$MENU" "$FORM" "$CHECKS" "$ABORT"
	printf '%s\n' '0:grid' '0:Amy\n\n' '1:' '255:' >"$DIALOG_ANSWERS"
	setup_with_dialog >/dev/null || true
	assert_equals "back" "$(request 4 .button)"
	assert_equals "next" "$(request 3 .button)"
}

function test_screen_shows_the_notice_above_the_form() {
	local notice
	make_fake_dialog
	notice=$(jq -c '.data.attributes.notice = "Error: Passwords differ"' <<<"$FORM")
	engine_says "$MENU" "$notice" "$ABORT"
	printf '%s\n' '0:grid' '255:' >"$DIALOG_ANSWERS"
	setup_with_dialog >/dev/null || true
	assert_contains "Error: Passwords differ" "$(grep mixedform "$DIALOG_LOG")"
	assert_contains "--mixedform Error: Passwords differ 11 72 2" "$(grep mixedform "$DIALOG_LOG")"
}

function test_error_is_not_displayed_as_part_of_the_answer() {
	local out status=0
	engine_says "$QUIT"
	out=$(ENGINE_NOISE="Deprecated: a library is old" setup_with) || status=$?
	assert_exit_code 0 '' "$status"
	assert_contains "Written in /etc/opensim/grids/amy." "$out"
	assert_not_contains "Deprecated" "$out"
}

function test_error_is_displayed_for_invalid_answer() {
	local out status=0
	engine_says "not json at all"
	out=$(ENGINE_NOISE="Fatal: the engine is broken" setup_with) || status=$?
	assert_contains "Fatal: the engine is broken" "$out"
	assert_exit_code 1 '' "$status"
}

function test_readonly_field_is_shown_and_readonly() {
	local form
	make_fake_dialog
	form=$(jq -c '.data.attributes.fields = [{"name":"preset_grid","label":"Grid","value":"Speculoos","secret":false,"readonly":true},{"name":"name","label":"Region name","value":"Welcome","secret":false,"readonly":false}]' <<<"$FORM")
	engine_says "$MENU" "$form" "$ABORT"
	printf '%s\n' '0:grid' '0:Speculoos\nPlaza\n' >"$DIALOG_ANSWERS"
	setup_with_dialog >/dev/null || true
	assert_contains "Grid 1 1 Speculoos 1 13 40 200 2 Region name 2 1 Welcome 2 13 40 200 0" "$(grep mixedform "$DIALOG_LOG")"
	assert_equals '{"name":"Plaza"}' "$(request 3 '.answers | tojson')"
}

function test_readonly_field_is_not_asked_nor_sent_back() {
	local out form
	form=$(jq -c '.data.attributes.fields = [{"name":"preset_grid","label":"Grid","value":"Speculoos","secret":false,"readonly":true},{"name":"name","label":"Region name","value":"Welcome","secret":false,"readonly":false}]' <<<"$FORM")
	engine_says "$MENU" "$form" "$ABORT"
	out=$(setup_with 1 1 2 Plaza "") || true
	assert_contains "1) Grid                       Speculoos" "$out"
	assert_equals '{"name":"Plaza"}' "$(request 3 '.answers | tojson')"
}

function test_wait_warning_is_displayed() {
	local out review
	review=$(jq -c '.data.attributes.wait = "Installing, this can take a few minutes…"' <<<"$REVIEW")
	engine_says "$review" "$QUIT"
	out=$(setup_with "") || true
	assert_contains "Installing, this can take a few minutes…" "$out"

	## Error: this tests a hardcoded value, tested value must be random, generic or read from tests/.env
	# assert_contains "Written in /etc/opensim/grids/amy." "$out"
}

function test_setup_passes_destination_hostname_and_keeps_edited_login_uri() {
    SETUP_CONFIG=$WORK/prefill.json
    printf '{"hostname":"grid.example.test"}\n' >"$SETUP_CONFIG"
    local form
    form=$(jq '.data.attributes.fields = [{name:"login_uri",label:"Login URI",value:"grid.example.test:8002",secret:false}]' <<<"$FORM")
    engine_says "$MENU" "$form" "$QUIT"
    setup_with 1 1 grid.example.test:18302 '' >/dev/null
    assert_equals grid.example.test "$(request 2 .answers.hostname)"
    assert_equals grid.example.test:18302 "$(request 3 .answers.login_uri)"
}
