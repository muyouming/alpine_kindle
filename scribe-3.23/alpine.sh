#!/bin/sh

setup_swap() {
	# zram0 exists on Scribe-class Kindles; Chromium needs headroom on 1GB RAM.
	if [ -e /sys/block/zram0/disksize ] && ! grep -q zram0 /proc/swaps; then
		[ "$(cat /sys/block/zram0/disksize)" = "0" ] && echo 805306368 > /sys/block/zram0/disksize
		mkswap /dev/zram0 >/dev/null 2>&1 && swapon /dev/zram0 2>/dev/null && echo "zram swap enabled"
	fi
}

setup_perf() {
	for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
		[ -w "$g" ] && echo performance > "$g" 2>/dev/null
	done
}

ALREADYMOUNTED="no"
if mount | grep -q "alpine.ext3" ; then
	ALREADYMOUNTED="yes"
	echo "ATTENTION! Alpine's rootfs is already mounted, thus you will be just dropped into it."
	echo "BE CAREFUL to leave this shell first, as there will be no umount either (To not disturb the other session)."
   else
	echo "Mounting Alpine rootfs"
	mkdir -p /tmp/alpine
	mount -o loop,noatime -t ext3 /mnt/base-us/alpine.ext3 /tmp/alpine
	mount -o bind /dev /tmp/alpine/dev
	mkdir -p /tmp/alpine/dev/shm
	mount -o bind /dev/shm /tmp/alpine/dev/shm
	mount -o bind /dev/pts /tmp/alpine/dev/pts
	mount -o bind /proc /tmp/alpine/proc
	mount -o bind /sys /tmp/alpine/sys
	mount -o bind /var/run/dbus/ /tmp/alpine/run/dbus/
	cp /etc/hosts /tmp/alpine/etc/hosts
	cp /etc/resolv.conf /tmp/alpine/etc/resolv.conf
	chmod a+w /dev/shm
	setup_swap
	setup_perf
fi

echo "You're now being dropped into Alpine's shell"
chroot /tmp/alpine /bin/sh

if [ $ALREADYMOUNTED = "yes" ] ; then
	echo "Umount is being skipped, as the rootfs was mounted already. You're now at your kindle's shell again."
else
	echo "You returned from Alpine, killing remaining processes"
	kill $(pgrep Xephyr) 2>/dev/null || true
	kill -9 $(lsof -t /var/tmp/alpine/) 2>/dev/null || true
	# Kill anything still chrooted into the image (bridge.py, touch.py, Chromium).
	for p in /proc/[0-9]*; do
		[ "$(readlink "$p/root" 2>/dev/null)" = "/var/tmp/alpine" ] && kill -9 "${p##*/}" 2>/dev/null
	done
	killall Xvfb Xephyr 2>/dev/null || true
	sleep 1

	echo "Unmounting Alpine rootfs"
	LOOPDEV="$(losetup -a | grep "/mnt/base-us/alpine.ext3" | cut -d: -f1)"
	umount /tmp/alpine/run/dbus/
	umount /tmp/alpine/dev/shm
	umount /tmp/alpine/sys
	sleep 1
	umount /tmp/alpine/proc
	umount /tmp/alpine/dev/pts
	umount /tmp/alpine/dev
	# Sync beforehand so umount doesn't fail due to the device being busy still
	sync
	umount /tmp/alpine || true
	# Sometimes it fails still and only works by trying again
	while mount | grep -q "alpine.ext3"
	do
		echo "Alpine is still mounted, trying again shortly.."
		sleep 3
		umount /tmp/alpine || true
	done
	echo "Alpine unmounted"
	echo "Disassociating loop device >>$LOOPDEV<<"
	[ -n "$LOOPDEV" ] && losetup -d $LOOPDEV 2>/dev/null || true
	swapoff /dev/zram0 2>/dev/null || true
	for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
		[ -w "$g" ] && echo ondemand > "$g" 2>/dev/null
	done
	echo "All done, you're now back at your kindle's shell."
fi
