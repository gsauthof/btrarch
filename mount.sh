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
run "$CRYPTSETUP" luksOpen "$DEVICE" "$NAME"
run mount -o noatime "$DEV_MAPPER"/"$NAME" "$TARGET"
