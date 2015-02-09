This repository contains shell scripts for creating and managing
incremental backups on encrypted BTRFS filesystems.

## Author

Georg Sauthoff <mail@georg.so>

## Example

### Setup Steps

Create configuration file:

    # cat config.sh
    DEVICE=/dev/sdb
    NAME=backup
    TARGET=/mnt/backup
    SOURCE=(/home /root /etc /var example.org:/home)

Initialize disk drive:

    # bash create.sh -c config.sh

### Regular Usage

    # bash mount.sh  -c config.sh
    # bash backup.sh -c config.sh
    # bash umount.sh -c config.sh

## Overview

[BTRFS][btrfs] is a copy on write file system that supports fast
snapshotting. Thus, using it for for incremental backups suggests itself.
Basically, the backup involves simply rsyncing locations to a BTRFS mount,
creating daily/weekly etc. read-only snapshots (which are normal filesystem
locations) and that's it. For encryption, the BTRFS filesystem is
created on a [luks-encrypted][luks] device-mapper device.

Advantages:

- speed - especially when doing incremental backups I've observed for
  example a speedup of 2 against [Dar][dar]. In my tests I used rsync in
  whole-file-copy mode (which is also the default when syncing between
  local disks), thus, the speedup does not come from a reduced number of
  tranfered bytes.
- easy retrieval - the restore of the last or any previous snapshots
  can be done via simple filesystem commands. No need to restore
  several increments on each other or to construct some kind of
  catalogue.
- data integrity - since BTRFS checksums all filesystem data, errors
  are detected. The checksums are verified during normal filesystem
  operation - but it is also possible to explicitly verify
  a complete volume (cf. btrfs-scrub(8)).

## Backup Schedule

The default backup schedule used by the `backup.sh` script is:

    # days weeks months years
    PLAN=${PLAN:-8 3 6 5}

Meaning that snapshots of the last 8 days, the last 3 weaks, the last 6
months and last 5 years are retained.

Note that the creation of a new snapshot is edge-triggered. In other words,
the year, the week number etc. are extracted from the current date and are
used for creation of the corresponding snapshots, iff a snapshot with the
same name does not exist. For example, when running the script every day,
the yearly snapshot is created on January the 1st, the weekly on each
Monday, the monthly on the 1st of each month and so on.

## Directory Layout

The top level directory layout created by the `create.sh` on a
target - say - /mnt/backup is:

    /mnt/backup
    ├── mirror
    └── snapshot

When backing up two example hosts the mirror hierarchy could look like:

    /mnt/backup/mirror
    ├── foo.example.org
    │   ├── etc
    │   ├── home
    │   ├── root
    │   └── var
    └── bar.example.org
        ├── etc
        ├── home
        └── var

Where the snapshot hierarchy might look like:

    /mnt/backup/snapshot
    ├── day
    │   ├── 2014-10-10
    │   ├── 2014-10-11
    │   ├── 2014-10-12
    │   ├── 2014-10-13
    │   ├── 2014-10-14
    │   ├── 2014-10-15
    │   ├── 2014-10-23
    │   └── 2014-10-24
    ├── month
    │   ├── 2014-07
    │   ├── 2014-08
    │   ├── 2014-09
    │   └── 2014-10
    ├── week
    │   ├── 2014-41
    │   ├── 2014-42
    │   └── 2014-43
    └── year
        └── 2014

Note that there is not a snapshot for each of the last 8 days (assuming
that today is October, 24th), but rather for the last 8 days where the
backup script was executed.

Under each snapshot directory the state of the mirror directory
is frozen (read-only).

All those directory trees can be accessed using standard filesystem
operations.

## License

[GPLv3+][gpl]

[gpl]: http://www.gnu.org/copyleft/gpl.html
[btrfs]: http://en.wikipedia.org/wiki/Btrfs
[luks]: https://code.google.com/p/cryptsetup/
[dar]: http://dar.linux.free.fr/
