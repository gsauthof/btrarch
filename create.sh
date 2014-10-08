#!/bin/bash

# 2014-07-14, Georg Sauthoff <mail@georg.so>

# Setting up device for snapshot backups

set -e
set -x

if [ $# -lt 3 ]; then
  echo call: $0 DISK_DEVICE MAPPED_NAME MNT_POINT
  exit 2
fi

BTRFS=${BTRFS:-btrfs}
MKFS=${MKFS:-mkfs.btrfs}
CRYPTSETUP=${CRYPTSETUP:-cryptsetup}

DEVICE="$1"
NAME="$2"
MNT="$3"


echo Formatting $DEVICE
"$CRYPTSETUP" luksFormat "$DEVICE"
echo Opening $DEVICE as $NAME
"$CRYPTSETUP" luksOpen "$DEVICE" "$NAME"
echo Creating filesystem on $NAME
"$MKFS" /dev/mapper/"$NAME"
mkdir -p $MNT
echo Mounting $NAME as $MNT
mount -o noatime /dev/mapper/"$NAME" "$MNT"
cd "$MNT"
echo Create mirror subvolume and snapshot base as backup destinations
"$BTRFS" subvolume create mirror
mkdir snapshot


