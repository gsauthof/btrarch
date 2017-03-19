#!/usr/bin/env python3

# 2015-11-21, Georg Sauthoff

import argparse
import datetime
import glob
import itertools
import json
import logging
import os
import os.path
from os.path import basename
import random
import subprocess
from subprocess import check_call, check_output, PIPE, Popen, STDOUT
import sys
import tempfile
import time
from types import SimpleNamespace

# to run the tests: py.test-3 backup.py
import unittest
import unittest.mock as mock


btrfs      = 'btrfs'
cryptsetup = 'cryptsetup'
mount      = 'mount'
mkfs       = 'mkfs.btrfs'
umount     = 'umount'


# SimpleNamespace can be used to easily test a configuration
# without a json file, e.g.:

exdst = SimpleNamespace(
    device      = '/dev/disk/by-id/ata-TOSHIBA_MQ01UBD100_33PAT945T',
    mapper_name = 'backup',
    mount_point = '/mnt/backup')

exsrc  = [
    SimpleNamespace(path='/home', name='home', snapshot_dir='/snapshot',
                    destination='/mnt/backup/dell12'),
    SimpleNamespace(path='/', name='slash', snapshot_dir='/snapshot',
                    destination='/mnt/backup/dell12')
    ]

default_retention = [
    SimpleNamespace(days = 1,        count = 1),
    SimpleNamespace(days = 6,        count = 6),
    SimpleNamespace(days = 4*7,      count = 4),
    SimpleNamespace(days = 4*7*6,    count = 6),
    SimpleNamespace(days = 4*7*12*2, count = 2)
    ]



log_format      = '{rel_secs:6.1f} {lvl}  {message}'
log_date_format = '%Y-%m-%d %H:%M:%S'

log = logging.getLogger(__name__)


class Relative_Formatter(logging.Formatter):
  level_dict = { 10 : 'DBG',  20 : 'INF', 30 : 'WRN', 40 : 'ERR',
      50 : 'CRI' }
  def format(self, rec):
    rec.rel_secs = rec.relativeCreated/1000.0
    rec.lvl = self.level_dict[rec.levelno]
    return super(Relative_Formatter, self).format(rec)

def setup_logging():
  logging.basicConfig(format=log_format, datefmt=log_date_format,
      level=logging.DEBUG)
  logging.getLogger().handlers[0].setLevel(logging.INFO)
  logging.getLogger().handlers[0].setFormatter(
      Relative_Formatter(log_format, log_date_format, style='{'))



def setup_file_logging(filename):
  log = logging.getLogger()
  fh = logging.FileHandler(filename)
  fh.setLevel(logging.DEBUG)
  f = Relative_Formatter(log_format + ' - [%(name)s]',
      log_date_format, style='{')
  fh.setFormatter(f)
  log.addHandler(fh)


def check_output_log(*args, **kwargs):
  l = args[0] if args else []
  if type(l) is not list:
    l = [l]
  log.debug('Calling: {}'.format(' '.join([ "'{}'".format(a) for a in l])))
  r = check_output(*args, **kwargs)
  if r:
    log.debug('Output:\n{}'.format(r.decode()))
  return r

def Popen_Log(*args, **kwargs):
  l = args[0] if args else []
  if type(l) is not list:
    l = [l]
  log.debug('Calling: {}'.format(' '.join([ "'{}'".format(a) for a in l])))
  r = Popen(*args, **kwargs)
  return r

def init(device, mapper_name):
  log.info('Initialize encryption on {}'.format(device))
  check_call([cryptsetup, 'luksFormat', device])
  log.info('Opening initialized {}'.format(device))
  check_output_log([cryptsetup, 'luksOpen', device, mapper_name],
      stderr=STDOUT)
  log.info('Creating BTRFS on crypted {}'.format(device))
  check_output_log([mkfs, '{}/{}'.format('/dev/mapper', mapper_name)],
      stderr=STDOUT)
  # work around 'kernel: device-mapper: ioctl: unable to remove open device'
  # issue - cf. https://bugzilla.redhat.com/show_bug.cgi?id=1419909
  time.sleep(1)
  check_output_log([cryptsetup, 'luksClose', mapper_name],
      stderr=STDOUT)

# Incremental backup example:
# btrfs subvolume snapshot -r /home /snapshot/home/$(date -I)
# btrfs send -p /snapshot/home/$(date -I -d yesterday) \
#    /snapshot/home/$(date -I) | btrfs receive /mnt/backup/host/home

# e.g. date=today_iso, ref_date=yesterday_iso, path='/home', name='home',
# snapshot_dir='/snapshot', destination='/mnt/backup/host'
def backup(date, ref_date, path, name, snapshot_dir, destination):
  local_ss = '{}/{}/{}'.format(snapshot_dir, name, date)
  log.info('Snapshotting {} as {}'.format(path, local_ss))
  check_output_log([btrfs, 'subvolume', 'snapshot', '-r', path, local_ss ],
      stderr=STDOUT)
  log.info('Sending {} to {}/{}'.format(local_ss, destination, name))
  with tempfile.TemporaryFile() as send_err:
    ref = [ '-p', '{}/{}/{}'.format(snapshot_dir, name, ref_date) ] \
        if ref_date else []
    send = Popen_Log([btrfs, 'send'] + ref + [local_ss],
      stdout=PIPE, stderr=send_err)
    receive = Popen_Log([btrfs, 'receive', '{}/{}'.format(destination, name) ],
        stdin=send.stdout, stdout=PIPE, stderr=PIPE)
    # close one duplicate such that the close in the receiver generates
    # a SIGPIPE
    send.stdout.close()
    o = receive.communicate()
    if send_err.tell() > 0:
      send_err.seek(0)
      log.debug('btrfs send stderr: {}'.format(send_err.read().decode()))
    if o[0]:
      log.debug('btrfs receive output: {}'.format(o[0].decode()))
    if o[1]:
      log.debug('btrfs receive stderr: {}'.format(o[1].decode()))
    if receive.returncode:
      raise RuntimeError('btrfs receive failed with exit status ({})'.format(
        receive.returncode))
    send.wait()
    if send.returncode:
      raise RuntimeError('btrfs send failed with exit status ({})'.format(
        send.returncode))


# Mount example:
# cryptsetup luksOpen /dev/disk/by-id/usb-someid backup
# mount -o noatime /dev/mapper/backup /mnt/backup

def mount_backup_device(device, name, path):
  log.info('Mounting {} (named {}) at {}'.format(device, name, path))
  check_output_log([cryptsetup, 'luksOpen', device, name], stderr=STDOUT)
  check_output_log(
      [mount, '-o', 'noatime', '/dev/mapper/{}'.format(name), path],
      stderr=STDOUT)

def umount_backup_device(name, path):
  log.info('Unmounting {} at {}'.format(name, path))
  check_output_log([umount, path], stderr=STDOUT)
  check_output_log([cryptsetup, 'luksClose', name], stderr=STDOUT)

def last_date(snapshot_dir, name):
  l = sorted(glob.glob(
    '{}/{}/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*'.format(
      snapshot_dir, name)), reverse=True)
  return basename(l[0]) if l else None

def test_last_date_empty():
  with mock.patch('glob.glob', lambda x:[]):
    assert last_date('/snapshot', 'home') is None

def test_last_date():
  f_glob = lambda x : [ '/snapshot/home/'+x for x in \
      [ '2016-12-05T09:11:39.474245', '2017-01-21T01:25:57.945776',
        '2017-02-07T11:14:47.630489'] ]
  with mock.patch('glob.glob', f_glob):
    assert last_date('/snapshot', 'home') == '2017-02-07T11:14:47.630489'

def test_last_date_unsorted():
  f_glob = lambda x : [ '/snapshot/home/'+x for x in \
      [ '2017-01-21T01:25:57.945776',
        '2017-02-07T11:14:47.630489', '2016-12-05T09:11:39.474245' ] ]
  with mock.patch('glob.glob', f_glob):
    assert last_date('/snapshot', 'home') == '2017-02-07T11:14:47.630489'

# returns e.g. '2017-02-07T19:24:14.231990'
def today():
  return datetime.datetime.now().isoformat()

class Outdated_Tester(unittest.TestCase):

  retentions = [
      SimpleNamespace(days = 1        , count = 1), 
      SimpleNamespace(days = 6        , count = 6), 
      SimpleNamespace(days = 4*7      , count = 4), 
      SimpleNamespace(days = 4*7*6    , count = 6), 
      SimpleNamespace(days = 4*7*12*2 , count = 2)
      ]

  def test_example(self):
    inp = ['2015-11-10', '2015-11-11', '2015-11-12', '2015-11-16',
           '2015-11-17', '2015-11-18', '2015-11-21', '2015-11-25' ]
    l = outdated(inp, self.retentions, datetime.date(2015, 11, 25))
    self.assertEqual(l.__len__(), 2)
    self.assertEqual(set(l).__len__(), 2)
    self.assertNotIn('2015-11-21', l)
    self.assertNotIn('2015-11-25', l)
    for i in l:
      self.assertIn(i, inp[0:-2])

  def test_example_unsorted(self):
    inp = ['2015-11-10', '2015-11-11', '2015-11-12', '2015-11-16',
           '2015-11-17', '2015-11-18', '2015-11-21', '2015-11-25' ]
    x = inp.copy()
    random.shuffle(x)
    l = outdated(x, self.retentions, datetime.date(2015, 11, 25))
    self.assertEqual(l.__len__(), 2)
    self.assertEqual(set(l).__len__(), 2)
    self.assertNotIn('2015-11-21', l)
    self.assertNotIn('2015-11-25', l)
    for i in l:
      self.assertIn(i, inp[0:-2])

  def test_empty(self):
    l = outdated([], self.retentions, datetime.date(2015, 11, 25))
    self.assertFalse(l)

  def test_all_empty(self):
    l = outdated([], [], datetime.date(2015, 11, 25))
    self.assertFalse(l)

  def test_no_retentions(self):
    inp = ['2015-11-10', '2015-11-11', '2015-11-12', '2015-11-16',
           '2015-11-17', '2015-11-18', '2015-11-21', '2015-11-25' ]
    l = outdated(inp, [], datetime.date(2015, 11, 25))
    l.sort()
    self.assertEqual(l, [])

  def test_full(self):
    inp = ['2015-12-31', '2015-12-30', '2015-12-29', '2015-12-28',
           '2015-12-27', '2015-12-26', '2015-12-25', '2010-01-01' ]
    #inp.sort()
    l = outdated(inp, self.retentions, datetime.date(2015, 12, 31))
    self.assertEqual(l, ['2010-01-01'])

  def test_long_iso(self):
    inp = ['2016-11-27T00:33:58+01:00', '2016-11-28T22:37:49.576739']
    l = outdated(inp, self.retentions, datetime.date(2016, 11, 28))
    self.assertFalse(l)

  def test_always_retain_newest(self):
    inp = ['2016-11-28T18:10:23.110225', '2016-11-28T20:11:53.954313',
        '2016-11-28T22:37:49.576739']
    l = outdated(inp, self.retentions, datetime.date(2016, 11, 28))
    self.assertEqual(l.__len__(), 0)
    #self.assertTrue(l[0] in inp[:2])

class Akku:
  def __init__(self, itr):
    self.itr = itr
    self.v = []
  def __iter__(self):
    return self
  def __next__(self):
    self.v.clear()
    self.v.append(next(self.itr))
    return self.v[0]
  def tail(self):
    return self.v

class Take_While:
  def __init__(self, f, itr):
    self.f   = f
    self.a   = Akku(itr)
    self.itr = itertools.takewhile(f, self.a)
  def __iter__(self):
    return self.itr
  def tail(self):
    return self.a.tail()

def intervals(xs, days, today):
  tail = []
  ys   = iter(xs)
  os   = []
  for day in days:
    d    = today - datetime.timedelta(days=day)
    s    = d.isoformat()
    tw   = Take_While(lambda x: basename(x) < s, itertools.chain(tail, ys))
    yield  tw
    tail = tw.tail()

def outdated(xs, retentions, today):
  rs  = list(reversed(retentions))
  ivs = intervals(sorted(xs), map(lambda x:x.days,  rs), today)
  os  = list(next(ivs, []))
  for (iv, count) in zip(ivs, map(lambda x:x.count, rs)):
    ks  = list(iv)
    ts  = random.sample(ks, max(0, ks.__len__() - count))
    os += ts
  return  os



# call for local snapshots and backed-up ones
def clean(snapshot_dir, name, selector):
  l = sorted(glob.glob(
    '{}/{}/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*'.format(
      snapshot_dir, name)))
  to_be_deleted = selector(l)
  for d in to_be_deleted:
    log.info('Removing snapshot: {}'.format(d))
    check_output_log([btrfs, 'subvolume', 'delete', '--commit-after', d],
        stderr=STDOUT)

# call for local snapshots and backed-up ones
def cleanup(snapshot_dir, name, retentions, today=datetime.date.today()):
  return clean(snapshot_dir, name, lambda l: outdated(l, retentions, today))

def clean_local(snapshot_dir, name):
  return clean(snapshot_dir, name, lambda l: l[:-1])

# Example call sequence:
# mount_backup_device('/dev/disk/by-id/usb-someid', 'backup', '/mnt/backup')
# backup('2015-11-21', '2015-11-18', **exsrc[0].__dict__)
# umount_backup_device('backup', '/mnt/backup')

def run(args):
  try:
    if args.init:
      init(args.env.device, args.env.mapper_name)
      return 0
    if args.clean:
      for d in args.defs:
        clean_local(d.snapshot_dir, d.name)
      return 0
    mount_backup_device(args.env.device, args.env.mapper_name,
        args.env.mount_point)
    date = today()
    for d in args.defs:
      os.makedirs('{}/{}'.format(d.snapshot_dir, d.name), exist_ok=True)
      os.makedirs('{}/{}'.format(d.destination, d.name), exist_ok=True)
      backup(date, last_date(d.snapshot_dir, d.name), **d.__dict__)
      if not args.keep:
        cleanup(d.snapshot_dir, d.name, args.retention)
        cleanup(d.destination , d.name, args.retention)
    if not args.no_umount:
      umount_backup_device(args.env.mapper_name, args.env.mount_point)
  except subprocess.CalledProcessError as e:
    log.error('Call failed: {}, Output: {}'.format(
      e, e.output.decode() if e.output else ''))
    return 1
  return 0

def mk_arg_parser():
  p = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description = 'Incrementatlly backup BTRFS filesystems',
        epilog='''

2016, Georg Sauthoff <mail@georg.so>, GPLv3+''')
  p.add_argument('--config', default='~/.config/btrarch.json', metavar='FILE',
      help='configuration file (JSON)')
  p.add_argument('--clean', action='store_true',
      help='remove all local snapshots except the latest')
  p.add_argument('--debug', action='store_true',
      help='print debug log messages')
  p.add_argument('--init', action='store_true',
      help='initialize destination device (crypt, mkfs ...)')
  p.add_argument('--keep', action='store_true',
      help="keep all snapshot, don't apply retentions")
  p.add_argument('--log', nargs='?', metavar='FILE',
      const='backup.log', help='log all messages into FILE')
  p.add_argument('--no-umount', action='store_true',
      help='automatically umount at the end')
  p.add_argument('--quiet', '-q', action='store_true',
      help='silence output')
  return p

def parse_args(*a):
  p = mk_arg_parser()
  args = p.parse_args(*a)
  if args.debug:
    l = logging.getLogger() # root logger
    l.setLevel(logging.DEBUG)
  if args.log:
    setup_file_logging(args.log)
  if args.quiet:
    logging.getLogger().handlers[0].setLevel(logging.WARNING)
  return args

def read_config(filename, args):
  with open(filename) as f:
    t = json.load(f, object_hook=lambda d: SimpleNamespace(**d))
    args.env  = t.destination
    args.defs = t.source if 'source' in t.__dict__ else []
    args.retention = t.retention if 'retention' in t.__dict__ \
                 else default_retention

def main(*a):
  args = parse_args(*a)
  read_config(os.path.expanduser(args.config), args)
  return run(args)

if __name__ == '__main__':
  setup_logging()
  log.info(('Started at {:' + log_date_format + '}')
      .format(datetime.datetime.now()))

  sys.exit(main())

