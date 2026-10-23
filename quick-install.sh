#!/usr/bin/env bash

# OpenSim Install script: installs OpenSim and optionally starts `opensim setup`.
#
#   One command, from the web (Debian or Ubuntu):
#     curl -fsSL https://raw.githubusercontent.com/GuduleLapointe/opensim-cli/dev/quick-install.sh | sudo bash
#
#   Or from a clone of the repository:
#     git clone https://github.com/GuduleLapointe/opensim-cli.git && cd opensim-cli && ./quick-install.sh
#
#   Or with the packages only:  sudo apt install opensim-cli opensim-helpers && opensim setup
#
# From a clone it runs the tools of the clone; its PHP libraries come from Composer.
#
# Setup is not started unless requested with --setup or RUN_SETUP=yes.
# Options:  -y, --yes             do not ask before installing
#           --setup               run `opensim setup` after the full or OpenSim install
#           --dependencies        install quick-install's own dependencies
#           --mariadb | --mysql   install/configure the requested SQL server
#           --dotnet              install the .NET runtime
#           --opensim             install OpenSim packages (or prepare the clone)
# Environment: OPENSIM_KIT_DEBS=folder  install the packages (*.deb) of that folder instead of the Magiiic repository

set -euo pipefail

INSTALLER_HOME=${HOME:-/root}
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] && command -v getent >/dev/null 2>&1; then
	INSTALLER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi
OPENSIM_RC_PATH=${OPENSIM_RC:-$INSTALLER_HOME/.opensimrc}

for file in "${1:+$1/.env}" "$OPENSIM_RC_PATH"; do
	# shellcheck disable=SC1090
	[[ -n "$file" && -r "$file" ]] && source "$file"
done

MAGIIIC_KEY=https://apt.magiiic.com/magiiic-packaging.asc
MAGIIIC_REPOSITORY="deb [signed-by=/usr/share/keyrings/magiiic-packaging.gpg] https://apt.magiiic.com stable main"
# What the tools need on a machine that does not have the packages (a clone): the same as the package opensim-tools
PHP_PACKAGES=(php-cli php-curl php-intl php-mbstring php-mysql php-xml)
OPENSIM_PACKAGES=(opensim-cli opensim-helpers)

OPENSIM_KIT_DEBS=${OPENSIM_KIT_DEBS:-}
ASSUME_YES=${ASSUME_YES:-}
RUN_SETUP=${RUN_SETUP:-}
DPKG_CONFIGURED=no
APT_UPDATED=no
PACKAGE_SOURCES_READY=no
INSTALL_PHASE=all
DATABASE_CHOICE=mariadb
PHASE_SELECTED=no

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
		as_root apt-get update -qq || return $?
		APT_UPDATED=yes
	fi
}

install_packages() {
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu (see INSTALLATION.md for the others)"
	export DEBIAN_FRONTEND=noninteractive
	recover_dpkg_configuration || return $?
	apt_update || return $?
	as_root apt-get install -y -qq "$@" || return $?
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

configure_package_sources() {
	[[ "$PACKAGE_SOURCES_READY" == yes ]] && return 0
	[[ $(uname -s) == Linux ]] || die "packages are for Debian and Ubuntu"
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu"
	install_packages ca-certificates curl gpg openssl || return $?

	if [[ -n "$OPENSIM_KIT_DEBS" ]]; then
		local debs
		debs=$(cd "$OPENSIM_KIT_DEBS" && pwd) || die "$OPENSIM_KIT_DEBS is not a folder"
		say "Use local packages from $debs"
		if [[ ! -s "$debs/Packages.gz" ]]; then
			die "Packages.gz is missing from $debs; build the local package index first"
		fi
		if ! grep -Fq "file:$debs" /etc/apt/sources.list.d/magiiic.list 2>/dev/null; then
			printf 'deb [trusted=yes] file:%s ./\n' "$debs" | as_root tee /etc/apt/sources.list.d/magiiic.list >/dev/null || return $?
		fi
	else
		if [[ ! -f /etc/apt/sources.list.d/magiiic.list ]]; then
			curl -fsSL "$MAGIIIC_KEY" | as_root gpg --dearmor --yes -o /usr/share/keyrings/magiiic-packaging.gpg || return $?
			printf '%s\n' "$MAGIIIC_REPOSITORY" | as_root tee /etc/apt/sources.list.d/magiiic.list >/dev/null || return $?
		fi
	fi
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
	local basedir opensim_path

	if [ -n "${clone:-}" ]; then
		basedir=$clone
	else
		opensim_path=$(command -v opensim) || die "opensim is not available after installation"
		basedir=$(cd "$(dirname "$(realpath "$opensim_path")")/.." && pwd) || die "could not locate the opensim installation"
	fi
	cat <<-INSTALL_COMPLETED
		Installation completed, execute:
		    source ${basedir}/share/bash-completion/opensim
		    $basedir/bin/opensim setup
	INSTALL_COMPLETED
	if [[ "${RUN_SETUP:-}" =~ ^(yes|true|1)$ ]]; then
		$basedir/bin/opensim setup || die Error $? while executing opensim setup
	fi
	exit 0
}

phase_dotnet() {
	[[ $(uname -s) == Linux ]] || { say ".NET installation is only run on Linux"; return 0; }
	recover_dpkg_configuration || die "could not complete package configuration"
	if [[ -n "$clone" && -z "$OPENSIM_KIT_DEBS" ]]; then
		[[ -f "$clone/vendor/autoload.php" ]] || phase_dependencies || return $?
		as_root "$clone/bin/opensim" install-dotnet -y || return $?
		return
	fi
	configure_package_sources || return $?
	# The engine owns the runtime installer; its package does not install the CLI.
	install_packages opensim-engine || die "could not install opensim-engine for the .NET installer"
	as_root php -r 'require "/usr/share/opensim-engine/vendor/autoload.php"; $ui = new OpenSim\Provisioning\NullUi(true); $installer = new OpenSim\Runtime\DotnetInstaller($ui); exit($installer->install(8) ? 0 : 1);' || die "could not install the .NET runtime"
}

phase_opensim() {
	if [[ -n "$clone" && -z "$OPENSIM_KIT_DEBS" ]]; then
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

PGM=$(basename "$0")
TMP=/tmp/$PGM.$$
DEBUG=${DEBUG:-}
trap "rm -rf $TMP $TMP.$$" EXIT

while (($#)); do
	argument=$1
	shift
	case "$argument" in
	-y | --yes) ASSUME_YES=yes ;;
	--setup) RUN_SETUP=yes ;;
	--dependencies | --mariadb | --mysql | --dotnet | --opensim)
		[[ "$PHASE_SELECTED" == no ]] || die "choose only one installation phase"
		PHASE_SELECTED=yes
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
