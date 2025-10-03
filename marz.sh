#!/bin/bash
export PRE_INSTALL=preinst.sh
export PRE_REMOVE=prerm.sh
export POST_INSTALL=postinst.sh
export POST_REMOVE=postrm.sh

error() {
	echo "ERROR: $@"
	exit 1
}

copy() {
	rsync -aAXHh --ignore-existing --info=progress2 $@
}

package() {
	tar --numeric-owner --xattrs --acls -cpf $@
}

unpackage() {
	tar --xattrs --acls -xpf $@
}

setup() {
	mkdir -p /etc/marz /var/marz/packages
}

build() {
	OLDDIR=$PWD
	WORKDIR=$1
	OUTPUT=$2
	cd $WORKDIR
	if [[ ! -d "./control" ]]; then
		error "No control folder found. Exiting."
	elif [[ ! -d "./data" ]]; then
		error "No data folder found. Exiting."
	elif [[ ! -d "./config" ]]; then
		error "No config file found. Exiting."
	fi
	chmod +x control/*.sh
	PKG_NAME=$(cat config/name)
	if [[ -z "$OUTPUT" ]]; then
		OUTPUT=$OLDDIR/$PKG_NAME.marz
	fi
	package $OUTPUT control/ data/ config/
}

extract() {
	OLDDIR=$PWD
	PACKAGE=$1
	WORKDIR=$2
	TEMPDIR=$(mktemp -d)
	cd $TEMPDIR
	unpackage $PACKAGE
	copy data $WORKDIR
	cd $OLDDIR
	rm -rf $TEMPDIR
}

install() {
	OLDDIR=$PWD
	PACKAGE=$1
	shift
	FLAGS=$@
	[[ ! -f "$PACKAGE" ]] && error "Target file not found."
	TEMPDIR=$(mktemp -d)
	cd $TEMPDIR
	unpackage $PACKAGE
	PKG_NAME="$(cat config/name)"
	PKG_VERSION="$(cat config/version)"
	if [[ -d "/var/marz/packages/$PKG_NAME" ]] && [[ "$FLAGS" == *"--upgrade"* ]]; then
		UPGRADE=1
	fi
	mkdir -p /var/marz/packages/$PKG_NAME/{info,remove}
	copy config /var/marz/packages/$PKG_NAME/info
	find ./data -mindepth 1 -printf '%P\n' | while read -r rel; do
		if [ ! -e "/$rel" ]; then
			sed -i "\| $rel$|d" /var/marz/packages/$PKG_NAME/filelist
			echo "$(sha256sum "data/$rel" | cut -d ' ' -f1) /$rel" >> /var/marz/packages/$PKG_NAME/filelist
		else
			if [[ -f "/$rel" ]] && [[ -z "$UPGRADE" ]] && [[ "/$rel" != /bin/* ]] && [[ "/$rel" != /lib*/* ]] && [[ "/$rel" != /usr/* ]]; then
				if [[ ! -z "$ALLYES" ]]; then
					rm -rf /$rel
					sed -i "\| $rel$|d" /var/marz/packages/$PKG_NAME/filelist
					echo "$(sha256sum "data/$rel" | cut -d ' ' -f1) /$rel" >> /var/marz/packages/$PKG_NAME/filelist
				elif [[ -z "${ALLYES}${ALLNO}" ]]; then
					read -p "The package $PKG_NAME wants to install it's version of the file /$rel, but it already exists. Would you like to replace the pre-existing file with the package's version? (y/N/a[n]/a[y]) " response
					case "$response" in
						[yY])
							rm -rf /$rel
							sed -i "\| $rel$|d" /var/marz/packages/$PKG_NAME/filelist
							echo "$(sha256sum "data/$rel" | cut -d ' ' -f1) /$rel" >> /var/marz/packages/$PKG_NAME/filelist
							;;
						ay|aY|Ay|AY)
							rm -rf /$rel
							sed -i "\| $rel$|d" /var/marz/packages/$PKG_NAME/filelist
							echo "$(sha256sum "data/$rel" | cut -d ' ' -f1) /$rel" >> /var/marz/packages/$PKG_NAME/filelist
							ALLYES=1
							;;
						an|aN|An|AN)
							ALLNO=1
							;;
					esac
				fi
			elif [[ -f "/$rel" ]] && [[ -z "$UPGRADE" ]] && { [[ "/$rel" == /bin/* ]] || [[ "/$rel" == /lib*/* ]] || [[ "/$rel" == /usr/* ]] }; then
				rm -rf /$rel
				sed -i "\| $rel$|d" /var/marz/packages/$PKG_NAME/filelist
				echo "$(sha256sum "data/$rel" | cut -d ' ' -f1) /$rel" >> /var/marz/packages/$PKG_NAME/filelist
			elif [[ -f "/$rel" ]] && [[ ! -z "$UPGRADE" ]] && { [[ "/$rel" == /bin/* ]] || [[ "/$rel" == /lib*/* ]] || [[ "/$rel" == /usr/* ]] }; then
				rm -rf /$rel
				sed -i "\| $rel$|d" /var/marz/packages/$PKG_NAME/filelist
				echo "$(sha256sum "data/$rel" | cut -d ' ' -f1) /$rel" >> /var/marz/packages/$PKG_NAME/filelist
			elif [[ -f "/$rel" ]] && [[ ! -z "$UPGRADE" ]] && [[ "$(cat /var/marz/packages/$PKG_NAME/filelist | grep " /$rel$" | cut -d ' ' -f1)" == "$(sha256sum "/$rel" | cut -d ' ' -f1)" ]] && [[ "/$rel" != /bin/* ]] && [[ "/$rel" != /lib*/* ]] && [[ "/$rel" != /usr/* ]]; then
				rm -rf /$rel
				sed -i "\| $rel$|d" /var/marz/packages/$PKG_NAME/filelist
				echo "$(sha256sum "data/$rel" | cut -d ' ' -f1) /$rel" >> /var/marz/packages/$PKG_NAME/filelist
			fi
		fi
	done
	[[ -f "./control/$PRE_REMOVE" ]] && copy control/$PRE_REMOVE /var/marz/packages/$PKG_NAME/remove/
	[[ -f "./control/$POST_REMOVE" ]] && copy control/$POST_REMOVE /var/marz/packages/$PKG_NAME/remove/

	[[ -f "./control/$PRE_INSTALL" ]] && ./control/$PRE_INSTALL
	copy data /
	[[ -f "./control/$POST_INSTALL" ]] && ./control/$POST_INSTALL
	cd $OLDDIR
	rm -rf $TEMPDIR
}

remove() {
	OLDDIR=$PWD
	PKG_NAME=$1
	[[ ! -d "/var/marz/packages/$PKG_NAME" ]] && error "Package not installed."
	[[ -f "/var/marz/packages/$PKG_NAME/remove/$PRE_REMOVE" ]] && /var/marz/packages/$PKG_NAME/remove/$PRE_REMOVE
	for i in $(cat /var/marz/packages/$PKG_NAME/filelist | cut -d ' ' -f2); do
		if [[ "$i" != "/" ]] && [[ "$i" != "/usr" ]] && [[ "$i" != "/lib" ]] && [[ "$i" != "/lib64" ]]; then
			rm -rf $i
			rmdir --ignore-fail-on-non-empty -p "$(dirname "$i")" 2>/dev/null
		fi
	done
	[[ -f "/var/marz/packages/$PKG_NAME/remove/$POST_REMOVE" ]] && /var/marz/packages/$PKG_NAME/remove/$POST_REMOVE
	rm -rf /var/marz/packages/$PKG_NAME/
}

upgrade() {
	OLDDIR=$PWD
	PKG_NAME=$1
	UPGRADE_PACKAGE=$2
	TEMPDIR=$(mktemp -d)
	[[ ! -d "/var/marz/packages/$PKG_NAME" ]] && error "Package not installed."
	cd $TEMPDIR
	unpackage $UPGRADE_PACKAGE
	PKG_VERSION="$(cat config/version)"
	cd $OLDDIR
	rm -rf $TEMPDIR
	[[ "$(echo -e "$(cat /var/marz/packages/$PKG_NAME/info/version)\n$PKG_VERSION" | sort -V | tail -n 1)" != "$PKG_VERSION" ]] && error "Upgrade package's version is lower than the installed package's version. If you are trying to downgrade a package, use marz downgrade."
	install $UPGRADE_PACKAGE --upgrade
}

downgrade() {
	OLDDIR=$PWD
	PKG_NAME=$1
	DOWNGRADE_PACKAGE=$2
	TEMPDIR=$(mktemp -d)
	[[ ! -d "/var/marz/packages/$PKG_NAME" ]] && error "Package not installed."
	cd $TEMPDIR
	unpackage $DOWNGRADE_PACKAGE
	PKG_VERSION="$(cat config/version)"
	cd $OLDDIR
	rm -rf $TEMPDIR
	[[ "$(echo -e "$(cat /var/marz/packages/$PKG_NAME/info/version)\n$PKG_VERSION" | sort -V | head -n 1)" != "$PKG_VERSION" ]] && error "Downgrade package's version is higher than the installed package's version. If you are trying to upgrade a package, use marz upgrade."
	install $DOWNGRADE_PACKAGE --upgrade
}

download() {
	OLDDIR=$PWD
	PKG_NAME=$1
}
