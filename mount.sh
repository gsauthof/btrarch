#!/bin/bash

set -e
set -x

if [ -v BACKUP_CFG ] ; then
  . $BACKUP_CFG
fi

CRYPTSETUP=${CRYPTSETUP:-cryptsetup}

if [ \! -v DEV -o \! -v NAME -o \! -v MNT ]; then

  if [ $# -lt 3 ]; then
    echo call: $0 DEVICE NAME MNT_POINT
    exit 2
  fi

  DEV=$1
  NAME=$2
  MNT=$3
fi


"$CRYPTSETUP" luksOpen "$DEV" "$NAME"
mount -o noatime /dev/mapper/"$NAME" "$MNT"
