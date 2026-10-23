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
#           --cleanup             remove an existing OpenSim installation first (asks for confirmation)
#           --setup               run `opensim setup` after the full or OpenSim install
#           --dependencies        install quick-install's own dependencies
#           --mariadb | --mysql   install/configure the requested SQL server
#           --dotnet              install the .NET runtime without OpenSim packages
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
RUN_CLEANUP=no

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
		if apt-cache policy "$package" 2>/dev/null | grep -Eq 'Candidate: [^()]'; then
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

apt_has_candidate() {
	apt-cache policy "$1" 2>/dev/null | grep -Eq 'Candidate: [^()]'
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

configure_package_sources() {
	[[ "$PACKAGE_SOURCES_READY" == yes ]] && return 0
	[[ $(uname -s) == Linux ]] || die "packages are for Debian and Ubuntu"
	command -v apt-get >/dev/null 2>&1 || die "no apt-get here: this works on Debian and Ubuntu"
	# A local repository from an earlier run may point at a different path.
	# Remove it before install_packages runs apt-get update; the source for this
	# run is configured below, after the local index has been checked.
	if grep -Eq '^[[:space:]]*deb([[:space:]]|\[).*file:' /etc/apt/sources.list.d/magiiic.list 2>/dev/null; then
		as_root rm -f /etc/apt/sources.list.d/magiiic.list || return $?
	fi
	install_packages ca-certificates curl gpg openssl || return $?

	local apt_debs=
	if [[ -n "$OPENSIM_KIT_DEBS" ]]; then
		local debs
		debs=$(cd "$OPENSIM_KIT_DEBS" && pwd) || die "$OPENSIM_KIT_DEBS is not a folder"
		say "Use local packages from $debs"
		if [[ ! -s "$debs/Packages.gz" ]] || [[ $(ls -rt "$debs"/*.deb "$debs/Packages.gz" 2>/dev/null | tail -n 1) != "$debs/Packages.gz" ]]; then
			say "Refresh the local package index"
			if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
				install_packages dpkg-dev || die "no dpkg-scanpackages, could not install dpkg-dev"
			fi
			(cd "$debs" && dpkg-scanpackages --multiversion . /dev/null | gzip -9c >Packages.gz) || die "local package index refresh failed"
		fi
		apt_debs=$(apt_accessible_local_repository "$debs") || return $?
	fi
	if [[ ! -s /usr/share/keyrings/magiiic-packaging.gpg ]]; then
		curl -fsSL "$MAGIIIC_KEY" | as_root gpg --dearmor --yes -o /usr/share/keyrings/magiiic-packaging.gpg || return $?
	fi
	{
		printf '%s\n' "$MAGIIIC_REPOSITORY"
		[[ -z "$apt_debs" ]] || printf 'deb [trusted=yes] file:%s ./\n' "$apt_debs"
	} | as_root tee /etc/apt/sources.list.d/magiiic.list >/dev/null || return $?
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
		if apt_has_candidate libgdiplus; then
			support_packages+=(libgdiplus)
		else
			say "libgdiplus is not available from the configured APT sources"
		fi
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

	package_rows=$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 'opensim-*' 2>/dev/null) || package_rows=
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
		--cleanup) RUN_CLEANUP=yes ;;
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
