#!/bin/bash

set -e
set -u

function help()
{
  cat <<EOF
Set up a device for snapshot backups using BTRFS and dm-crypt.

call: $1 BTRFS_TARGET MAPPED_NAME DEVICE

or

call: $1 OPTION_1 OPTION_2 ...

where:

 -c, --config <script>     configuration file that is sourced
 -d, --device <device>     luks encrypted disk device
 -t, --target <mnt-point>  BTRFS mount point acting as base dir
                           under it the {mirror,snapshot} subdirectories
                           are used
 -n, --name <mapped_name>  name of the crypt device mapping
 -h, --help                this help screen

EOF
  help_footer
}

directory=$(dirname $0)
. $directory/shared.sh

parse_argv "$@"
echo Formatting $DEVICE
run "$CRYPTSETUP" luksFormat "$DEVICE"
echo Opening $DEVICE as $NAME
run "$CRYPTSETUP" luksOpen "$DEVICE" "$NAME"
echo Creating filesystem on $NAME
run "$MKFS" /dev/mapper/"$NAME"
mkdir -p "$TARGET"
echo Mounting $NAME as $TARGET
run mount -o noatime /dev/mapper/"$NAME" "$TARGET"
cd "$TARGET"
echo Create mirror subvolume and snapshot base as backup destinations
run "$BTRFS" subvolume create mirror
mkdir -p snapshot
echo You can now call backup.sh and finally umount.sh

