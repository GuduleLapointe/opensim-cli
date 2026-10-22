#!/usr/bin/env bash

PGM=$(basename "$0")
TMP=/tmp/$PGM.$$
trap "rm -f $TMP $TMP.*" EXIT

. $(which bash-helpers)

DEBUG=yes

hostname=$(hostname -s)

DIST_FOLDER=${DIST_FOLDER:-/opt/opensim/dist}
log DIST_FOLDER: $DIST_FOLDER

ARCHIVE_FOLDER=${ACHIVES_FOLDER:-${DIST_FOLDER}/archive}
log ARCHIVE_FOLDER: $ARCHIVE_FOLDER

db_prefix=${hostname}

cd $DIST_FOLDER
for package in $(
	ls *.deb |
		sed -E "s#(\.[0-9]+(\+g[a-f0-9]+|\+e[a-f0-9]+(-[0-9]+)?|\+git[a-f0-9\.-]+))?(_[a-z0-9]+)?\.deb##" |
		sort -u
); do
	ls -t $package*.deb 2>/dev/null | tail +2 >>$TMP.duplicates
done

if grep -q . $TMP.duplicates; then
	echo Archive duplicate builds:
	sed "s/^/\t/" $TMP.duplicates | tac
fi >>$TMP.tasks

dpkg --get-selections "opensim-*" 2>/dev/null | cut -f 1 >$TMP.installed
if grep -q . $TMP.installed; then
	echo Uninstall packages:
	sed "s/^/\t/" $TMP.installed
fi >>$TMP.tasks

ls -d /etc/opensim/ /var/lib/opensim/ /usr/share/opensim* 2>/dev/null >$TMP.folders
if grep -q . $TMP.folders; then
	echo Delete folders:
	for folder in $(cat $TMP.folders); do
		printf "\t%s (%s)\n" "$folder" $(find $folder/ -type f | wc -l)
	done
	# sed "s/^/\t/" $TMP.folders
fi >>$TMP.tasks

mysql -BN -e "SHOW DATABASES like '${db_prefix}%'" >$TMP.databases
if grep -q . $TMP.databases; then
	echo "Drop these databases:"
	sed "s/^/\t/" $TMP.databases
fi >>$TMP.tasks

if grep -q . "$TMP.tasks"; then
	cat $TMP.tasks
	yesno "Are you sure you want to proceed?" || end "Abort"
fi

duplicates=$(cat $TMP.duplicates)
if [ -n "$duplicates" ]; then
	log Move duplicates $duplicates
	mkdir -p $ARCHIVE_FOLDER || end $?
	for duplicate in $duplicates; do
		mv -v "$duplicate" $ARCHIVE_FOLDER/ || end $?
	done
fi

packages=$(cat $TMP.installed)
if [ -n "$packages" ]; then
	log Uninstall $packages
	sudo apt remove $packages --purge -y || end $?
fi

folders=$(cat $TMP.folders)
if [ -n "$folders" ]; then
	log Remove installation folders $(cat $TMP.folders)
	sudo rm -rf $(cat $TMP.folders) || end $?
fi

databases=$(cat $TMP.databases)
if [ -n "$databases" ]; then
	for db in $databases; do
		log dropping database $db
		mysql -e "DROP DATABASE $db;" && log dropped $db || end $?
	done
fi
