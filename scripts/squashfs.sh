#!/bin/bash

echo "Make squashfs image of root filesystem"

lsblk -d -o NAME,SIZE,MODEL

echo "Please select a drive:"
select drive in $(lsblk -d -n -o NAME); do
  if [ -n "$drive" ]; then
    echo "You selected /dev/$drive"
    break
  else
    echo "Invalid selection. Please try again."
  fi
done

MOUNT_POINT=$(findmnt -nr -o TARGET -S /dev/${drive}3)

if [ -z "$MOUNT_POINT" ]; then
  echo "/dev/${drive}3 is not mounted. Mounting it at /mnt/idk."
  mount --mkdir /dev/${drive}3 /mnt/idk
  MOUNT_POINT="/mnt/idk"
else
  echo "/dev/${drive}3 is mounted at $MOUNT_POINT."
fi

# Save the location to a variable
MOUNT_LOCATION=$MOUNT_POINT

# Output the location
echo "Mount location: $MOUNT_LOCATION"

mksquashfs / $MOUNT_POINT/rootfs.sfs -e /proc /sys /dev /tmp /run /mnt /media /var/tmp /var/run /boot
