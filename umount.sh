#!/bin/bash

set -e
set -x

if [ $# -lt 3 ]; then
  echo call: $0 DEVICE NAME MNT_POINT
  exit 2
fi

CRYPTSETUP=${CRYPTSETUP:-cryptsetup}

DEV=$1
NAME=$2
MNT=$3

umount "$MNT"
"$CRYPTSETUP" luksClose "$NAME"
