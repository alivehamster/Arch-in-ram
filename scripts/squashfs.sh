#!/bin/bash

storage_uuid="storage-uuid"
boot_uuid="boot-uuid"
part_uuid="part-uuid"

# Check if the UUID exists
if ! blkid | grep -q "UUID=\"$storage_uuid\""; then
  echo "Error: UUID=$storage_uuid does not exist."
  exit 1
fi

if ! blkid | grep -q "UUID=\"$boot_uuid\""; then
  echo "Error: UUID=$boot_uuid does not exist."
  exit 1
fi

MOUNT_POINT=$(findmnt -nr -o TARGET -S UUID=$storage_uuid)
BOOT_MOUNT=$(findmnt -nr -o TARGET -S UUID=$boot_uuid)

if [ -z "$MOUNT_POINT" ]; then
  echo "UUID=$storage_uuid is not mounted. Mounting it at /mnt/$storage_uuid."
  mount --mkdir UUID=$storage_uuid /mnt/$storage_uuid
  MOUNT_POINT="/mnt/$storage_uuid"
  x=1
else
  echo "UUID=$storage_uuid is mounted at $MOUNT_POINT."
  x=0
fi

if [ -z "$BOOT_MOUNT" ]; then
  echo "UUID=$boot_uuid is not mounted. Mounting it at /mnt/$boot_uuid."
  mount --mkdir UUID=$boot_uuid /mnt/$boot_uuid
  BOOT_MOUNT="/mnt/$boot_uuid"
  y=1
else
  echo "UUID=$boot_uuid is mounted at $BOOT_MOUNT."
  y=0
fi

echo
echo "Select an option:"
echo "1) Create new rootfs"
echo "2) Use existing rootfs"
echo "3) Delete rootfs"
read -p "Enter choice [1-3]: " choice

case $choice in
  1)
    echo
    read -p "Enter the name of the new squashfs image: " squashfs_name
    echo
    echo "Enter the size of the ramdisk:"
    echo "This is the amount of ram space the filesystem will have access to"
    read -p "size{K,M,G,T,P} (rec: 4G) : " ramdisk_size

    mkdir -p $BOOT_MOUNT/linux/$squashfs_name

    cp /usr/local/share/squashfs-stuff/bootram /etc/initcpio/hooks/bootram
    sed -i "s/part-uuid/$part_uuid/g" /etc/initcpio/hooks/bootram
    sed -i "s/ramdisk-size/$ramdisk_size/g" /etc/initcpio/hooks/bootram
    sed -i "s/squash-name/$squashfs_name/g" /etc/initcpio/hooks/bootram

    echo "Generating new initramfs..."
    mkinitcpio -P

    cp /usr/local/share/squashfs-stuff/systemd-boot/entries/arch.conf $BOOT_MOUNT/loader/entries/arch-$squashfs_name.conf
    sed -i "s/squash-name/$squashfs_name/g" $BOOT_MOUNT/loader/entries/arch-$squashfs_name.conf

    echo "Copying kernel and initramfs files..."
    cp "/boot/vmlinuz-linux" "$BOOT_MOUNT/linux/$squashfs_name/vmlinuz-linux"
    cp "/boot/initramfs-linux.img" "$BOOT_MOUNT/linux/$squashfs_name/initramfs-linux.img"
    echo "Kernel files copied to $BOOT_MOUNT/linux/$squashfs_name/"

    rm $MOUNT_POINT/squashfs/$squashfs_name.sfs
    mksquashfs / $MOUNT_POINT/squashfs/$squashfs_name.sfs -e /proc /sys /dev /tmp /run /mnt /media /var/tmp /var/run
    echo "Created new rootfs: $squashfs_name.sfs"
    ;;
    
  2)
    echo
    if ! ls $MOUNT_POINT/squashfs/*.sfs >/dev/null 2>&1; then
      echo "No rootfs images found"
      # unmount after
      exit 1
    fi
    
    # Create array of available images
    images=()
    while IFS= read -r file; do
      images+=("$(basename "$file" .sfs)")
    done < <(ls -1 $MOUNT_POINT/squashfs/*.sfs)
    
    # Display selection menu
    echo "Select a rootfs image:"
    select image in "${images[@]}"; do
      if [ -n "$image" ]; then
        echo "Selected: $image.sfs"
        break
      else
        echo "Invalid selection"
      fi
    done

    # Copy kernel and initramfs
    echo "Copying kernel and initramfs files..."
    cp "/boot/vmlinuz-linux" "$BOOT_MOUNT/linux/$image/vmlinuz-linux"
    cp "/boot/initramfs-linux.img" "$BOOT_MOUNT/linux/$image/initramfs-linux.img"
    echo "Kernel files copied to $BOOT_MOUNT/linux/$image/"
    rm $MOUNT_POINT/squashfs/$image.sfs
    mksquashfs / $MOUNT_POINT/squashfs/$image.sfs -e /proc /sys /dev /tmp /run /mnt /media /var/tmp /var/run
    echo "Created new rootfs: $image.sfs"
    ;;
    
  3)
    echo
    echo "Will do later"
    ;;
    
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

if [ $x -eq 1 ]; then
  umount $MOUNT_POINT
fi

if [ $y -eq 1 ]; then
  umount $BOOT_MOUNT
fi