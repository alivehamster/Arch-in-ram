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
  echo "UUID=$part_uuid is not mounted. Mounting it at /mnt/idk."
  mount --mkdir UUID=$part_uuid /mnt/idk
  MOUNT_POINT="/mnt/idk"
else
  echo "UUID=$part_uuid is mounted at $MOUNT_POINT."
fi

# Save the location to a variable
MOUNT_LOCATION=$MOUNT_POINT

# Output the location
echo "Mount location: $MOUNT_LOCATION"

mksquashfs / $MOUNT_POINT/rootfs-tmp.sfs -e /proc /sys /dev /tmp /run /mnt /media /var/tmp /var/run /boot

mv $MOUNT_POINT/rootfs-tmp.sfs $MOUNT_POINT/rootfs.sfs
