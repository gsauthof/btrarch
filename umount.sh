#!/bin/bash

set -e
set -u

function help()
{
  cat <<EOF
Unmount and close encrypted BTRFS filesystem.

call: $1 BTRFS_TARGET MAPPED_NAME

or

call: $1 OPTION_1 OPTION_2 ...

where:

 -c, --config <script>     configuration file that is sourced
 -t, --target <mnt-point>  BTRFS mount point acting as base dir
                           under it the {mirror,snapshot} subdirectories
                           are used
 -n, --name <mapped_name>  name of the crypt device mapping
 -h, --help                this help screen

Note that long options can also be specified via omitting the first dash.

2014-10-23, Georg Sauthoff <mail@georg.so>
EOF

}

directory=$(dirname $0)
. $directory/shared.sh

parse_argv "$@"
run umount "$TARGET"
run "$CRYPTSETUP" luksClose "$NAME"
