#!/bin/bash

# modify this to get the uuid of the hook uuid 

echo "Make squashfs image of root filesystem"

part_uuid="storage"

# Check if the UUID exists
if ! blkid | grep -q "UUID=\"$part_uuid\""; then
  echo "Error: UUID=$part_uuid does not exist."
  exit 1
fi

MOUNT_POINT=$(findmnt -nr -o TARGET -S UUID=$part_uuid)

if [ -z "$MOUNT_POINT" ]; then
  echo "UUID=$part_uuid is not mounted. Mounting it at /mnt/$part_uuid."
  mount --mkdir UUID=$part_uuid /mnt/$part_uuid
  MOUNT_POINT="/mnt/$part_uuid"
  x=1
else
  echo "UUID=$part_uuid is mounted at $MOUNT_POINT."
  x=0
fi

echo
read -p "Enter the name of the squashfs image: " squashfs_name

mksquashfs / $MOUNT_POINT/squashfs/rootfs-tmp.sfs -e /proc /sys /dev /tmp /run /mnt /media /var/tmp /var/run /boot

mv $MOUNT_POINT/squashfs/rootfs-tmp.sfs $MOUNT_POINT/squashfs/$squashfs_name.sfs

if [ $x -eq 1 ]; then
  umount -l $MOUNT_POINT
fi
