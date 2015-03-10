#!/bin/bash

# 2015-03-07, Georg Sauthoff <mail@georg.so>

set -e
set -u

function help()
{
  cat <<EOF
Mount, incrementally backup and umount using one command.

See also the help screens of the mount.sh/backup.sh/umount.sh
commands for more details.

call: $1 OPTION_1 OPTION_2 ...

where:

 -c, --config <script>     configuration file that is sourced
 -h, --help                this help screen

EOF
  help_footer
}

directory=$(dirname $0)
. $directory/shared.sh

parse_argv "$@"

"$directory"/mount.sh  "$@"
"$directory"/backup.sh "$@"
"$directory"/umount.sh "$@"

