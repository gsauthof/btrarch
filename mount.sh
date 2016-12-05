#!/bin/bash

set -e
set -u

function help()
{
  cat <<EOF
Opens and mounts an encrypted BTRFS filesystem.

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
if lsblk -l -o fstype,mountpoint "$DEVICE" \
  | grep 'btrfs *'"$TARGET" >/dev/null ; then
  :
else
  run "$CRYPTSETUP" luksOpen "$DEVICE" "$NAME"
fi
if lsblk -l -o fstype,mountpoint "$DEV_MAPPER"/"$NAME" \
  | grep 'btrfs *'"$TARGET" >/dev/null ; then
  :
else
  run mount -o noatime "$DEV_MAPPER"/"$NAME" "$TARGET"
fi
