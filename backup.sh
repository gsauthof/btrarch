#!/bin/bash

# 2014-07-14, Georg Sauthoff <mail@georg.so>

# Backup script that uses rsync and BTRFS snapshots

set -e
set -u

if [ $# -lt 2 ]; then
  echo call: $0 BTRFS_DEST DIRECTORY_1 DIRECTORY_2 ...
  exit 2
fi

RSYNC=${RSYNC:-rsync}
BTRFS=${BTRFS:-btrfs}
DATE=${DATA:-date}
FIND=${FIND:-find}

DRY=${DRY:-0}

#RSYNC_FLAGS=${RSYNC_FLAGS:---itemize-changes --info=progress2,stats2,remove,backup}
#RSYNC_FLAGS=${RSYNC_FLAGS:---info=progress2,stats2,remove,backup}
# RHEL 7 does not have rsync 3.1, where --info was added
RSYNC_FLAGS=${RSYNC_FLAGS:---stats}

# how many of each to keep:
# days weeks months years
PLAN=${PLAN:-8 3 6 5}
PLAN_ARRAY=($PLAN)


BASE="$1"
shift
MIRROR="$BASE/mirror"
SNAPSHOT="$BASE/snapshot"

function run()
{
  r=0
  if [ $DRY -eq 1 ]; then
    echo dry-run: "$@"
  else
    set +e
    "$@"
    r=$?
    set -e
  fi
  return $r
}

function init()
{
  mkdir -p $SNAPSHOT/{day,week,month,year}
}
function check_dirs()
{
  for i in "$@"; do
    if [ ${i%/} != "$i" ]; then
      echo $i has a trailing slash - which instructs rsync to ommit
      echo to create the root directory on the receiving side,
      echo which does not really make sense for backups.
      exit 3
    fi
  done
}
function backup()
{
  for i in "$@"; do
    echo Backing up $i ...

    HOST=`hostname`
    DST="$MIRROR/$HOST"
    mkdir -p $DST

    if [ "$i" != "${i%:*}" ]; then
      h=${i%:*}
      n=${i#*:}
      if [ "${h/\//_}" = "$h" ]; then
        HOST=$h
        DST="$MIRROR/$HOST"
      fi
    fi

    set +e
    run "$RSYNC" --archive --whole-file --delete $RSYNC_FLAGS \
      "$i" "$DST"
    r=$?
    set -e
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
    #thresh=1
    for j in $($FIND -maxdepth 1 -type d \
                     -regextype grep -regex '^[0-9./-]\{4,\}$' | sort -r); do
      k=$((k+1))
      if [ $k -gt $thresh ]; then
        run "$BTRFS" subvolume delete --commit-after $j
      fi
    done
  done
}

init
check_dirs "$@"
backup "$@"
create_snapshots
remove_old_snapshots

