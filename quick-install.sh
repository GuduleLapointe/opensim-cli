#!/usr/bin/env bash

# OpenSim Install script: gets this machine ready, then starts `opensim setup`, which asks about your grid.
#
#   One command, from the web (Debian or Ubuntu):
#     curl -fsSL https://raw.githubusercontent.com/GuduleLapointe/opensim-kit/refs/heads/master/setup.sh | sudo bash
#
#   Or from a clone of the repository:
#     git clone https://github.com/GuduleLapointe/opensim-kit.git && cd opensim-kit && ./setup.sh
#
#   Or with the packages only:  sudo apt install opensim-kit && opensim setup
#
# From the web it installs the packages of the Magiiic repository (opensim-kit and what it needs, the .NET runtime
# included). From a clone it runs the tools of the clone: its PHP libraries come from composer.
#
# Options:  -y, --yes   do not ask before installing
#           --no-setup  prepare the machine, do not start `opensim setup`
# Environment: OPENSIM_KIT_DEBS=folder  install the packages (*.deb) of that folder instead of the Magiiic repository

set -euo pipefail

for file in "${1:+$1/.env}" "${OPENSIM_RC:-${HOME:-}/.opensimrc}"; do
	# shellcheck disable=SC1090
	[[ -n "$file" && -r "$file" ]] && source "$file"
done

MAGIIIC_KEY=https://apt.magiiic.com/magiiic-packaging.asc
MAGIIIC_REPOSITORY="deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com stable main"
# What the tools need on a machine that does not have the packages (a clone): the same as the package opensim-tools
PHP_PACKAGES=(php-cli php-curl php-intl php-mbstring php-mysql php-xml)
TOOL_PACKAGES=(ca-certificates curl git unzip screen sudo default-mysql-client)
OPENSIM_PACKAGES=(opensim-cli opensim-helpers)

OPENSIM_KIT_DEBS=${OPENSIM_KIT_DEBS:-}
ASSUME_YES=${ASSUME_YES:-}
RUN_SETUP=${RUN_SETUP:-}

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

install_packages() {
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu (see INSTALLATION.md for the others)"
	export DEBIAN_FRONTEND=noninteractive
	as_root apt-get update -qq
	as_root apt-get install -y -qq "$@"
}

# The .NET runtime OpenSimulator needs, and libgdiplus, by the command of the tools (it knows what each system has)
dotnet_runtime() {
	as_root "$1" install-dotnet -y
}

# Installation completed, give proper instructions and run opensim setup if RUN_SETUP=yes
end_installation() {
	local basedir

	if [ -n "${clone:-}" ]; then
		basedir=$clone
	else
		basedir=$(cd $(dirname $(realpath $(which opensim)))/.. && pwd)
	fi
	cat <<-INSTALL_COMPLETED
		Installation completed, execute:
		    source ${basedir}/share/bash-completion/opensim
		    $basedir/bin/opensim setup
	INSTALL_COMPLETED
	if [[ "${RUN_SETUP:-}" == "yes" ]]; then
		$basedir/bin/opensim setup || die Error $? while executing opensim setup
	fi
	exit 0
}

# === Actual business logic starts here ===

PGM=$(basename "$0")
TMP=/tmp/$PGM.$$
DEBUG=${DEBUG:-}
trap "rm -rf $TMP $TMP.$$" EXIT

for argument in "$@"; do
	case "$argument" in
	-y | --yes) ASSUME_YES=yes ;;
	--no-setup) RUN_SETUP= ;;
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

# Check if in a clone of the repository
here=
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
	here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
log here $here
clone=
[[ -n "$here" && -x "$here/bin/opensim" && -f "$here/composer.json" ]] && clone=$here
log clone $clone

case "$(uname -s)" in
Linux | Darwin) ;;
*) die "unsupported system $(uname -s)" ;;
esac

if [ -n "$clone" -a -z "$OPENSIM_KIT_DEBS" ]; then
	###
	# A clone: its tools run from the folder, with the PHP libraries of composer
	###
	say "Install from the clone in $clone"

	os=$(uname -s)
	case $os in
	Darwin)
		log Darwin detected
		command -v brew >/dev/null 2>&1 || die "Homebrew is needed on macOS: https://brew.sh"
		for tool in php composer screen; do
			command -v "$tool" >/dev/null 2>&1 && continue
			log Install $tool
			brew install "$tool"
		done
		;;

	Linux)
		log Linux detected
		missing=()
		command -v php >/dev/null 2>&1 || missing+=("${PHP_PACKAGES[@]}")
		command -v composer >/dev/null 2>&1 || missing+=(composer)
		for tool in curl git unzip screen; do
			command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
		done
		command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || missing+=(default-mysql-client)
		if ((${#missing[@]})); then
			say "This machine needs: ${missing[*]}"
			ask "Install them?" || die "cancelled"
			install_packages "${missing[@]}"
		fi
		;;
	*)
		die "$os operating system not supported"
		;;
	esac

	php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);' || die "PHP 8.2 or newer is needed (this is $(php -r 'echo PHP_VERSION;'))"

	if [[ ! -f "$clone/vendor/autoload.php" ]]; then
		say "Installing the PHP libraries (composer)..."
		(cd "$clone" && composer install --no-dev --no-interaction --prefer-dist)
	fi

	if [[ $(uname -s) == Linux ]]; then
		as_root "$clone/bin/opensim" install-dotnet -y
	fi

	end_installation
else
	###
	# Install debian packages, from apt repository and/or local .deb files
	###
	[[ $(uname -s) == Linux ]] || die "the packages are for Debian and Ubuntu: on macOS, clone the repository and run ./setup.sh from it"
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu (see INSTALLATION.md for the others)"

	if [[ -n "${OPENSIM_KIT_DEBS:-}" ]]; then
		debs=$(cd "$OPENSIM_KIT_DEBS" && pwd) || die "$OPENSIM_KIT_DEBS is not a folder"
		say "Use local packages from ${OPENSIM_KIT_DEBS}"
		cd $debs
		if [[ ! -s Packages.gz ]] || find . -maxdepth 1 -type f -name '*.deb' -newer Packages.gz -print -quit | grep -q .; then
			say "A scan of the directory is required"
			if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
				install_packages dpkg-dev ||
					die "no dpkg-scanpackages, could not install dpkg-dev"
			fi
			dpkg-scanpackages . /dev/null | gzip -9c >Packages.gz ||
				die Directory scan failed $?
		fi

		if ! grep -q "^[^#]*\bfile:$debs\b" /etc/apt/sources.list.d/*.list 2>/dev/null; then
			say "Add $debs folder to apt sources"
			echo deb [trusted=yes] file:$debs ./ |
				as_root tee -a /etc/apt/sources.list.d/magiiic.list
		fi
	fi

	if [[ ! -f /etc/apt/sources.list.d/magiiic.list ]]; then
		log "add official magiiic repository to apt sources"
		install_packages ca-certificates curl gpg
		curl -fsSL "$MAGIIIC_KEY" | as_root gpg --dearmor --yes -o /usr/share/keyrings/magiiic-packaging.gpg
		printf '%s\n' "$MAGIIIC_REPOSITORY" | as_root tee /etc/apt/sources.list.d/magiiic.list >/dev/null
	fi

	say "Install apt packages"
	install_packages ${OPENSIM_PACKAGES[@]} || die error $?

	if ! command -v dotnet | grep -q .; then
		say "Install dotnet"
		as_root opensim install-dotnet -y || die Error $? installing dotNet
	fi

	end_installation
fi
