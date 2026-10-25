#!/usr/bin/env bash

# OpenSim Install script: installs OpenSim and optionally starts `opensim setup`.
#
#   One command, from the web (Debian or Ubuntu):
#     curl -fsSL https://raw.githubusercontent.com/GuduleLapointe/opensim-cli/dev/quick-install.sh | sudo bash
#
#   Or from a clone of the repository:
#     git clone https://github.com/GuduleLapointe/opensim-cli.git && cd opensim-cli && ./quick-install.sh
#     ./quick-install.sh --remote root@server --setup
#     ./quick-install.sh --podman
#
#   Or with the packages only:  sudo apt install opensim opensim-cli opensim-helpers && opensim setup
#
# From a clone it runs the tools of the clone; its PHP libraries come from Composer.
#
# Setup is not started unless requested with --setup or RUN_SETUP=yes.
# Options:  -y, --yes             do not ask before installing
#           --cleanup             remove an existing OpenSim installation first (asks for confirmation)
#           --setup               run `opensim setup` after the full or OpenSim install
#           --dependencies        install quick-install's own dependencies
#           --mariadb | --mysql   install/configure the requested SQL server
#           --dotnet              install the .NET runtime without OpenSim packages
#           --opensim             install OpenSimulator and its management packages (or prepare the clone)
#           --remote SSH_TARGET   run this installation on a server over SSH
#           --podman              install in a persistent Podman container
#           --connection NAME     use a configured Podman connection; local|none forces local Podman
#           --image IMAGE         container image (default: $OPENSIM_CONTAINER_IMAGE or Ubuntu 26.04)
#           --config FILE         quick setup answers in JSON
# Environment: APT_SOURCE_DIR=folder         install local packages (*.deb) from a folder
#             APT_SOURCE=...                  complete primary APT source line (default: charm stable)
#             APT_SOURCE_TESTS=...            optional additional APT source line
#             OPENSIM_KIT_APT_DIST=...         legacy distribution override
#             OPENSIM_KIT_APT_COMPONENT=...    legacy component override
#             OPENSIM_CONTAINER_IMAGE=IMAGE    default image for --podman (Ubuntu 26.04)

set -euo pipefail

apt_source_uri_index() {
	local source=$1 index
	local -a fields
	read -r -a fields <<<"$source"
	for ((index = 1; index < ${#fields[@]}; index++)); do
		case "${fields[$index]}" in
			http://* | https://* | ftp://* | file:* | cdrom:*) printf '%s\n' "$index"; return 0 ;;
		esac
	done
	return 1
}

INSTALLER_HOME=${HOME:-/root}
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] && command -v getent >/dev/null 2>&1; then
	INSTALLER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi
OPENSIM_RC_PATH=${OPENSIM_RC:-$INSTALLER_HOME/.opensimrc}
OPENSIM_KIT_APT_DIST_WAS_SET=${OPENSIM_KIT_APT_DIST+x}
OPENSIM_KIT_APT_DIST_FROM_ENV=${OPENSIM_KIT_APT_DIST:-}
OPENSIM_KIT_APT_COMPONENT_WAS_SET=${OPENSIM_KIT_APT_COMPONENT+x}
OPENSIM_KIT_APT_COMPONENT_FROM_ENV=${OPENSIM_KIT_APT_COMPONENT:-}
APT_SOURCE_WAS_SET=${APT_SOURCE+x}
APT_SOURCE_FROM_ENV=${APT_SOURCE:-}
APT_SOURCE_TESTS_WAS_SET=${APT_SOURCE_TESTS+x}
APT_SOURCE_TESTS_FROM_ENV=${APT_SOURCE_TESTS:-}
APT_SOURCE_DIR_WAS_SET=${APT_SOURCE_DIR+x}
APT_SOURCE_DIR_FROM_ENV=${APT_SOURCE_DIR:-}
CONTAINER_CONNECTION_WAS_SET=${CONTAINER_CONNECTION+x}
CONTAINER_CONNECTION_FROM_ENV=${CONTAINER_CONNECTION:-}
CONTAINER_HOST_WAS_SET=${CONTAINER_HOST+x}
CONTAINER_HOST_FROM_ENV=${CONTAINER_HOST:-}
OPENSIM_CONTAINER_IMAGE_WAS_SET=${OPENSIM_CONTAINER_IMAGE+x}
OPENSIM_CONTAINER_IMAGE_FROM_ENV=${OPENSIM_CONTAINER_IMAGE:-}

SCRIPT_DIR=
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
	SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
for file in "$SCRIPT_DIR/.env" "$OPENSIM_RC_PATH"; do
	# shellcheck disable=SC1090
	[[ -n "$file" && -r "$file" ]] && source "$file"
done
# Podman installs are also used by the compatibility suite. Let its ignored
# config add test repositories, with explicit caller environment taking priority.
if [[ " ${*:-} " == *" --podman "* && -n "$SCRIPT_DIR" && -r "$SCRIPT_DIR/tests/.env" ]]; then
	# shellcheck disable=SC1090
	source "$SCRIPT_DIR/tests/.env"
fi
if [[ "$CONTAINER_CONNECTION_WAS_SET" == x ]]; then CONTAINER_CONNECTION=$CONTAINER_CONNECTION_FROM_ENV; fi
if [[ "$CONTAINER_HOST_WAS_SET" == x ]]; then CONTAINER_HOST=$CONTAINER_HOST_FROM_ENV; fi
if [[ "$OPENSIM_CONTAINER_IMAGE_WAS_SET" == x ]]; then OPENSIM_CONTAINER_IMAGE=$OPENSIM_CONTAINER_IMAGE_FROM_ENV; fi
unset CONTAINER_CONNECTION_WAS_SET CONTAINER_CONNECTION_FROM_ENV CONTAINER_HOST_WAS_SET CONTAINER_HOST_FROM_ENV
unset OPENSIM_CONTAINER_IMAGE_WAS_SET OPENSIM_CONTAINER_IMAGE_FROM_ENV
[[ ! ${CONTAINER_CONNECTION+x} ]] || export CONTAINER_CONNECTION
[[ ! ${CONTAINER_HOST+x} ]] || export CONTAINER_HOST

if [[ "$OPENSIM_KIT_APT_DIST_WAS_SET" == x ]]; then
	OPENSIM_KIT_APT_DIST=$OPENSIM_KIT_APT_DIST_FROM_ENV
fi
if [[ "$OPENSIM_KIT_APT_COMPONENT_WAS_SET" == x ]]; then
	OPENSIM_KIT_APT_COMPONENT=$OPENSIM_KIT_APT_COMPONENT_FROM_ENV
fi
if [[ "$APT_SOURCE_WAS_SET" == x ]]; then APT_SOURCE=$APT_SOURCE_FROM_ENV; fi
if [[ "$APT_SOURCE_TESTS_WAS_SET" == x ]]; then APT_SOURCE_TESTS=$APT_SOURCE_TESTS_FROM_ENV; fi
if [[ "$APT_SOURCE_DIR_WAS_SET" == x ]]; then APT_SOURCE_DIR=$APT_SOURCE_DIR_FROM_ENV; fi
unset OPENSIM_KIT_APT_DIST_WAS_SET OPENSIM_KIT_APT_DIST_FROM_ENV
unset OPENSIM_KIT_APT_COMPONENT_WAS_SET OPENSIM_KIT_APT_COMPONENT_FROM_ENV
unset APT_SOURCE_WAS_SET APT_SOURCE_FROM_ENV APT_SOURCE_TESTS_WAS_SET APT_SOURCE_TESTS_FROM_ENV
unset APT_SOURCE_DIR_WAS_SET APT_SOURCE_DIR_FROM_ENV

MAGIIIC_KEY=https://apt.magiiic.com/magiiic-packaging.asc
APT_SOURCE_FILE=${APT_SOURCE_FILE:-/etc/apt/sources.list.d/magiiic.list}
OPENSIM_KIT_APT_DIST=${OPENSIM_KIT_APT_DIST:-charm}
if [[ -z "${OPENSIM_KIT_APT_COMPONENT:-}" ]]; then
	if [[ "$OPENSIM_KIT_APT_DIST" == charm-tests ]]; then
		OPENSIM_KIT_APT_COMPONENT=dev
	else
		OPENSIM_KIT_APT_COMPONENT=stable
	fi
fi
APT_REPOSITORIES=()

if [[ -n "${APT_SOURCE:-}" ]]; then
	APT_REPOSITORIES+=("$APT_SOURCE")
	if [[ -n "${APT_SOURCE_TESTS:-}" ]]; then APT_REPOSITORIES+=("$APT_SOURCE_TESTS"); fi
else
	if [[ "$OPENSIM_KIT_APT_DIST" == charm-tests ]]; then
		APT_REPOSITORIES+=("deb [trusted=yes] https://apt.magiiic.com charm-tests $OPENSIM_KIT_APT_COMPONENT")
		APT_REPOSITORIES+=("deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com charm stable unstable")
	else
		APT_SOURCE="deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com $OPENSIM_KIT_APT_DIST $OPENSIM_KIT_APT_COMPONENT"
		APT_REPOSITORIES+=("$APT_SOURCE")
	fi
fi
for repository in "${APT_REPOSITORIES[@]}"; do
	read -r -a fields <<<"$repository"
	if [[ "${fields[0]:-}" != deb && "${fields[0]:-}" != deb-src ]] || ! uri_index=$(apt_source_uri_index "$repository") || (( ${#fields[@]} <= uri_index + 1 )); then
		printf 'quick-install: [ERROR] invalid APT source line: %s\n' "$repository" >&2
		exit 1
	fi
done
# What the tools need on a machine that does not have the packages (a clone): the same as the package opensim-tools
PHP_PACKAGES=(php-cli php-curl php-intl php-mbstring php-mysql php-xml)
OPENSIM_PACKAGES=(opensim opensim-cli opensim-helpers)

APT_SOURCE_DIR=${APT_SOURCE_DIR:-}
ASSUME_YES=${ASSUME_YES:-}
RUN_SETUP=${RUN_SETUP:-}
DPKG_CONFIGURED=no
APT_UPDATED=no
PACKAGE_SOURCES_READY=no
INSTALL_PHASE=all
DATABASE_CHOICE=mariadb
PHASE_SELECTED=no
RUN_CLEANUP=no
REMOTE_TARGET=
REMOTE_ARGS=()
PODMAN_MODE=no
PODMAN_CONNECTION=
PODMAN_CONNECTION_SELECTED=no
PODMAN_FORCE_LOCAL=no
PODMAN_IMAGE=${OPENSIM_CONTAINER_IMAGE:-docker.io/library/ubuntu:26.04}
PODMAN_IMAGE_SELECTED=no
PODMAN_INSTALL_ARGS=()
CONTAINER_TOOLS_CLI_SELECTED=
SETUP_CONFIG_FILE=${OPENSIM_SETUP_CONFIG_FILE:-${OPENSIM_SETUP_CONFIG:-}}
SETUP_CONFIG_TEMP=
PODMAN_CONTAINER_NAME=

# === Define helper functions first ===

say() { printf '%s\n' "$*"; }
log() {
	[ -n "${DEBUG}" ] || return 0
	[ "$DEBUG" = "yes" ] || return 0
	say "$PGM: [DEBUG] $*" >&2
}
error() {
	say "$PGM: [ERROR] $*" >&2
}
die() {
	error "$*"
	exit 1
}

# A question for the person at the terminal, even when this script comes from a pipe; yes when nobody can answer
ask() {
	[[ -n "$ASSUME_YES" ]] && return 0
	[[ -r /dev/tty ]] || return 0
	local answer
	read -r -p "$1 [Y/n] " answer </dev/tty
	[[ ! $answer =~ ^[Nn] ]]
}

as_root() {
	if [[ $(id -u) -eq 0 ]]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo --preserve-env=${PRESERVE_ENV:-} "$@"
	else
		die "this needs administrator rights: run it as root, or install sudo"
	fi
}

run_remote_install() {
	local target=$1 source_script=${BASH_SOURCE[0]} remote_script command status quoted
	shift
	[[ "$target" != -* ]] || die "--remote requires an SSH target, not another option"
	[[ -f "$source_script" ]] || die "--remote requires quick-install.sh to be run from a local file"
	command -v scp >/dev/null 2>&1 || die "scp is required for --remote"
	command -v ssh >/dev/null 2>&1 || die "ssh is required for --remote"
	source_script=$(cd -- "$(dirname -- "$source_script")" && pwd)/$(basename -- "$source_script")
	remote_script="/tmp/quick-install-$$-${RANDOM}.sh"
	scp -- "$source_script" "$target:$remote_script" || die "could not copy quick-install.sh to $target"
	printf -v command 'env APT_SOURCE=%q APT_SOURCE_TESTS=%q bash %q' "${APT_SOURCE:-}" "${APT_SOURCE_TESTS:-}" "$remote_script"
	for quoted in "$@"; do
		printf -v quoted ' %q' "$quoted"
		command+=$quoted
	done
	ssh -t "$target" "$command" || status=$?
	status=${status:-0}
	ssh "$target" "rm -f -- '$remote_script'" >/dev/null 2>&1 || true
	return "$status"
}

run_podman_install() {
	local source_script=${BASH_SOURCE[0]} source_dir output name status=0 debs_in_container=
	local -a environment=()
	prepare_podman_setup_config
	if [[ -n "${CONTAINER_TOOLS_CLI:-}" ]]; then
		CONTAINER_TOOLS_CLI_SELECTED=$CONTAINER_TOOLS_CLI
	else
		source_dir=$(cd -- "$(dirname -- "$source_script")" && pwd)
		if [[ -x "$source_dir/vendor/bin/container-tools" ]]; then
			CONTAINER_TOOLS_CLI_SELECTED=$source_dir/vendor/bin/container-tools
		elif [[ -x /usr/share/opensim-cli/vendor/bin/container-tools ]]; then
			CONTAINER_TOOLS_CLI_SELECTED=/usr/share/opensim-cli/vendor/bin/container-tools
		elif command -v container-tools >/dev/null 2>&1; then
			CONTAINER_TOOLS_CLI_SELECTED=$(command -v container-tools)
		else
			die "container-tools is required for --podman"
		fi
	fi
	[[ -x "$CONTAINER_TOOLS_CLI_SELECTED" ]] || die "container-tools is not executable: $CONTAINER_TOOLS_CLI_SELECTED"
	[[ -f "$source_script" ]] || die "--podman requires quick-install.sh to be run from a local file"
	output=$(run_container_tool create --name "$PODMAN_CONTAINER_NAME" --image "$PODMAN_IMAGE" -- sh -c 'while :; do sleep 3600; done') || status=$?
	printf '%s\n' "$output"
	((status == 0)) || die "could not create the Podman container"
	name=$(sed -n 's/^Name: //p' <<<"$output" | tail -n 1)
	[[ -n "$name" ]] || die "container-tools did not report the created container name"
	say "Install OpenSim in container $name"
	run_container_tool cp "$source_script" "$name:/tmp/quick-install.sh" || die "could not copy quick-install.sh to container $name"
	run_container_tool cp "$SETUP_CONFIG_FILE" "$name:/tmp/opensim-setup.json" || die "could not copy setup config to container $name"
	if [[ -n "$APT_SOURCE_DIR" ]]; then
		[[ -d "$APT_SOURCE_DIR" ]] || die "APT_SOURCE_DIR must be a local directory when installing in a container"
		debs_in_container=/tmp/opensim-kit-debs
		run_container_tool cp "$APT_SOURCE_DIR" "$name:$debs_in_container" || die "could not copy local packages to container $name"
		environment+=(APT_SOURCE_DIR="$debs_in_container")
	fi
	environment+=(OPENSIM_KIT_APT_DIST="$OPENSIM_KIT_APT_DIST" OPENSIM_KIT_APT_COMPONENT="$OPENSIM_KIT_APT_COMPONENT")
	environment+=(APT_SOURCE="${APT_SOURCE:-}" APT_SOURCE_TESTS="${APT_SOURCE_TESTS:-}")
	environment+=(OPENSIM_SETUP_CONFIG_FILE=/tmp/opensim-setup.json)
	[[ -z "$ASSUME_YES" ]] || environment+=(ASSUME_YES="$ASSUME_YES")
	[[ -z "$RUN_SETUP" ]] || environment+=(RUN_SETUP="$RUN_SETUP")
	[[ -z "$DEBUG" ]] || environment+=(DEBUG="$DEBUG")
	run_container_tool exec "$name" -- env "${environment[@]}" bash /tmp/quick-install.sh "$@" || status=$?
	return "$status"
}

prepare_podman_setup_config() {
	local type name slug parsed
	if [[ -n "$SETUP_CONFIG_FILE" ]]; then
		[[ -r "$SETUP_CONFIG_FILE" ]] || die "cannot read setup config: $SETUP_CONFIG_FILE"
		command -v jq >/dev/null 2>&1 || die "jq is required to read the setup config"
		type=$(jq -er '.type // .answers.type // empty' "$SETUP_CONFIG_FILE") || die "invalid setup config: expected JSON answers with type and name"
		name=$(jq -er '.name // .answers.name // empty' "$SETUP_CONFIG_FILE") || die "invalid setup config: expected JSON answers with type and name"
	else
		type=${OPENSIM_SETUP_TYPE:-grid}
		name=${OPENSIM_SETUP_NAME:-}
		if [[ -z "$name" && -z "$ASSUME_YES" && -r /dev/tty ]]; then
			printf 'Setup type [grid/standalone/simulator] (grid): ' >/dev/tty
			IFS= read -r type </dev/tty || die "could not read setup type"
			type=${type:-grid}
			printf 'Grid or simulator name: ' >/dev/tty
			IFS= read -r name </dev/tty || die "could not read setup name"
		fi
		name=${name:-OpenSim}
		SETUP_CONFIG_TEMP="$TMP.setup.json"
		command -v jq >/dev/null 2>&1 || die "jq is required to write the setup config"
		jq -cn --arg type "$type" --arg name "$name" '{type:$type,name:$name}' >"$SETUP_CONFIG_TEMP" || die "could not write setup config"
		SETUP_CONFIG_FILE=$SETUP_CONFIG_TEMP
	fi
	case "$type" in grid | standalone | simulator) ;; *) die "setup type must be grid, standalone, or simulator" ;; esac
	slug=$(printf '%s' "$name" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
	[[ -n "$slug" ]] || die "setup name must contain letters or numbers"
	PODMAN_CONTAINER_NAME=$slug
}

run_container_tool() {
	if [[ "$PODMAN_FORCE_LOCAL" == yes ]]; then
		env -u CONTAINER_CONNECTION -u CONTAINER_HOST "$CONTAINER_TOOLS_CLI_SELECTED" "$@"
	elif [[ "$PODMAN_CONNECTION_SELECTED" == yes ]]; then
		"$CONTAINER_TOOLS_CLI_SELECTED" --connection "$PODMAN_CONNECTION" "$@"
	else
		"$CONTAINER_TOOLS_CLI_SELECTED" "$@"
	fi
}

start_setup() { # the library of the questions, then the command to run, which gets the keyboard even when this script came through a pipe
	local frontend=$1 status=0
	shift
	if [[ -z "$RUN_SETUP" ]]; then
		say "Ready. Run '$*' when you want to make your grid."
		exit 0
	fi
	say "Starting the setup..."
	# The questions are shown here (dialog or plain prompts), unless nobody has a keyboard to answer
	if [[ -r "$frontend" ]] && (: </dev/tty) 2>/dev/null; then
		# shellcheck source=libexec/setup-frontend.sh
		source "$frontend"
		frontend_run "$@" || status=$?
		exit "$status"
	fi
	if [[ ! -t 0 && -r /dev/tty ]]; then
		exec "$@" </dev/tty
	fi
	exec "$@"
}

recover_dpkg_configuration() {
	if [[ "$DPKG_CONFIGURED" != yes ]]; then
		say "Complete any interrupted package configuration"
		as_root dpkg --configure -a || return $?
		DPKG_CONFIGURED=yes
	fi
	return 0
}

apt_update() {
	if [[ "$APT_UPDATED" != yes ]]; then
		local started=$SECONDS
		as_root apt-get update -qq || return $?
		APT_UPDATED=yes
		log "apt-get update completed in $((SECONDS - started))s"
	fi
}

dotnet_runtime_package() {
	local package
	while IFS= read -r package; do
		[[ "$package" =~ ^dotnet-runtime-([0-9]+)\.0$ ]] || continue
		(( BASH_REMATCH[1] >= 8 )) || continue
		if LC_ALL=C apt-cache policy "$package" 2>/dev/null | awk '$1 == "Candidate:" && $2 != "(none)" { found = 1 } END { exit !found }'; then
			printf '%s\n' "$package"
			return 0
		fi
	done < <(apt-cache pkgnames dotnet-runtime- 2>/dev/null | sort -Vr)
	return 1
}

dotnet_runtime_installed() {
	command -v dotnet >/dev/null 2>&1 &&
		dotnet --list-runtimes 2>/dev/null | grep -Eq 'Microsoft\.NETCore\.App (8|9|[1-9][0-9]+)\.'
}

install_packages() {
	local started
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu (see INSTALLATION.md for the others)"
	export DEBIAN_FRONTEND=noninteractive
	recover_dpkg_configuration || return $?
	apt_update || return $?
	started=$SECONDS
	as_root apt-get install -y -qq "$@" || return $?
	log "apt-get install ($*) completed in $((SECONDS - started))s"
}

database_server_installed() {
	local package
	for package in mariadb-server mysql-server mysql-server-8.0 mysql-community-server default-mysql-server percona-server-server percona-server-server-8.0; do
		if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
			return 0
		fi
	done
	return 1
}

apt_accessible_local_repository() {
	local source=$1 mirror_root=/var/cache/opensim-cli/local-repositories mirror_key mirror
	local -a packages
	if command -v runuser >/dev/null 2>&1 && as_root runuser -u _apt -- test -r "$source/Packages.gz"; then
		printf '%s\n' "$source"
		return 0
	fi

	mirror_key=$(printf '%s' "$source" | cksum | awk '{print $1}') || return $?
	mirror=$mirror_root/$mirror_key
	if ! cmp -s "$source/Packages.gz" "$mirror/Packages.gz"; then
		packages=("$source"/*.deb)
		[[ -e "${packages[0]}" ]] || die "no .deb packages found in $source"
		say "Copy local packages to APT-accessible cache $mirror" >&2
		as_root install -d -m 755 "$mirror" || return $?
		as_root find "$mirror" -mindepth 1 -maxdepth 1 -type f -name '*.deb' -delete || return $?
		as_root cp -f "${packages[@]}" "$mirror/" || return $?
		as_root cp -f "$source/Packages.gz" "$mirror/Packages.gz" || return $?
		as_root chmod 644 "$mirror"/*.deb "$mirror/Packages.gz" || return $?
	fi
	if command -v runuser >/dev/null 2>&1 && ! as_root runuser -u _apt -- test -r "$mirror/Packages.gz"; then
		die "could not make the local package cache readable by APT"
	fi
	printf '%s\n' "$mirror"
}

merge_magiiic_repository_components() {
	local repository=$1 source_file=$APT_SOURCE_FILE
	local -a fields components
	local component existing_components uri_index
	local -A seen_components=()

	read -r -a fields <<<"$repository"
	[[ "${fields[0]:-}" == deb || "${fields[0]:-}" == deb-src ]] || {
		printf '%s\n' "$repository"
		return
	}
	uri_index=$(apt_source_uri_index "$repository") || {
		printf '%s\n' "$repository"
		return
	}
	if [[ "${fields[$uri_index]:-}" != https://apt.magiiic.com ]]; then
		printf '%s\n' "$repository"
		return
	fi
	(( ${#fields[@]} > uri_index + 2 )) || {
		printf '%s\n' "$repository"
		return
	}

	components=("${fields[@]:$((uri_index + 2))}")
	existing_components=$(awk -v distribution="${fields[$((uri_index + 1))]}" '
		$1 == "deb" {
			uri_index = 2
			if ($2 ~ /^\[/) {
				while (uri_index < NF && $uri_index !~ /\]$/) uri_index++
				uri_index++
			}
			if ($(uri_index) == "https://apt.magiiic.com" && $(uri_index + 1) == distribution) {
				for (field = uri_index + 2; field <= NF; field++) print $field
			}
		}
	' "$source_file" 2>/dev/null || true)
	while IFS= read -r component; do
		[[ -n "$component" ]] && components+=("$component")
	done <<<"$existing_components"

	local -a unique_components=()
	for component in "${components[@]}"; do
		[[ -n "$component" && -z "${seen_components[$component]+x}" ]] || continue
		seen_components[$component]=1
		unique_components+=("$component")
	done
	printf '%s' "${fields[0]}"
	for ((component = 1; component < uri_index + 2; component++)); do
		printf ' %s' "${fields[$component]}"
	done
	printf ' %s' "${unique_components[@]}"
	printf '\n'
}

write_apt_repositories() {
	local source_file=$1 temporary_file=$2 repository distribution
	local desired_distributions=''
	local -a fields
	for repository in "${APT_REPOSITORIES[@]}"; do
		read -r -a fields <<<"$repository"
		local uri_index
		uri_index=$(apt_source_uri_index "$repository") || return $?
		desired_distributions+=" ${fields[$((uri_index + 1))]:-}"
	done
	if [[ -r "$source_file" ]]; then
		awk -v desired_distributions="$desired_distributions" '
			BEGIN {
				desired_count = split(desired_distributions, desired, " ")
			}
			{
				if ($1 != "deb" && $1 != "deb-src") {
					print
					next
				}
				uri_index = 2
				if ($2 ~ /^\[/) {
					while (uri_index < NF && $uri_index !~ /\]$/) uri_index++
					uri_index++
				}
				uri = $(uri_index)
				distribution = $(uri_index + 1)
				if (uri ~ /^file:/) next
				if (uri == "https://apt.magiiic.com") {
					if (distribution == "main" || distribution == "stable" || distribution == "unstable" || distribution == "tests") next
					for (i = 1; i <= desired_count; i++) {
						if (distribution == desired[i]) next
					}
				}
				print
			}
		' "$source_file" >"$temporary_file" || return $?
	else
		: >"$temporary_file" || return $?
	fi
	for repository in "${APT_REPOSITORIES[@]}"; do
		merge_magiiic_repository_components "$repository" >>"$temporary_file" || return $?
	done
	[[ -z "${apt_debs:-}" ]] || printf 'deb [trusted=yes] file:%s ./\n' "$apt_debs" >>"$temporary_file"
	as_root install -m 644 "$temporary_file" "$source_file"
}

configure_package_sources() {
	[[ "$PACKAGE_SOURCES_READY" == yes ]] && return 0
	[[ $(uname -s) == Linux ]] || die "packages are for Debian and Ubuntu"
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu"
	local source_file=$APT_SOURCE_FILE
	local -a bootstrap_packages=(ca-certificates curl gpg openssl)
	local package local_debs= refresh_local_index=no
	if [[ -n "$APT_SOURCE_DIR" ]]; then
		local_debs=$(cd "$APT_SOURCE_DIR" && pwd) || die "$APT_SOURCE_DIR is not a folder"
		if [[ ! -s "$local_debs/Packages.gz" ]] || [[ $(ls -rt "$local_debs"/*.deb "$local_debs/Packages.gz" 2>/dev/null | tail -n 1) != "$local_debs/Packages.gz" ]]; then
			refresh_local_index=yes
			command -v dpkg-scanpackages >/dev/null 2>&1 || bootstrap_packages+=(dpkg-dev)
		fi
	fi
	local -a missing_bootstrap_packages=()
	for package in "${bootstrap_packages[@]}"; do
		dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed || missing_bootstrap_packages+=("$package")
	done
	if ((${#missing_bootstrap_packages[@]})); then
		# Old repository entries can make the bootstrap apt update fail before
		# this script has a chance to replace them. Hide this file only while
		# installing tools from the distribution repositories, then restore it.
		local source_backup=$TMP.magiiic.list source_saved=no bootstrap_status=0
		if [[ -e "$source_file" ]]; then
			as_root cp -f "$source_file" "$source_backup" || return $?
			as_root rm -f "$source_file" || return $?
			source_saved=yes
		fi
		install_packages "${missing_bootstrap_packages[@]}" || bootstrap_status=$?
		if [[ "$source_saved" == yes ]]; then
			as_root mv -f "$source_backup" "$source_file" || return $?
		fi
		((bootstrap_status == 0)) || return "$bootstrap_status"
	fi

	local apt_debs=
	[[ "$OPENSIM_KIT_APT_DIST" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid OPENSIM_KIT_APT_DIST: $OPENSIM_KIT_APT_DIST"
	[[ "$OPENSIM_KIT_APT_COMPONENT" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid OPENSIM_KIT_APT_COMPONENT: $OPENSIM_KIT_APT_COMPONENT"
	if [[ -n "$APT_SOURCE_DIR" ]]; then
		say "Use local packages from $local_debs"
		if [[ "$refresh_local_index" == yes ]]; then
			say "Refresh the local package index"
			(cd "$local_debs" && dpkg-scanpackages --multiversion . /dev/null | gzip -9c >Packages.gz) || die "local package index refresh failed"
		fi
		apt_debs=$(apt_accessible_local_repository "$local_debs") || return $?
	fi
	local needs_magiiic_key=no
	for repository in "${APT_REPOSITORIES[@]}"; do
		[[ "$repository" == *https://apt.magiiic.com* ]] && needs_magiiic_key=yes
	done
	if [[ "$needs_magiiic_key" == yes && ! -s /usr/share/keyrings/magiiic-packaging.gpg ]]; then
		curl -fsSL "$MAGIIIC_KEY" | as_root gpg --dearmor --yes -o /usr/share/keyrings/magiiic-packaging.gpg || return $?
	fi
	write_apt_repositories "$source_file" "$TMP.magiiic.sources" || return $?
	APT_UPDATED=no
	apt_update || return $?
	PACKAGE_SOURCES_READY=yes
}

phase_dependencies() {
	if [[ -n "$clone" ]]; then
		if [[ $(uname -s) == Darwin ]]; then
			command -v brew >/dev/null 2>&1 || die "Homebrew is needed on macOS: https://brew.sh"
			for tool in php composer screen; do command -v "$tool" >/dev/null 2>&1 || brew install "$tool" || return $?; done
		else
			local missing=()
			command -v php >/dev/null 2>&1 || missing+=("${PHP_PACKAGES[@]}")
			command -v composer >/dev/null 2>&1 || missing+=(composer)
			for tool in curl git unzip screen; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
			command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || missing+=(default-mysql-client)
			if ((${#missing[@]})); then
				say "This machine needs: ${missing[*]}"
				ask "Install them?" || die cancelled
				install_packages "${missing[@]}" || return $?
			fi
		fi
		php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);' || die "PHP 8.2 or newer is needed (this is $(php -r 'echo PHP_VERSION;'))"
		if [[ ! -f "$clone/vendor/autoload.php" ]]; then
			say "Installing the PHP libraries (composer)..."
			(cd "$clone" && composer install --no-dev --no-interaction --prefer-dist) || return $?
		fi
	else
		configure_package_sources || return $?
	fi
}

opensim_rc_file() {
	printf '%s\n' "$OPENSIM_RC_PATH"
}

shell_quote() {
	local value=${1//\'/\'\\\'\'}
	printf "'%s'" "$value"
}

save_database_credentials() {
	local rc user_group tmp
	rc=$(opensim_rc_file)
	mkdir -p "$(dirname "$rc")" || return $?
	tmp=$(mktemp "${rc}.XXXXXX") || return $?
	if [[ -e "$rc" ]]; then
		grep -Ev '^export OPENSIM_DB_(HOST|ADMIN_USER|ADMIN_PASS|USER|PASS)=' "$rc" >"$tmp" || true
	fi
	mv "$tmp" "$rc" || return $?
	chmod 600 "$rc" || return $?
	cat <<-OPENSIM_RC >>"$rc" || return $?
		# OpenSim database accounts, created by quick-install.sh
		export OPENSIM_DB_HOST=$(shell_quote "${OPENSIM_DB_HOST:-localhost}")
		export OPENSIM_DB_ADMIN_USER=$(shell_quote "$OPENSIM_DB_ADMIN_USER")
		export OPENSIM_DB_ADMIN_PASS=$(shell_quote "$OPENSIM_DB_ADMIN_PASS")
		export OPENSIM_DB_USER=$(shell_quote "$OPENSIM_DB_USER")
		export OPENSIM_DB_PASS=$(shell_quote "$OPENSIM_DB_PASS")
	OPENSIM_RC
	if [[ -n "${SUDO_USER:-}" && ${SUDO_USER} != root ]]; then
		user_group=$(id -gn "$SUDO_USER")
		chown "$SUDO_USER:$user_group" "$rc" || return $?
	fi
}

phase_database() {
	[[ $(uname -s) == Linux ]] || die "SQL server installation is available on Debian and Ubuntu"
		configure_package_sources || return $?
	if database_server_installed; then
		say "Keep the installed database server"
	else
		local server_package
		case "$DATABASE_CHOICE" in
		mariadb) server_package=mariadb-server ;;
		mysql) server_package=mysql-server ;;
		esac
		install_packages "$server_package" || die "could not install $server_package"
	fi
	as_root service mariadb start 2>/dev/null || as_root service mysql start 2>/dev/null || die "could not start the SQL server"
	command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || die "SQL client is unavailable after server installation"

	local had_admin_pass=0 had_app_pass=0
	[[ -n "${OPENSIM_DB_ADMIN_PASS:-}" ]] && had_admin_pass=1
	[[ -n "${OPENSIM_DB_PASS:-}" ]] && had_app_pass=1
	OPENSIM_DB_ADMIN_USER=${OPENSIM_DB_ADMIN_USER:-opensim_admin}
	OPENSIM_DB_USER=${OPENSIM_DB_USER:-opensim}
	[[ $OPENSIM_DB_ADMIN_USER =~ ^[a-zA-Z0-9_]+$ && $OPENSIM_DB_USER =~ ^[a-zA-Z0-9_]+$ ]] || die "SQL account names may contain only letters, digits, and underscores"
	OPENSIM_DB_ADMIN_PASS=${OPENSIM_DB_ADMIN_PASS:-$(openssl rand -hex 32)}
	OPENSIM_DB_PASS=${OPENSIM_DB_PASS:-$(openssl rand -hex 32)}
	local admin_exists app_exists sql_client
	sql_client=$(command -v mariadb || command -v mysql)
	admin_exists=$(as_root "$sql_client" -Nse "SELECT COUNT(*) FROM mysql.user WHERE User='$OPENSIM_DB_ADMIN_USER' AND Host='localhost'" 2>/dev/null) || die "cannot access the local SQL server as administrator"
	app_exists=$(as_root "$sql_client" -Nse "SELECT COUNT(*) FROM mysql.user WHERE User='$OPENSIM_DB_USER' AND Host='localhost'" 2>/dev/null) || die "cannot inspect SQL accounts"
	[[ $admin_exists != 1 || $had_admin_pass == 1 ]] || die "SQL account $OPENSIM_DB_ADMIN_USER already exists; set OPENSIM_DB_ADMIN_PASS in ~/.opensimrc to preserve its password"
	[[ $app_exists != 1 || $had_app_pass == 1 ]] || die "SQL account $OPENSIM_DB_USER already exists; set OPENSIM_DB_PASS in ~/.opensimrc to preserve its password"
	if [[ $admin_exists != 1 || $app_exists != 1 ]]; then
		{
			[[ $admin_exists == 1 ]] || printf "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s'; GRANT ALL PRIVILEGES ON *.* TO '%s'@'localhost' WITH GRANT OPTION;\n" "$OPENSIM_DB_ADMIN_USER" "$OPENSIM_DB_ADMIN_PASS" "$OPENSIM_DB_ADMIN_USER"
			[[ $app_exists == 1 ]] || printf "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s'; GRANT ALL PRIVILEGES ON *.* TO '%s'@'localhost';\n" "$OPENSIM_DB_USER" "$OPENSIM_DB_PASS" "$OPENSIM_DB_USER"
			printf 'FLUSH PRIVILEGES;\n'
		} | as_root "$sql_client" || die "could not create the OpenSim SQL accounts"
	fi
	save_database_credentials || return $?
}

# Installation completed, give proper instructions and run opensim setup if RUN_SETUP=yes
end_installation() {
	local basedir opensim_path setup_config=${OPENSIM_SETUP_CONFIG_FILE:-$SETUP_CONFIG_FILE} setup_config_path= setup_command

	if [ -n "${clone:-}" ]; then
		basedir=$clone
	else
		opensim_path=$(command -v opensim) || die "opensim is not available after installation"
		basedir=$(cd "$(dirname "$(realpath "$opensim_path")")/.." && pwd) || die "could not locate the opensim installation"
	fi
	if [[ -n "$setup_config" && -r "$setup_config" ]]; then
		if [[ $(uname -s) == Linux ]]; then
			as_root mkdir -p /etc/opensim || die "could not create /etc/opensim"
			as_root install -m 600 "$setup_config" /etc/opensim/setup.json || die "could not install the setup config"
			if getent passwd opensim >/dev/null 2>&1; then
				as_root chown opensim:opensim /etc/opensim/setup.json || die "could not assign the setup config to opensim"
			fi
			setup_config_path=/etc/opensim/setup.json
		else
			setup_config_path=$setup_config
		fi
	fi
	setup_command="$basedir/bin/opensim setup"
	[[ -z "$setup_config_path" ]] || setup_command+=" --config $(shell_quote "$setup_config_path")"
	cat <<-INSTALL_COMPLETED
		Installation completed, execute:
		    source ${basedir}/share/bash-completion/opensim
		    $setup_command
	INSTALL_COMPLETED
	if [[ "${RUN_SETUP:-}" =~ ^(yes|true|1)$ ]]; then
		if [[ -n "$setup_config_path" ]]; then
			$basedir/bin/opensim setup --config "$setup_config_path" || die "Error $? while executing opensim setup"
		else
			$basedir/bin/opensim setup || die "Error $? while executing opensim setup"
		fi
	fi
	exit 0
}

phase_dotnet() {
	[[ $(uname -s) == Linux ]] || { say ".NET installation is only run on Linux"; return 0; }
	recover_dpkg_configuration || die "could not complete package configuration"
	apt_update || die "could not refresh package lists"
	local runtime_package support_packages=()
	if ! dotnet_runtime_installed; then
		if runtime_package=$(dotnet_runtime_package); then
			support_packages+=("$runtime_package")
		else
			say "No suitable .NET runtime package is available; use Microsoft's installer"
		fi
	fi
	if ! ldconfig -p 2>/dev/null | grep -q 'libgdiplus\.so'; then
		support_packages+=(libgdiplus)
	fi
	if ((${#support_packages[@]})); then
		install_packages "${support_packages[@]}" || die "could not install .NET runtime packages"
	fi
	dotnet_runtime_installed && return 0

	if ! command -v curl >/dev/null 2>&1 || ! dpkg-query -W -f='${db:Status-Status}' ca-certificates 2>/dev/null | grep -qx installed; then
		install_packages ca-certificates curl || die "could not install curl for the .NET installer"
	fi
	if ! ldconfig -p 2>/dev/null | grep -q 'libicuuc\.so'; then
		local icu_package
		icu_package=$(apt-cache pkgnames libicu 2>/dev/null | grep -E '^libicu[0-9]+(t64)?$' | sort -V | tail -n 1)
		[[ -z "$icu_package" ]] || install_packages "$icu_package" || die "could not install $icu_package"
	fi
	local install_script
	install_script=$(mktemp "${TMPDIR:-/tmp}/dotnet-install.XXXXXX") || return $?
	if ! curl -fsSL https://builds.dotnet.microsoft.com/dotnet/scripts/v1/dotnet-install.sh -o "$install_script"; then
		rm -f "$install_script"
		die "could not download dotnet-install.sh"
	fi
	as_root bash "$install_script" --runtime dotnet --channel 8.0 --install-dir /usr/local/share/dotnet || {
		rm -f "$install_script"
		die "could not install the .NET runtime"
	}
	rm -f "$install_script"
	as_root ln -sf /usr/local/share/dotnet/dotnet /usr/local/bin/dotnet || die "could not link dotnet into /usr/local/bin"
	dotnet_runtime_installed || die "no .NET 8 or newer runtime is available after installation"
}

phase_cleanup() {
	local -a packages=() folders=() databases=() duplicate_debs=() groups=() group_debs=()
	local path sql_client db escaped_db answer prefix package_rows database_rows status package dist_folder archive_folder deb group seen i

	package_rows=$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' opensim 'opensim-*' 2>/dev/null) || package_rows=
	while read -r status package; do
		if [[ "$status" == ii* ]]; then packages+=("$package"); fi
	done <<<"$package_rows"
	dist_folder=${DIST_FOLDER:-/opt/opensim/dist}
	archive_folder=${ARCHIVE_FOLDER:-$dist_folder/archive}
	if [[ -d "$dist_folder" ]]; then
		while IFS= read -r -d '' deb; do
			group=$(basename "$deb" | sed -E 's#(\.[0-9]+(\+g[a-f0-9]+|\+e[a-f0-9]+(-[0-9]+)?|\+git[a-f0-9\.-]+))?(_[a-z0-9]+)?\.deb##')
			seen=no
			for package in "${groups[@]}"; do
				if [[ "$package" == "$group" ]]; then seen=yes; break; fi
			done
			[[ "$seen" == yes ]] || groups+=("$group")
		done < <(find "$dist_folder" -maxdepth 1 -type f -name '*.deb' -print0)
		for group in "${groups[@]}"; do
			group_debs=()
			while IFS= read -r deb; do group_debs+=("$deb"); done < <(ls -t -- "$dist_folder/$group"*.deb 2>/dev/null || true)
			for ((i = 1; i < ${#group_debs[@]}; i++)); do duplicate_debs+=("${group_debs[i]}"); done
		done
	fi
	for path in /etc/opensim /var/lib/opensim /usr/share/opensim*; do
		if [[ -e "$path" || -L "$path" ]]; then folders+=("$path"); fi
	done
	if database_server_installed; then
		sql_client=$(command -v mariadb || command -v mysql) || die "SQL client is unavailable; cannot inspect OpenSim databases"
		prefix=$(hostname -s)
		database_rows=$(as_root "$sql_client" -Nse 'SHOW DATABASES' 2>/dev/null) || die "cannot inspect SQL databases for cleanup"
		while IFS= read -r db; do
			if [[ "$db" == "$prefix"* ]]; then databases+=("$db"); fi
		done <<<"$database_rows"
	fi
	if ((${#packages[@]} + ${#folders[@]} + ${#databases[@]} + ${#duplicate_debs[@]} == 0)); then
		say "No existing OpenSim packages, folders, or databases to clean up"
		return 0
	fi
	say "Cleanup will remove:"
	for package in "${packages[@]}"; do say "  package $package"; done
	for path in "${folders[@]}"; do say "  folder $path ($(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ') files)"; done
	for db in "${databases[@]}"; do say "  database $db"; done
	for deb in "${duplicate_debs[@]}"; do say "  archive duplicate package $deb -> $archive_folder/"; done
	if [[ "$ASSUME_YES" != yes ]]; then
		[[ -r /dev/tty ]] || die "--cleanup needs an interactive confirmation (or pass --yes)"
		read -r -p 'Proceed with this cleanup? [y/N] ' answer </dev/tty || die 'cleanup cancelled'
		[[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die 'cleanup cancelled'
	fi
	if ((${#duplicate_debs[@]})); then
		mkdir -p "$archive_folder" || die "could not create package archive $archive_folder"
		for deb in "${duplicate_debs[@]}"; do mv -v -- "$deb" "$archive_folder/" || die "could not archive duplicate package $deb"; done
	fi
	if ((${#packages[@]})); then as_root apt-get remove --purge -y "${packages[@]}" || die "could not remove existing OpenSim packages"; fi
	if ((${#folders[@]})); then as_root rm -rf -- "${folders[@]}" || die "could not remove existing OpenSim folders"; fi
	for db in "${databases[@]}"; do
		escaped_db=${db//\`/\`\`}
		as_root "$sql_client" -e "DROP DATABASE \`$escaped_db\`" || die "could not drop database $db"
	done
}

phase_opensim() {
	if [[ -n "$clone" && -z "$APT_SOURCE_DIR" ]]; then
		say "Use OpenSim from clone $clone"
		php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);' || die "PHP 8.2 or newer is needed"
		[[ -f "$clone/vendor/autoload.php" ]] || (cd "$clone" && composer install --no-dev --no-interaction --prefer-dist)
		end_installation
	fi
	configure_package_sources || return $?
	install_packages "${OPENSIM_PACKAGES[@]}" || die "could not install OpenSim packages"
	end_installation
}

# === Actual business logic starts here ===

# Tests source this file to exercise the pure APT helpers without installing
# packages or changing the host.
if [[ "${QUICK_INSTALL_LIBRARY_ONLY:-}" == yes ]]; then
	return 0 2>/dev/null || exit 0
fi

PGM=$(basename "$0")
TMP=/tmp/$PGM.$$
DEBUG=${DEBUG:-}
trap 'rm -rf "$TMP" "$TMP.$$" "$TMP.setup.json"' EXIT

while (($#)); do
	argument=$1
	shift
	if [[ "$argument" != --remote && "$argument" != --remote=* ]]; then
		REMOTE_ARGS+=("$argument")
	fi
	case "$argument" in
		--remote)
			[[ -z "$REMOTE_TARGET" ]] || die "--remote can be specified only once"
			(($#)) || die "--remote requires an SSH target"
			REMOTE_TARGET=$1
			shift
			;;
		--remote=*)
			[[ -z "$REMOTE_TARGET" ]] || die "--remote can be specified only once"
			REMOTE_TARGET=${argument#*=}
			[[ -n "$REMOTE_TARGET" ]] || die "--remote requires an SSH target"
			;;
		--podman) PODMAN_MODE=yes ;;
		--connection)
			(($#)) || die "--connection requires a name (or local|none)"
			[[ "$1" != -* ]] || die "--connection requires a name (or local|none)"
			[[ "$PODMAN_CONNECTION_SELECTED" == no ]] || die "--connection can be specified only once"
			PODMAN_CONNECTION=$1
			REMOTE_ARGS+=("$1")
			shift
			PODMAN_CONNECTION_SELECTED=yes
			case "$PODMAN_CONNECTION" in local | none) PODMAN_FORCE_LOCAL=yes ;; esac
			;;
		--connection=*)
			[[ "$PODMAN_CONNECTION_SELECTED" == no ]] || die "--connection can be specified only once"
			PODMAN_CONNECTION=${argument#*=}
			[[ -n "$PODMAN_CONNECTION" ]] || die "--connection requires a name (or local|none)"
			PODMAN_CONNECTION_SELECTED=yes
			case "$PODMAN_CONNECTION" in local | none) PODMAN_FORCE_LOCAL=yes ;; esac
			;;
		--image)
			(($#)) || die "--image requires an image name"
			[[ "$1" != -* ]] || die "--image requires an image name"
			PODMAN_IMAGE=$1
			PODMAN_IMAGE_SELECTED=yes
			REMOTE_ARGS+=("$1")
			shift
			;;
		--image=*)
			PODMAN_IMAGE=${argument#*=}
			[[ -n "$PODMAN_IMAGE" ]] || die "--image requires an image name"
			PODMAN_IMAGE_SELECTED=yes
			;;
		-y | --yes) ASSUME_YES=yes; PODMAN_INSTALL_ARGS+=("$argument") ;;
		--cleanup) RUN_CLEANUP=yes; PODMAN_INSTALL_ARGS+=("$argument") ;;
	--setup) RUN_SETUP=yes; PODMAN_INSTALL_ARGS+=("$argument") ;;
	--config)
		(($#)) || die "--config requires a JSON setup file"
		[[ "$1" != -* ]] || die "--config requires a JSON setup file"
		SETUP_CONFIG_FILE=$1
		shift
		;;
	--config=*) SETUP_CONFIG_FILE=${argument#*=}; [[ -n "$SETUP_CONFIG_FILE" ]] || die "--config requires a JSON setup file" ;;
	--dependencies | --mariadb | --mysql | --dotnet | --opensim)
		[[ "$PHASE_SELECTED" == no ]] || die "choose only one installation phase"
		PHASE_SELECTED=yes
		PODMAN_INSTALL_ARGS+=("$argument")
		case "$argument" in
		--dependencies) INSTALL_PHASE=dependencies ;;
		--mariadb) INSTALL_PHASE=mariadb ; DATABASE_CHOICE=mariadb ;;
		--mysql) INSTALL_PHASE=mysql ; DATABASE_CHOICE=mysql ;;
		--dotnet) INSTALL_PHASE=dotnet ;;
		--opensim) INSTALL_PHASE=opensim ;;
		esac
		;;
	-h | --help)
		sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-d | --debug | -v | --verbose)
		DEBUG=yes
		;;
	*)
		error "unknown option $argument (see --help)" >&2
		exit 2
		;;
	esac
done
case "$INSTALL_PHASE" in
	all | dependencies | mariadb | mysql | dotnet | opensim) ;;
	*) die "invalid installation phase $INSTALL_PHASE" ;;
esac
[[ "$INSTALL_PHASE" == all || "$INSTALL_PHASE" == opensim ]] || [[ -z "$RUN_SETUP" ]] || die "--setup is only valid for the full install or --opensim"
[[ "$PODMAN_CONNECTION_SELECTED" == no || "$PODMAN_MODE" == yes ]] || die "--connection requires --podman"
[[ "$PODMAN_IMAGE_SELECTED" == no || "$PODMAN_MODE" == yes ]] || die "--image requires --podman"
[[ "$PODMAN_MODE" != yes || -z "$RUN_SETUP" ]] || die "--setup needs an interactive container terminal; run opensim setup in the container after installation"

if [[ -n "$REMOTE_TARGET" ]]; then
	run_remote_install "$REMOTE_TARGET" "${REMOTE_ARGS[@]}"
	exit $?
fi

if [[ "$PODMAN_MODE" == yes ]]; then
	run_podman_install "${PODMAN_INSTALL_ARGS[@]}"
	exit $?
fi

# Check if in a clone of the repository
here=
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
	here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
log here $here
clone=
[[ -n "$here" && -x "$here/bin/opensim" && -f "$here/composer.json" ]] && clone=$here
log clone $clone

case "$(uname -s)" in Linux | Darwin) ;; *) die "unsupported system $(uname -s)" ;; esac

if [[ "$RUN_CLEANUP" == yes ]]; then
	[[ $(uname -s) == Linux ]] || die "cleanup is available on Debian and Ubuntu only"
	phase_cleanup
fi

case "$INSTALL_PHASE" in
all)
	phase_dependencies || die "quick-install dependencies failed"
	if [[ $(uname -s) == Linux ]]; then
		phase_database || die "database phase failed"
		phase_dotnet || die ".NET phase failed"
	fi
	phase_opensim
	;;
dependencies) phase_dependencies || die "quick-install dependencies failed" ;;
mariadb | mysql) phase_database || die "database phase failed" ;;
dotnet) phase_dotnet || die ".NET phase failed" ;;
opensim) phase_opensim ;;
esac
