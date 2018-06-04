# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
#
# sdchroot
# unmount_on_exit
# check_loop_device
# install_external_applications
# write_uboot
# customize_image
# install_deb_chroot


sdchroot()
{
	local dir=$1
	shift
	# --bind here is to fool useless makedev postinstall script
	systemd-nspawn -q -a --bind /dev/zero:/dev/.devfsd -D "$dir" "$@"
}

# unmount_on_exit
#
unmount_on_exit()
{
	trap - INT TERM EXIT
	umount -l $SDCARD/tmp >/dev/null 2>&1
	umount -l $SDCARD >/dev/null 2>&1
	umount -l $MOUNT/boot >/dev/null 2>&1
	umount -l $MOUNT >/dev/null 2>&1
	losetup -d $LOOP >/dev/null 2>&1
	rm -rf --one-file-system $SDCARD
	exit_with_error "debootstrap-ng was interrupted"
} #############################################################################

# check_loop_device <device_node>
#
check_loop_device()
{
	local device=$1
	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 $device b 0x$(stat -c '%t' "/tmp/$device") 0x$(stat -c '%T' "/tmp/$device")
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi
} #############################################################################

install_external_applications()
{
	display_alert "Installing extra applications and drivers" "" "info"

	for plugin in $SRC/packages/extras/*.sh; do
		source $plugin
	done
}  #############################################################################

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
#
write_uboot()
{
	local loop=$1
	display_alert "Writing U-boot bootloader" "$loop" "info"
	mkdir -p /tmp/u-boot/
	dpkg -x ${DEST}/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb /tmp/u-boot/
	write_uboot_platform "/tmp/u-boot/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
	rm -r /tmp/u-boot/
	sync
} #############################################################################

customize_image()
{
	# for users that need to prepare files at host
	[[ -f $SRC/userpatches/customize-image-host.sh ]] && source $SRC/userpatches/customize-image-host.sh
	cp $SRC/userpatches/customize-image.sh $SDCARD/tmp/customize-image.sh
	chmod +x $SDCARD/tmp/customize-image.sh
	display_alert "Calling image customization script" "customize-image.sh" "info"
	mkdir -p $SDCARD/tmp/overlay
	sdchroot $SDCARD --bind $SRC/userpatches/overlay:$SDCARD/tmp/overlay /bin/bash -c "/tmp/customize-image.sh $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP"
	rm -r $SDCARD/tmp/overlay
} #############################################################################

install_deb_chroot()
{
	local package=$1
	local name=$(basename $package)
	cp $package $SDCARD/root/$name
	display_alert "Installing" "$name"
	sdchroot $SDCARD /bin/bash -c "dpkg -i /root/$name" >> $DEST/debug/install.log 2>&1
	rm -f $SDCARD/root/$name
}