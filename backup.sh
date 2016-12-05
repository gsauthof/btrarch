#!/bin/bash

# 2014-07-14, Georg Sauthoff <mail@georg.so>

set -e
set -u

function help()
{
  cat <<EOF
Incrementally backup locations to BTRFS filesystem using
a backup schedule.

call: $1 BTRFS_TARGET SOURCE_DIR_1 SOURCE_DIR_2 ...

or

call: $1 OPTION_1 OPTION_2 ...

where:

 -c, --config <script>     configuration file that is sourced
 -t, --target <mnt-point>  BTRFS mount point acting as base dir
                           under it the {mirror,snapshot} subdirectories
                           are used
 -s, --source <directory>  directory to backup
                           can be specified multiple times, where
                           directory is either a normal path or an rsync
                           source specification like host:/path
 -h, --help                this help screen

EOF
  help_footer

}

#RSYNC_FLAGS=${RSYNC_FLAGS:---itemize-changes --info=progress2,stats2,remove,backup}
#RSYNC_FLAGS=${RSYNC_FLAGS:---info=progress2,stats2,remove,backup}
# RHEL 7 does not have rsync 3.1, where --info was added
RSYNC_FLAGS=${RSYNC_FLAGS:---stats}

# how many of each to keep:
# days weeks months years
PLAN=${PLAN:-8 3 6 5}
PLAN_ARRAY=($PLAN)

directory=$(dirname $0)
. $directory/shared.sh

function check_target()
{
  if mount | grep 'on '"$TARGET"' type btrfs' > /dev/null ; then
    :
  else
    echo "BTRFS target $TARGET is not mounted - call $directory/mount.sh ..."
    exit 1
  fi
}

function set_variables()
{
  MIRROR="$TARGET/mirror"
  SNAPSHOT="$TARGET/snapshot"
}

function init()
{
  mkdir -p $SNAPSHOT/{day,week,month,year}
}
function check_dirs()
{
  for ((i=0; i<${#SOURCE[@]}; ++i)); do
    s=${SOURCE[i]}
    if [ "${s%/}" != "$s" ]; then
      cat <<-EOF
	$s has a trailing slash - which instructs rsync to ommit
	to create the root directory on the receiving side,
	which does not really make sense for backups.
	EOF
      exit 3
    fi
  done
}
function backup()
{
  for ((j=0; j<${#SOURCE[@]}; ++j)); do
    i=${SOURCE[j]}
    echo Backing up $i ...

    HOST=$(hostname)
    DST="$MIRROR/$HOST"
    mkdir -p "$DST"

    if [ "$i" != "${i%:*}" ]; then
      h=${i%:*}
      n=${i#*:}
      if [ "${h/\//_}" = "$h" ]; then
        HOST=$h
        DST="$MIRROR/$HOST"
      fi
    fi
    r=0
    run "$RSYNC" --archive --delete $RSYNC_FLAGS \
      "$i" "$DST" || r=$?
    # 24: sync warning: some files vanished before they could be transferred
    if [ $r -ne 0 -a $r -ne 24 ]; then
      echo Rsync exit code: $r
      exit $r
    fi
    echo Backing up $i ... done
  done
}
function create_snapshots()
{
  plan_idx=0
  for i in day/$($DATE +%Y-%m-%d) week/$($DATE +%Y-%V) month/$($DATE +%Y-%m) year/$($DATE +%Y) ; do
    thresh=${PLAN_ARRAY[$plan_idx]}
    if [ $thresh -ne 0 -a \! -e "$SNAPSHOT"/$i ]; then
      echo Create readonly snapshot $SNAPSHOT/$i
      run "$BTRFS" subvolume snapshot -r "$MIRROR" "$SNAPSHOT"/$i
    fi
    plan_idx=$((plan_idx+1))
  done
}
function remove_old_snapshots()
{
  cd $SNAPSHOT/year
  plan_idx=0
  for i in day week month year ; do
    cd ../$i
    k=0
    thresh=${PLAN_ARRAY[$plan_idx]}
    plan_idx=$((plan_idx+1))
    for j in $($FIND -maxdepth 1 -type d \
                     -regextype grep -regex '^[0-9./-]\{4,\}$' | sort -r); do
      k=$((k+1))
      if [ $k -gt $thresh ]; then
        run "$BTRFS" subvolume delete --commit-after $j
      fi
    done
  done
}

function backup_parse_argv()
{
  if [ "${1#-}" = "$1" ]; then
    TARGET=$1
    shift
    SOURCE=("$@")
  else
    parse_argv "$@"
  fi
}

backup_parse_argv "$@"
check_target
set_variables
init
check_dirs
backup
create_snapshots
remove_old_snapshots

