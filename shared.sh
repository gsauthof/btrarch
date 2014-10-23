
BTRFS=${BTRFS:-btrfs}
CRYPTSETUP=${CRYPTSETUP:-cryptsetup}
DATE=${DATA:-date}
DEV_MAPPER=${DEV_MAPPER:-/dev/mapper}
FIND=${FIND:-find}
MKFS=${MKFS:-mkfs.btrfs}
RSYNC=${RSYNC:-rsync}

DRY=${DRY:-0}

function parse_argv()
{
  if [ "${1#-}" = "$1" ]; then
    set +e
    TARGET=$1
    NAME=$2
    DEVICE=$3
    set -e
    return
  fi

  prog_name=$0

  while [ $# -gt 0 ] ; do
    case $1 in
      -c|-config|--config)
        shift
        . "$1"
        shift
        ;;
      -t|-target|--target)
        shift
        TARGET=$1
        shift
        ;;
      -n|-name|--name)
        shift
        NAME=$1
        shift
        ;;
      -d|-device|--device)
        shift
        DEVICE=$1
        shift
        ;;
      -s|-source|--source)
        shift
        SOURCE+=("$1")
        shift
        ;;
      -h|-help|--help)
        help "$prog_name"
        exit 0
        ;;
      *)
        echo Ignoring option: $1
        shift
        ;;
    esac
  done
}

function help_footer()
{
  cat <<-EOF
	Note that long options can also be specified via omitting the first dash.
	
	2014-10-23, Georg Sauthoff <mail@georg.so>
	EOF
}

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


if [ $# -lt 2 ]; then
  help "$0"
  exit 2
fi

