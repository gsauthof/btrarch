This repository contains scripts for creating and managing
incremental backups using an encrypted BTRFS filesystem as
target.

The `backup.sh` script is designed to backup source filesystems
that don't use BTRFS. See `README-mixed.md` for details.

In contrast to that the `backup.py` script is for backing up
BTRFS to BTRFS. The following sections describe it in detail.


Georg Sauthoff <mail@georg.so>


## Example

Create basic configuration in `~/.config/btrarch.json`:


    {
      "destination" : {
        "device" : "/dev/disk/by-id/usb-some-id",
        "mapper_name" : "backup",
        "mount_point" : "/mnt/backup"
      },
      "source" : [
        {
          "path"         : "/home",
          "name"         : "home",
          "snapshot_dir" : "/snapshot",
          "destination"  : "/mnt/backup/example.org"
        },
        {
          "path"         : "/",
          "name"         : "slash",
          "snapshot_dir" : "/snapshot",
          "destination"  : "/mnt/backup/example.org"
        }
      ]
    }

Retention plan is the default one.

Format the destination device:

    # backup.py --init

Create first full backup:

    # backup.py

Create next incremental backup and possibly remove outdated
snapshots according to the retention plan:

    # backup.py

## Background

[BTRFS][btrfs] is a copy on write file system that supports fast
snapshotting. Thus, using it for incremental backups suggests
itself.  For encryption, the BTRFS filesystem is created on a
[luks-encrypted][luks] device-mapper device.

Advantages:

- speed
- easy retrieval - the restore of the last or any previous snapshots
  can be done via simple filesystem commands. No need to restore
  several increments on each other or to construct some kind of
  catalogue.
- data integrity - since BTRFS checksums all filesystem data, errors
  are detected. The checksums are verified during normal filesystem
  operation - but it is also possible to explicitly verify
  a complete volume (cf. btrfs-scrub(8)).

## Retention

Old local and remote snapshots are removed according to a
retention plan. The default one keeps 1 snapshot per day for the
last 7 days, after that, for 4 weeks 1 per week, after that, for
6 months, 1 per month and after that for 2 years 1 per year.

A custom retention plan can be specified in the JSON
configuration file.

In case the number of snapshots in an interval is greater than
specified in the plan, superfluous ones are randomly selected and
removed.

Snapshots are kept locally and remotely. The main reason for
keeping them also locally is convenience. All local snapshots
except the last one can be removed to free up space. The last one
is sufficient for the next incremental backup run.

## Performance

Doing an incremental backup via btrfs send/receive is very fast
because the filesystem is designed to efficiently support those
operations. In contrast, on a traditional filesystem, tools like
rsync have to traverse the complete directory tree and stat each
file.

For example, a typical incremental backup of a 250 GB SSD disk
(containing 2 BTRFS volumes), of lightly changed data, to a USB 3
external 2.5" spinning disk takes ~ 40 seconds. Including
entering a secure password (which takes 5 seconds or so).

## Directory Structure

After some runs the local snapshot directory hierarchy might look like
this:

    /snapshot
    ├── home
    │   ├── 2016-11-28T22:37:49.576739
    │   ├── 2016-12-02T22:52:22.110225
    │   ├── 2017-01-30T23:42:22.647334
    │   ├── 2017-02-06T12:23:34.267908
    │   └── 2017-02-07T19:32:40.919178
    └── slash
	├── 2016-12-05T09:11:39.474245
	├── 2016-12-11T23:47:14.647986
	├── 2017-02-06T12:23:34.267908
	└── 2017-02-07T19:32:40.919178

As expected, the structure is similar on the backup device, e.g.:

    /mnt/backup/example.org/
    ├── home
    │   ├── 2016-12-04T23:50:01.556331
    │   ├── 2016-12-05T09:11:39.474245
    │   ├── 2017-01-30T23:42:22.647334
    │   ├── 2017-02-06T12:23:34.267908
    │   └── 2017-02-07T19:32:40.919178
    └── slash
	├── 2016-12-05T09:11:39.474245
	├── 2016-12-11T23:47:14.647986
	├── 2017-02-06T12:23:34.267908
	└── 2017-02-07T19:32:40.919178

## See also

In case BTRFS is not available as a filesystem (e.g. because the
kernel is too old or the system isn't Linux) a [good alternative
is to use a solution based on Dar][darscript].

## License

[GPLv3+][gpl]

[gpl]: http://www.gnu.org/copyleft/gpl.html
[btrfs]: http://en.wikipedia.org/wiki/Btrfs
[luks]: https://gitlab.com/cryptsetup/cryptsetup
[dar]: http://dar.linux.free.fr/
[darscript]: https://bitbucket.org/gsauthof/backup-scripts/src

