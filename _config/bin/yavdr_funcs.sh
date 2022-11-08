# This file has to be included via source command
# VERSION=221031

trap f_exit EXIT

SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"  # Eigener Pfad (Besseres $0)
SELF_NAME="${SELF##*/}"                          # Eigener Name mit Erweiterung
SVDRPSEND="$(type -p svdrpsend)"                 # svdrpsend vom VDR

source /usr/lib/vdr/config-loader.sh  # yaVDR Vorgaben
[[ -z "$LOG_LEVEL" ]] && source /etc/vdr.d/conf/vdr
[[ -z "$VDR_SOURCE_DIR" ]] && source /etc/vdr.d/conf/vdr_local.cfg

f_exit() {
  f_logger '<END>'
}

f_logger() {
  if [[ "$LOG_LEVEL" != '0' ]] ; then
    case "$1" in
      -s) PARM='-s' ; shift  ;;
      -o) PARM='-s' ; shift
          /usr/bin/vdr-dbus-send /Skin skin.QueueMessage string:"$*"  ;;
       *) PARM=''  ;;
    esac
    logger "$PARM" -t "yaVDR_$$_$PPID" "$SELF" "$*"
  fi
}

f_strstr() {  # strstr echoes nothing if s2 does not occur in s1
  [[ -n "$2" && -z "${1/*$2*}" ]] && return 0
  return 1
}

f_svdrps() {
  f_logger "$SVDRPSEND $*"
  "$SVDRPSEND" "$@"
}

f_logger '<START>'
