#!/bin/bash

# check if root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

# check if UEFI
if [ ! -d /sys/firmware/efi ]; then
  echo "This computer is not booted in UEFI mode. Exiting."
  exit 1
fi

# check if network is working
if ! ping -c 1 archlinux.org &> /dev/null; then
  echo "Network is not working. Exiting."
  exit 1
fi

# update system clock
timedatectl

# prompts

# select drive
echo
echo "select a drive to install to"
echo "**All data on the drive will be deleted**"
read -s -p "Press Enter to continue..."
echo "Available drives:"

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

# select partition size
default_efi_size="1G"
echo "Enter the size of the EFI partition:"
read -p "size{K,M,G,T,P} (rec: 1G) :" efi_part_size
efi_part_size=${efi_part_size:-$default_efi_size}
echo "EFI partition size set to: $efi_part_size"

echo

# default_root_size="4G"
# echo "Enter the size of the root partition:"
# echo "This should only be used to install the inital packages"
# read -p "size{K,M,G,T,P} (rec: 4G) : " root_part_size
# root_part_size=${root_part_size:-$default_root_size}
# echo "root partition size set to: $root_part_size"

# echo

default_ramdisk_size="4G"
echo "Enter the size of the ramdisk:"
echo "This is the amount of ram space the filesystem will have access to"
read -p "size{K,M,G,T,P} (recommended min: 4G) : " ramdisk_size
ramdisk_size=${ramdisk_size:-$default_ramdisk_size}
echo "root partition size set to: $ramdisk_size"

# select root filesystem mount location
default_root_loc="/mnt/arch-install"
echo
echo "default: $default_root_loc"
read -p "directory to mount filesystem:" rootfsloc
rootfsloc=${rootfsloc:-$default_root_loc}
echo "root filesystem mount location: $rootfsloc"

# select packages to install
echo
echo "list packages to install seperated with spaces ex: linux, networkmanager, nano"
echo "base, kernel-modules-hook, and squashfs-tools are automanically included"
echo "base-devel, git, and sudo will be added if secureboot is enabled"

read -p "packages to install:" packages

# select hostname
echo
read -p "hostname: " hostname

# set root password
echo
read -p "Enter root password: " root_password

echo
read -p "Enter squashfs readonly filesystem name: " squashfs_name

# enable secure boot
echo
read -p "Add secureboot with shim boot (y/n): " secureboot_choice

secureboot_packages=""
if [[ "$secureboot_choice" == "y" ]]; then
  secureboot_packages="base-devel git sudo"
fi

pkgname=$(sed -n "s/^pkgname=['\"]\([^'\"]*\)['\"]$/\1/p" PKGBUILD)
pkgver=$(sed -n "s/^pkgver=['\"]\([^'\"]*\)['\"]$/\1/p" PKGBUILD)
pkgrel=$(sed -n "s/^pkgrel=['\"]\([^'\"]*\)['\"]$/\1/p" PKGBUILD)
pkgarch=$(sed -n "s/^arch=('\([^']*\)').*/\1/p" PKGBUILD)
package_file="${pkgname}-${pkgver}-${pkgrel}-${pkgarch}.pkg.tar.zst"

if [[ -z "$pkgname" || -z "$pkgver" || -z "$pkgrel" || -z "$pkgarch" ]]; then
  echo "Could not determine package name, version, release, or architecture from PKGBUILD. Exiting."
  exit 1
fi

# Create partition using fdisk
(
echo g # Create a new empty GPT partition table
echo n # Add a new partition
echo 1 # Partition number
echo   # First sector (Accept default: 1)
echo +$efi_part_size # Last sector (Accept default: varies)
echo t # Change partition type
echo 1 # EFI System
echo n # Add a new partition
echo 2 # Partition number
# echo   # First sector (Accept default: varies)
# echo +$root_part_size # Last sector (Accept default: varies)
# echo t # Change partition type
# echo 2 # Select partition 2
# echo 23 # Linux root (x86-64)
# echo n # Add a new partition
# echo 3 # Partition number
echo   # First sector (Accept default: varies)
echo   # Last sector (Accept default: varies)
echo w # Write changes
) | fdisk /dev/$drive

# format partitions
mkfs.fat -F32 /dev/${drive}1
mkfs.ext4 /dev/${drive}2
# mkfs.ext4 /dev/${drive}3

# mount filesystem
mount --mkdir /dev/${drive}2 $rootfsloc
mount --mkdir /dev/${drive}1 $rootfsloc/boot

boot_uuid=$(blkid -s UUID -o value /dev/${drive}1)
fs_uuid=$(blkid -s UUID -o value /dev/${drive}2)

mkdir -p "$rootfsloc/etc"
cat > "$rootfsloc/etc/arch-in-ram.conf" <<EOF
# Changing these values only takes effect when the Arch-in-RAM package is updated
SQUASHFS="$squashfs_name"
RAMDISK_SIZE="$ramdisk_size"
STORAGE_UUID="$fs_uuid"
BOOT_UUID="$boot_uuid"
EOF

# install packages
pacstrap -K $rootfsloc base kernel-modules-hook squashfs-tools "./$package_file" $packages $secureboot_packages

# copy loader.conf to root filesystem
cp ./scripts/systemd-boot/loader.conf $rootfsloc/root/loader.conf

# create a temporary script to be executed within the chroot environment
cat <<EOF > $rootfsloc/root/chroot-script.sh
#!/bin/bash

final() {
  mksquashfs / /root/rootfs.sfs -e /proc /sys /dev /tmp /run /mnt /media /var/tmp /var/run /root/chroot-script.sh /lost+found -comp zstd

  mkdir -p /boot/linux/$squashfs_name
  mv /boot/vmlinuz-linux /boot/linux/$squashfs_name/vmlinuz-linux
  mv /boot/initramfs-linux.img /boot/linux/$squashfs_name/initramfs-linux.img
}

# set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# enable locales in /etc/locale.gen
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen

# make /etc/locale.conf file
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# hostname
echo $hostname > /etc/hostname

# make initial ramdisk
mkinitcpio -P

# set root password
echo "root:$root_password" | chpasswd
# passwd

# install and configure systemd-boot
bootctl install

cp /root/loader.conf /boot/loader/loader.conf
cp /usr/share/arch-in-ram/arch.conf /boot/loader/entries/$squashfs_name.conf
sed -i "s/squash-name/$squashfs_name/g" /boot/loader/entries/$squashfs_name.conf

if [[ "$secureboot_choice" != "y" ]]; then
  echo "Secure Boot support will not be added"
  # make squashfs filesystem
  final
  exit 0
fi

# secureboot with shim boot

# allow tempuser to temporarily have sudo access
echo "tempuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

useradd -m tempuser
su - tempuser <<'EOF2'

cd ~
git clone https://aur.archlinux.org/shim-signed.git
cd shim-signed
makepkg -si

EOF2

# remove tempuser sudo access
sed -i '/tempuser ALL=(ALL) NOPASSWD: ALL/d' /etc/sudoers

userdel -r tempuser

# add shim boot
mv /boot/EFI/BOOT/BOOTX64.EFI /boot/EFI/BOOT/grubx64.efi
cp /usr/share/shim-signed/shimx64.efi /boot/EFI/BOOT/BOOTX64.EFI
cp /usr/share/shim-signed/mmx64.efi /boot/EFI/BOOT/

# make squashfs filesystem
final

exit 0
EOF

# make the script executable
chmod +x $rootfsloc/root/chroot-script.sh

# chroot into the new system and execute the script
arch-chroot $rootfsloc /bin/bash /root/chroot-script.sh

safe_unmount() {
  local mount_point="$1"

  if [ -z "$mount_point" ]; then
      echo "Error: No mount point specified"
      return 1
  fi

  # Sync any cached writes to disk
  sync

  fuser -k -m "$mount_point" 2>/dev/null
  sleep 1

  # Attempt recursive unmount
  if ! umount -R "$mount_point" 2>/dev/null; then
    echo "Regular unmount failed, attempting lazy recursive unmount..."
    umount -Rl "$mount_point"
  fi

  # Final check
  if mountpoint -q "$mount_point"; then
      echo "Warning: $mount_point is still mounted"
      return 1
  fi

  return 0
}

cp $rootfsloc/root/rootfs.sfs ./
safe_unmount "$rootfsloc/boot"
rm -rf "$rootfsloc"/*
mkdir -p "$rootfsloc/squashfs"
mv ./rootfs.sfs "$rootfsloc/squashfs/$squashfs_name.sfs"

# unmount the filesystem
safe_unmount "$rootfsloc"


# Double check and force unmount if needed
if mountpoint -q "$rootfsloc"; then
  lsof | grep "$rootfsloc" | awk '{print $2}' | xargs -r kill -9
  sleep 2
  umount -lf "$rootfsloc"
  sleep 2
fi

# Flush file system buffers
sync

echo "Done"
