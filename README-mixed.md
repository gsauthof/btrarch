Basically, the backup involves simply rsyncing locations to a BTRFS mount,
creating daily/weekly etc. read-only snapshots (which are normal filesystem
locations) and that's it.

## Example

### Setup Steps

Create configuration file:

    # cat config.sh
    DEVICE=/dev/disk/by-id/some-id
    NAME=backup
    TARGET=/mnt/backup
    SOURCE=(/home /root /etc /var example.org:/home)

Initialize disk drive:

    # bash create.sh -c config.sh

### Regular Usage

    # bash mount.sh  -c config.sh
    # bash backup.sh -c config.sh
    # bash umount.sh -c config.sh

or all-in-one:

    # ./trinity.sh -c config.sh

## Backup Schedule

The default backup schedule used by the `backup.sh` script is:

    # days weeks months years
    PLAN=${PLAN:-8 3 6 5}

Meaning that snapshots of the last 8 days, the last 3 weeks, the last 6
months and last 5 years are retained.

Note that the creation of a new snapshot is edge-triggered. In other words,
the year, the week number etc. are extracted from the current date and are
used for creation of the corresponding snapshots, iff a snapshot with the
same name does not exist. For example, when running the script every day,
the yearly snapshot is created on January the 1st, the weekly on each
Monday, the monthly on the 1st of each month and so on.

## Performance

Especially when doing incremental backups I've observed for
example a speedup of 2 against [Dar][dar]. In my tests I used rsync in
whole-file-copy mode (which is also the default when syncing between
local disks), thus, the speedup does not come from a reduced number of
transferred bytes (as Dar also does whole-file-copying of changed
files).

## Directory Layout

The top level directory layout created by the `create.sh` on a
target - say - `/mnt/backup` is:

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

[dar]: http://dar.linux.free.fr/
