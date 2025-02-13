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

# partition disks and format
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

default_efi_size="512M"
echo "Enter the size of the EFI partition:"
read -p "size{K,M,G,T,P} (rec: 512M) :" efi_part_size
efi_part_size=${efi_part_size:-$default_efi_size}
echo "EFI partition size set to: $efi_part_size"

echo

default_root_size="4G"
echo "Enter the size of the root partition:"
echo "This will be transfered to ram so the smaller the better"
read -p "size{K,M,G,T,P} (rec: 4G) :" root_part_size
root_part_size=${root_part_size:-$default_root_size}
echo "root partition size set to: $root_part_size"
read -s -p "Press Enter to continue..."

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
echo   # First sector (Accept default: varies)
echo +$root_part_size # Last sector (Accept default: varies)
echo t # Change partition type
echo 2 # Select partition 2
echo 23 # Linux root (x86-64)
echo n # Add a new partition
echo 3 # Partition number
echo   # First sector (Accept default: varies)
echo   # Last sector (Accept default: varies)
echo w # Write changes
) | fdisk /dev/$drive

# format partitions
mkfs.fat -F32 /dev/${drive}1
mkfs.ext4 /dev/${drive}2
mkfs.ext4 /dev/${drive}3

# mount filesystem
default_root_loc="/mnt/arch-install"
echo 
echo "default: $default_root_loc"
read -p "directory to mount filesystem:" rootfsloc
rootfsloc=${rootfsloc:-$default_root_loc}
echo "root filesystem mount location: $rootfsloc"
read -s -p "Press Enter to continue..."

mount --mkdir /dev/${drive}2 $rootfsloc
mount --mkdir /dev/${drive}1 $rootfsloc/boot

# install packages
echo "list packages to install seperated with spaces ex: networkmanager nano vi"
read -p "packages to install:" packages
pacstrap -K $rootfsloc base linux linux-firmware base-devel git squashfs-tools amd-ucode intel-ucode polkit sudo reflector $packages

# generate fstab only include boot
genfstab -U $rootfsloc | grep -A 1 "^# /dev/${drive}1" >> $rootfsloc/etc/fstab

# copy squashfs script to new root
cp ./scripts/squashfs.sh $rootfsloc/root/squashfs.sh

# copy mkinitcpio hooks to new root
part3_uuid=$(blkid -s UUID -o value /dev/${drive}3)

cp ./scripts/install/bootram $rootfsloc/etc/initcpio/install/bootram
cp ./scripts/hooks/bootram $rootfsloc/etc/initcpio/hooks/bootram
sed -i "s/part3-uuid/$part3_uuid/g" $rootfsloc/etc/initcpio/hooks/bootram
chmod +x $rootfsloc/etc/initcpio/install/bootram
chmod +x $rootfsloc/etc/initcpio/hooks/bootram

# modify mkinitcpio.conf
if grep -q "^MODULES=" $rootfsloc/etc/mkinitcpio.conf; then
  sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 squashfs overlay)/' $rootfsloc/etc/mkinitcpio.conf
else
  echo 'MODULES=(squashfs overlay)' >> $rootfsloc/etc/mkinitcpio.conf
fi

# remove keyboard and block hooks if they exist
sed -i 's/\<keyboard\>//g' $rootfsloc/etc/mkinitcpio.conf
sed -i 's/\<block\>//g' $rootfsloc/etc/mkinitcpio.conf

# place keyboard and block hooks behind autodetect
sed -i 's/\(autodetect\)/keyboard block \1/' $rootfsloc/etc/mkinitcpio.conf

# add bootram hook at the end
sed -i 's/\(HOOKS=(.*\))/\1 bootram)/' $rootfsloc/etc/mkinitcpio.conf

# add systemd-boot config to tmp
cp -r ./scripts/systemd-boot $rootfsloc/root/systemd-boot

# create a temporary script to be executed within the chroot environment
cat <<'EOF' > $rootfsloc/root/chroot-script.sh
#!/bin/bash

# set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# enable locales in /etc/locale.gen
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen

# make /etc/locale.conf file
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# hostname
read -p "hostname: " hostname
echo $hostname > /etc/hostname

# make initial ramdisk
mkinitcpio -P

# set root password
passwd

# install and configure systemd-boot
bootctl install

part2_uuid=$(blkid -s UUID -o value /dev/${drive}2)

cp /root/systemd-boot/loader.conf /boot/loader/loader.conf
cp /root/systemd-boot/entries/arch.conf /boot/loader/entries/arch.conf
cp /root/systemd-boot/entries/arch-toram.conf /boot/loader/entries/arch-toram.conf
cp /root/systemd-boot/entries/arch-fallback.conf /boot/loader/entries/arch-fallback.conf

sed -i "s/part2-uuid/$part2_uuid/g" /boot/loader/entries/arch.conf
sed -i "s/part2-uuid/$part2_uuid/g" /boot/loader/entries/arch-fallback.conf

read -p "Add secureboot with shim boot (y/n): " secureboot_choice
if [[ "$secureboot_choice" != "y" ]]; then
  echo "Secure Boot support will not be added"
  # execute squashfs.sh
  bash /root/squashfs.sh
  echo "done"
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

# execute squashfs.sh
bash /root/squashfs.sh

echo "done"
exit 0
EOF

# make the script executable
chmod +x $rootfsloc/root/chroot-script.sh

# chroot into the new system and execute the script
arch-chroot $rootfsloc /root/chroot-script.sh

# clean up
rm $rootfsloc/root/chroot-script.sh
rm -r $rootfsloc/root/systemd-boot

# unmount filesystem
# umount -R $rootfsloc

# exit the original script
exit 0