#!/usr/bin/env bash

set -e

print () {
    echo -e "\n\033[1m> $1\033[0m\n"
}

# Tests
ls /sys/firmware/efi/efivars > /dev/null && \
  ping archlinux.org -c 1 > /dev/null &&    \
  timedatectl set-ntp true > /dev/null &&   \
  print "Tests ok"

# Set DISK
select ENTRY in $(ls /dev/disk/by-id/);
do
    DISK="/dev/disk/by-id/$ENTRY"
    echo "Installing on $ENTRY."
    break
done

read -p "> Do you want to wipe all datas on $ENTRY ?" -n 1 -r
echo # move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # Clear disk
    wipefs -af $DISK
    sgdisk -Zo $DISK
fi

# EFI part
print "Creating EFI part"
sgdisk -n1:1M:+512M -t1:EF00 $DISK
EFI=$DISK-part1

# ZFS part
print "Creating ZFS part"
sgdisk -n3:0:0 -t3:bf01 $DISK
ZFS=$DISK-part3

# Inform kernel
partprobe $DISK

# Format boot part
sleep 1
print "Format EFI part"
mkfs.vfat $EFI

# Load ZFS module
print "Load ZFS module"
curl -s https://eoli3n.github.io/archzfs/init | bash

# Create ZFS pool
print "Create ZFS pool"
zpool create -f -o ashift=12 zroot $ZFS
zfs create -o encryption=aes-256-gcm -o keyformat=passphrase -o mountpoint=none zroot/encr

# Slash dataset
print "Create slash dataset"
zfs create -o mountpoint=none zroot/encr/ROOT
zfs create -o compression=lz4        \
           -o dedup=on               \
           -o mountpoint=/           \
           -o acltype=posixacl       \
           -o xattr=sa               \
           -o atime=off              \
           zroot/encr/ROOT/default

# Home dataset
print "Create home dataset"
zfs create -o mountpoint=none zroot/encr/data
zfs create -o compression=lz4        \
           -o dedup=off              \
           -o mountpoint=/home       \
           -o xattr=sa               \
           -o atime=off              \
           zroot/encr/data/home

# SWAP
print "Create swap dataset"
zfs create -V 8G -b $(getconf PAGESIZE)         \
           -o logbias=throughput -o sync=always \
           -o primarycache=metadata             \
           -o com.sun:auto-snapshot=false       \
           zroot/swap

# /tmp
print "Create /tmp dataset"
zfs create -o setuid=off -o devices=off -o sync=disabled -o mountpoint=/tmp zroot/tmp
# TODO Should i encrypt tmp ?

# /var
print "Create datasets snapshot free"
zfs create -o canmount=off -o mountpoint=/var zroot/encr/ROOT/var
zfs create -o canmount=off -o mountpoint=/var zroot/encr/ROOT/usr
zfs create -o canmount=off -o mountpoint=/var zroot/encr/ROOT/srv

# Enable SWAP
mkswap -f /dev/zvol/zroot/swap
swapon /dev/zvol/zroot/swap

# Mount EFI part
mkdir /mnt/boot
mount $EFI /mnt/boot

# Finish
echo -e "\e[32mAll OK"
