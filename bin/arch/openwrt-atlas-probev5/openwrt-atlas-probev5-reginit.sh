. /home/atlas/bin/common-pre.sh

# Commands
CHECK_FOR_NEW_KERNEL_CMD=:
SSH_CMD=probev5_ssh
SSH_CMD_EXEC=probev5_ssh_exec

# Files
KERNEL_STATE_DIR=/home/atlas/state
TMP_FW=/storage/turrisos-mvebu-cortexa53-device-ripe-atlas-rootfs.tar.gz

. $BIN_DIR/arch/openwrt/openwrt-common.sh
. $BIN_DIR/arch/openwrt-atlas-probev5/openwrt-atlas-probev5-common.sh
. $BIN_DIR/arch/linux/linux-functions.sh

clean_snapshots()
{
	MOUNT_POINT=/mnt/.snapshots

	mount -o remount,rw /
	mkdir -p "$MOUNT_POINT"
	mount /dev/mmcblk1p1 "$MOUNT_POINT"

	btrfs subvolume list / |
		grep '@[0-9][0-9]*$' |
		sed 's/.*\(@[0-9]*\)$/\1/' |
		tac |
		tail +11 |
		head -3 |
		while read a
		do
			btrfs subvolume delete "$MOUNT_POINT/$a/storage"
			btrfs subvolume delete "$MOUNT_POINT/$a"
		done
	umount "$MOUNT_POINT"
}

install_firmware()
{
	fw=$1

	# Remove some old snapshots
	clean_snapshots

	# Just in case they are still mounted from a previous run
	umount /mnt/.snapshots

	# Remount root read-write
	mount -o remount,rw /

	if [ "$fw" = manual ]
	then
		# Move image to /storage. Note that DEV_FIRMWARE has a wildcard
		mv $DEV_FIRMWARE "$TMP_FW"
	else
		# Remove bz2 compression
		bzip2 -dc "$1" >"$TMP_FW"
		rm -f "$1"
	fi
	# Create new snapshot
	schnapps import -f "$TMP_FW"

	rm -f "$TMP_FW"

	# Mount new snapshot
	mkdir -p /mnt/.snapshots
	mount /dev/mmcblk1p1 /mnt/.snapshots

	TMP_ROOT=/mnt/.snapshots/@factory

	# Copy probe's private key
	cp $SSH_PVT_KEY $TMP_ROOT/$SSH_PVT_KEY
	cp /etc/config/network $TMP_ROOT/etc/config/network
	cp /home/atlas/state/mode $TMP_ROOT/home/atlas/state/mode

	# Copy host ssh keys (for dev and test access)
	for f in /etc/ssh/ssh_host_*
	do
		if [ -f "$f" ]
		then
			cp $f $TMP_ROOT"$f"
		fi
	done

	# Copy system configuration
	cp /etc/config/network $TMP_ROOT/etc/config
	cp /etc/config/system $TMP_ROOT/etc/config

	# Save /storage
	cp -r /storage $TMP_ROOT/storage.saved

	umount /mnt/.snapshots

	# Record current time
	date +%s >/home/atlas/status/currenttime.txt

	schnapps rollback factory
}

p_to_r_init()
{
	{
		reason="$1"
		echo P_TO_R_INIT
		echo TOKEN_SPECS `get_arch` `uname -r` `cat $STATE_DIR/FIRMWARE_APPS_VERSION`
		echo REASON_FOR_REGISTRATION "$reason"
	} | tee $P_TO_R_INIT_IN
}

probev5_ssh()
{
	/usr/bin/ssh -o 'PKCS11Provider /usr/lib/libmox-pkcs11.so' \
		-o "ServerAliveInterval 60" \
		-o "StrictHostKeyChecking yes" \
		-o "UserKnownHostsFile $ATLAS_STATUS/known_hosts" "$@"
}
probev5_ssh_exec()
{
	exec /usr/bin/ssh -o 'PKCS11Provider /usr/lib/libmox-pkcs11.so' \
		-o "ServerAliveInterval 60"\
		-o "StrictHostKeyChecking yes" \
		-o "UserKnownHostsFile $ATLAS_STATUS/known_hosts" "$@"
}

manual_firmware_upgrade
