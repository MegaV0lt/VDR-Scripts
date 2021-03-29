#!/bin/bash

# scanepg.sh - EPG des VDR aktualisieren
# Author MegaV0lt
VERSION=210329

# --- Variablen ---
SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"  # Eigener Pfad (besseres $0)
SELF_NAME="${SELF##*/}"                     # skript.sh
CHANNELS_CONF='/etc/vdr/channels.conf'      # Lokale Kananalliste
SVDRPSEND='svdrpsend'
MAXCHANNELS=299                             # Maximal einzulesende Kanäle (channels.conf)
ZAPDELAY=15                                 # Wartezeit in Sekunden bis zum neuen Transponder
BACKUPCHANNEL='n-tv'                        # Kanal nach dem Scan, falls das Auslesen scheitert
LOG="/var/log/${SELF_NAME%.*}.log"          # Log (Auskommentieren, wenn kein extra Log gewünscht)
MAXLOGSIZE=$((10*1024))                     # In Bytes
declare -a SVDRPCHANNELS TRANSPONDERLISTE   # Array's

# --- Funktionen ---
f_log() {                                     # Gibt die Meldung auf der Konsole und im Syslog aus
  logger -t "${SELF_NAME%.*}" "$*"
  [[ -n "$LOG" ]] && printf '%(%F %T)T %s\n' -1 "$*" >> "$LOG"  # Zusätzlich in Datei schreiben
  # echo "$*"  # Zusätzlich auf der Konsole
}

# --- Start ---
f_log "$SELF_NAME #${VERSION} Start"

if [[ ! -e "$CHANNELS_CONF" ]] ; then
   f_log "$CHANNELS_CONF nicht gefunden!" >&2
   exit 1
fi

# set -x # Debug

# channels.conf in Array einlesen
mapfile -t < "$CHANNELS_CONF"

for i in "${!MAPFILE[@]}" ; do
  if [[ "${MAPFILE[i]:0:1}" == ':' ]] ; then  # Marker auslassen (: an 1. Stelle)
    # f_log "Überspringe Marker: ${MAPFILE[i]:1}"
    continue
  fi
  ((cnt+=1))  # Zähler für Kanalanzahl
  IFS=':' read -r -a TMP <<< ${MAPFILE[i]}  # In Array kopieren (Trennzeichen ist ":")
  TRANSPONDER="${TMP[1]}-${TMP[2]}-${TMP[3]}"  # Frequenz-Parameter-Quelle
  if [[ "${TRANSPONDERLISTE[@]}" =~ $TRANSPONDER ]] ; then  # Transponder schon vorhanden?
    # f_log 'Transponder schon vorhanden'
    continue
  else
    # name frequenz parameter quelle symbolrate vpid apid tpid caid sid nid tid rid
    # SVDRP-Kanal-ID (S19.2E-133-14-123)
    f_log "Neuer Transponder: $TRANSPONDER -> SVDRP: ${TMP[3]}-${TMP[10]}-${TMP[11]}-${TMP[9]} (${TMP[0]})"
    TRANSPONDERLISTE+=("$TRANSPONDER")
    SVDRPCHANNELS+=("${TMP[3]}-${TMP[10]}-${TMP[11]}-${TMP[9]}")
  fi
  [[ $cnt -ge $MAXCHANNELS ]] && break  # Nur $MAXCHANNELS einlesen
done

# Statistik
f_log "=> $cnt Kanäle eingelesen. (${CHANNELS_CONF})"
f_log "=> ${#TRANSPONDERLISTE[@]} Transponder: ${TRANSPONDERLISTE[@]}"
f_log "=> ${#SVDRPCHANNELS[@]} SVDRP-Kanäle: ${SVDRPCHANNELS[@]}"

# Aktuellen Kanal speichern
AKTCHANNEL=($("$SVDRPSEND" CHAN | grep 250))  # Array (Kanalnummer in [1])

# Kanäle durchzappen
for i in "${SVDRPCHANNELS[@]}" ; do
  f_log "=> Schalte auf Kanal-ID: $i"
  "$SVDRPSEND" CHAN "$i"
  sleep "$ZAPDELAY"
done

# Auf zwischengewspeicherten Kanal zurückschalten
if [[ -n "${AKTCHANNEL[1]}" ]] ; then
  f_log "=> Schalte auf ursprünglichen Kanal: ${AKTCHANNEL[1]}"
  "$SVDRPSEND" CHAN "${AKTCHANNEL[1]}"
else  # Kanal konnte nicht gesichert werden
  f_log "=> Schalte auf Backup-Kanal: $BACKUPCHANNEL"
  "$SVDRPSEND" CHAN "$BACKUPCHANNEL"
fi

if [[ -e "$LOG" ]] ; then  # Log-Datei umbenennen, wenn zu groß
  FILESIZE="$(stat -c %s "$LOG")"
  [[ $FILESIZE -ge $MAXLOGSIZE ]] && mv --force "$LOG" "${LOG}.old"
fi

exit
