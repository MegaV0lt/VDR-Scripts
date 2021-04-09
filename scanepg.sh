#!/bin/bash

# scanepg.sh - EPG des VDR aktualisieren
# Author MegaV0lt
# Thanks to seahawk1986 for streamdev solution
VERSION=210409

# --- Variablen ---
SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"  # Eigener Pfad (besseres $0)
SELF_NAME="${SELF##*/}"                     # skript.sh
CHANNELS_CONF='/etc/vdr/channels.conf'      # Lokale Kananalliste
SVDRPSEND='svdrpsend'                       # svdrpsend Kommando * Eventuel mit Port angeben (-p 2001)
MAXCHANNELS=70                              # Maximal einzulesende Kanäle (channels.conf)
ZAPDELAY=(10 15)                            # Wartezeit in Sekunden bis zum neuen Transponder (unverschlüsselt Verschlüsselt)
BACKUPCHANNEL='n-tv'                        # Kanal nach dem Scan, falls das Auslesen scheitert
#LOG="/var/log/${SELF_NAME%.*}.log"          # Log (Auskommentieren, wenn kein extra Log gewünscht)
MAXLOGSIZE=$((10*1024))                     # In Bytes
SCAN_MODE="streamdev"                       # Methode für Kanalscan, alternativ "svdrp"
#SCAN_MODE="svdrp"                            # Methode für Kanalscan, alternativ "svdrp"
#STREAMHOST="localhost"                      # Host für den Streamdev-Server
STREAMHOST="10.75.25.22"                      # Host für den Streamdev-Server
STREAMPORT=3000                             # Port für den Streamdev-Server

declare -a CHANNELDATA                      # Arrays
declare -A TRANSPONDERLISTE                 # assoziative Arrays

# --- Funktionen ---
f_log() {                                   # Gibt die Meldung auf der Konsole und im Syslog aus
  logger -t "${SELF_NAME%.*}" "$*"
  [[ -n "$LOG" ]] && printf '%(%F %T)T %s\n' -1 "$*" >> "$LOG"  # Zusätzlich in Datei schreiben
  [[ -t 1 ]] && echo "$*"  # Zusätzlich auf der Konsole
}

# Kanalumschaltung mit svdrp
f_svdrp_channelswitch() {
  local zapdelay="${ZAPDELAY[0]}" channel="$1" caid="$2"
  [[ "$caid" != "0" ]] && zapdelay="${ZAPDELAY[1]}"
  $SVDRPSEND CHAN "$channel"
  sleep "$zapdelay"
}

# Kanalumschaltung mit streamdev
f_streamdev_channelswitch() {
  local zapdelay="${ZAPDELAY[0]}" channel="$1" caid="$2"
  [[ "$caid" != "0" ]] && zapdelay="${ZAPDELAY[1]}"
  timeout --foreground "$zapdelay" wget -q -O "/dev/null" "http://${STREAMHOST}:${STREAMPORT}/TS/${channel}.ts" 2>&1
}

declare -A SCAN_MODES=([svdrp]=f_svdrp_channelswitch [streamdev]=f_streamdev_channelswitch)
ZAPCMD="${SCAN_MODES[$SCAN_MODE]}"

# --- Start ---
f_log "$SELF_NAME #${VERSION} Start"

if [[ ! -e "$CHANNELS_CONF" ]] ; then
  f_log "$CHANNELS_CONF nicht gefunden!" >&2
  exit 1
fi

# Kanaleinträge aus channels.conf einlesen
while read -r channel ; do
  (( cnt+=1 ))  # Zähler für Kanalanzahl
  IFS=':' read -r -a TMP <<< "$channel"  # In Array kopieren (Trennzeichen ist ":")
  TRANSPONDER="${TMP[1]}-${TMP[2]}-${TMP[3]}"  # Frequenz-Parameter-Quelle
  if [[ -z "${TRANSPONDERLISTE[$TRANSPONDER]}" ]] ; then  # Transponder noch nicht vorhanden?
    # 0name 1frequenz 2parameter 3quelle 4symbolrate 5vpid 6apid 7tpid 8caid 9sid 10nid 11tid 12rid
    # Kanal-ID (S19.2E-133-14-123)
    f_log "Neuer Transponder: $TRANSPONDER -> ${TMP[3]}-${TMP[10]}-${TMP[11]}-${TMP[9]} #${TMP[8]:0:3} (${TMP[0]})"
    TRANSPONDERLISTE[$TRANSPONDER]=1
    : "${TMP[0]%;*}"  # Kanalname ohne Provider
    # Kanalnummer:Name:Kanal-ID:CAID
    CHANNELDATA+=("${cnt}:${TMP[0]%,*}:${TMP[3]}-${TMP[10]}-${TMP[11]}-${TMP[9]}:${TMP[8]}")  # TMP[8]=CAID (0 wenn unverschlüsselt)
  fi
done < <(grep -av "^:" ${CHANNELS_CONF} | tail -n +1 | head -n "$MAXCHANNELS")

# Statistik
f_log "=> $cnt channels eingelesen. (${CHANNELS_CONF})"
f_log "=> ${#TRANSPONDERLISTE[@]} Transponder"
f_log "=> ${#CHANNELDATA[@]} channels"

if [[ "$SCAN_MODE" == 'svdrp' ]] ; then
  # Aktuellen Kanal speichern
  read -r -a AKTCHANNEL < <("$SVDRPSEND" CHAN | grep 250)  # Array (Kanalnummer in [1])
fi

# Kanäle durchzappen
for channel in "${CHANNELDATA[@]}" ; do
  IFS=':' read -r -a channeldata <<< "$channel"
  f_log "=> Schalte auf Kanal: ${channeldata[0]} ${channeldata[1]} (${channeldata[2]}) CAID: ${channeldata[3]}"
  $ZAPCMD "${channeldata[2]}" "${channeldata[3]}"  # Kanal-ID CAID
done

if [[ "$SCAN_MODE" == 'svdrp' ]] ; then
  # Auf zwischengewspeicherten Kanal zurückschalten
  if [[ -n "${AKTCHANNEL[1]}" ]] ; then
    f_log "=> Schalte auf ursprünglichen Kanal: ${AKTCHANNEL[1]}"
    "$SVDRPSEND" CHAN "${AKTCHANNEL[1]}"
  else  # Kanal konnte nicht gesichert werden
    f_log "=> Schalte auf Backup-Kanal: $BACKUPCHANNEL"
    "$SVDRPSEND" CHAN "$BACKUPCHANNEL"
  fi
fi

if [[ -e "$LOG" ]] ; then  # Log-Datei umbenennen, wenn zu groß
  FILESIZE="$(stat -c %s "$LOG")"
  [[ $FILESIZE -ge $MAXLOGSIZE ]] && mv --force "$LOG" "${LOG}.old"
fi
