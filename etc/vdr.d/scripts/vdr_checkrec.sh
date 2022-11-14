#!/bin/bash
# ----
# vdr_checkrec.sh
#
# Skript um unvollständige Aufnahmen zu kennzeichnen  [67,5%]
# Zusätzlich Aufnahmen von TVScraper mit SxxExx versehen  (S01E01)
#   yavdr_funcs.sh für's Loggen
#   vdr_rec_mesg.sh für das .rec-Flag
# Skript wird vom recording_hook aufgerufen (vdr_record.sh):
#   screen -dm sh -c "/etc/vdr.d/scripts/vdr_rec_msg.sh $1 \"$2\""
# ---

# VERSION=221114

source /_config/bin/yavdr_funcs.sh

# Einstellungen
ADD_SE='true'                         # (SxxExx) anhängen, wenn in der Beschreibung gefunden
ADD_UNCOMPLETE='true'                 # [67,5%] anhängen, wenn aufnahme weniger als 99% lang

# Variablen
REC_DIR="${2%/}"                      # Sicher stellen, dass es ohne / am Ende ist
REC_FLAG="${REC_DIR}/.rec"            # Kennzeichnung für laufende Aufnahme (vdr_rec_msg.sh)
REC_INDEX="${REC_DIR}/index"          # VDR index Datei für die Länge der Aufnahme
REC_INFO="${REC_DIR}/info"            # VDR info Datei für die Framerate der Aufnahme
TIMER_FLAG="${REC_DIR}/.timer"        # Vom VDR während der Aufnahme angelegt (Inhalt: 1@vdr01)
MARKAD_PID="${REC_DIR}/markad.pid"    # MarkAD PID ist vorhanden wenn MarkAD die Aufnahme scannt
REC_INFOS="${REC_DIR}/.checkrec"      # Um die ermittelten Werte zu speichern
REC_LEN="${REC_DIR}/.rec_length"      # Angabe der Aufnahmelänge in %
: "${VIDEO:=/video}"                  # Vorgabe wenn nicht gesetzt

case "$1" in
  started)
    # Gespeicherte Werte schon vorhanden?
    if [[ -e "$REC_INFOS" ]] ; then
      f_logger "File $REC_INFOS already exists"  # Möglicher PID-Wechsel
      exit
    fi

    until [[ -e "$TIMER_FLAG" ]] ; do  # Warte auf .timer vom VDR
      #f_logger 'Waiting for timer-flag…'
      sleep 10 ; ((cnt++))
      [[ $cnt -gt 3 ]] && break  # Max. 30 Sekunden
    done

    # Datei .timer auslesen und Daten des Timers laden (Start- und Stopzeit)
    VDRTIMER=$(<"$TIMER_FLAG")  # 1@vdr01
    mapfile -t TIMER_NR < <("$SVDRPSEND" LSTT "${VDRTIMER%@*}")    # Timernummer vom VDR
    #220 vdr01 SVDRP VideoDiskRecorder 2.6.1; Thu Oct 27 15:30:24 2022; UTF-8
    #250 86 0:48:2022-10-27:1455:1539:99:99:LIVE| PK Lindner zur Herbst-Steuerschätzung:
    #221 vdr01 closing connection
    IFS=':' read -r -a VDR_TIMER <<< "${TIMER_NR[1]}"              # Trennzeichen ist ":"
    TIMER_START="${VDR_TIMER[3]}" ; TIMER_STOP="${VDR_TIMER[4]}"   # SSHH (Uhrzeit)

    # Länge des Timers ermitteln
    START="$(date +%s --date="$TIMER_START")" ; STOP="$(date +%s --date="$TIMER_STOP")"
    [[ $STOP -lt $START ]] && ((STOP+=60*60*24))  # 24 Stunden dazu (86400)
    TIMER_LENGTH=$((STOP - START))                # Länge in Sekunden

    # Ermittelte Werte für später Speichern
    { echo "VDRTIMER=$VDRTIMER" ; echo "VDR_TIMER=\"${VDR_TIMER[*]}\""
      #echo "TIMER_START=$TIMER_START" ; echo "TIMER_STOP=$TIMER_STOP"
      echo "START=$START" ; echo "STOP=$STOP"
      echo "TIMER_LENGTH=$TIMER_LENGTH"
    } > "$REC_INFOS"  # .checkrec
  ;;
  after)
    while [[ -e "$REC_FLAG" ]] ; do  # Warten, bis Aufnahme beendet ist (vdr_rec_mesg.sh)
      f_logger 'Waiting for end of recording…'
      sleep 10 ; ((cnt++))      # Warten bis Aufnahme beendet ist
      [[ $cnt -gt 3 ]] && exit  # Max. 30 Sekunden
    done
    if [[ -e "$REC_INFOS" ]] ; then  # Daten laden oder abbrechen wenn nicht vorhanden
      source "$REC_INFOS"
      [[ -z "$TIMER_LENGTH" ]] && { f_logger 'Error: TIMER_LENGTH not detected!' ; exit ;}
    else
      f_logger "Error: File $REC_INFOS not found!"
      exit
    fi

    # VDR info Datei einlesen und Werte ermitteln
    mapfile -t VDR_INFO < "$REC_INFO"  # Info-Datei vom VDR einlesen
    for line in "${VDR_INFO[@]}" ; do
      if [[ "$line" =~ ^D' ' ]] ; then  # Beschreibung
        re_s='\|Staffel: ([0-9]+)' ; re_e='\|Episode: ([0-9]+)'
        [[ "$line" =~ $re_s ]] && printf -v STAFFEL '%02d' "${BASH_REMATCH[1]}"
        [[ "$line" =~ $re_e ]] && printf -v EPISODE '%02d' "${BASH_REMATCH[1]}"
      fi  # ^D
      [[ "$line" =~ ^F' ' ]] && FRAMERATE="${line#F }"   # 25
      [[ "$line" =~ ^O' ' ]] && REC_ERRORS="${line#O }"  # 768
    done
    [[ -n "$STAFFEL" && -n "$EPISODE" ]] && SE="(S${STAFFEL}E${EPISODE})"  # (SxxExx)
    [[ -z "$FRAMERATE" ]] && { f_logger 'Error: FRAMERATE not detected!' ; exit ;}

    # Größe der index Datei ermitteln und mit Timerlänge vergleichen (index/8/Framrate=Aufnahmelänge in Sekunden)
    INDEX_SIZE=$(stat -c %s "$REC_INDEX") ; [[ -z "$INDEX_SIZE" ]] && { f_logger 'Error: INDEX_SIZE not detected!' ; exit ;}  # Dateigröße in Bytes
    REC_LENGTH=$((INDEX_SIZE / 8 / FRAMERATE)) ; [[ -z "$REC_LENGTH" ]] && { f_logger 'Error: REC_LENGTH not detected!' ; exit ;}  # Länge in Sekunden

    # %-Wert ermitteln und speichern
    RECORDED=$((REC_LENGTH * 100 * 10 / TIMER_LENGTH))  # In Promille (675 = 67,5%)
    if [[ "${#RECORDED}" -eq 1 ]] ; then
      RECORDED="0.${RECORDED}"  # 0.5
    else
      R_RIGHT="${RECORDED: -1}"  # 5
      RECORDED="${RECORDED:0:${#RECORDED}-1}.${R_RIGHT}"  # 67.5
    fi

    { echo "FRAMERATE=$FRAMERATE" ; echo "REC_ERRORS=$REC_ERRORS"
      echo "INDEX_SIZE=$INDEX_SIZE" ; echo "REC_LENGTH=$REC_LENGTH"
      echo "RECORDED=$RECORDED"
      echo "SE=$SE"
    } >> "$REC_INFOS"  # Für Debug-Zwecke

    REC_NAME="${REC_DIR%/*}"          # Verzeichnis ohne /2022-06-26.20.53.26-0.rec
    REC_NAME="${REC_NAME#${VIDEO}/}"  # /video/ am Anfang entfernen
    REC_DATE="${REC_DIR##*/}"         # 2022-06-26.20.53.26-0.rec

    if [[ "$ADD_SE" == 'true' ]] ; then
      re='\(S.*E.*\)'
      if [[ ! "$REC_NAME" =~ $re && -n "$SE" ]] ; then
        NEW_REC_NAME="${REC_NAME}__$SE"  # SxxExx hinzufügen
        f_logger "Adding $SE to ${REC_NAME} -> $NEW_REC_NAME"
      fi
    fi

    if [[ "$ADD_UNCOMPLETE" == 'true' && "${RECORDED%.*}" -lt 99 ]] ; then
      echo "$RECORDED" > "$REC_LEN"                                  # Speichern der Aufnahmelänge
      NEW_REC_NAME="${NEW_REC_NAME:-$REC_NAME}__[${RECORDED/./,}%]"  # Unvollständige Aufnahme
    fi

    # Statistik und Log
    f_logger "Recorded ${RECORDED}% of ${REC_NAME}. ${REC_ERRORS:-'?'} error(s) detected by VDR"
    printf '[%(%F %R)T] %b\n' -1 "${RECORDED}% of $REC_NAME with ${REC_ERRORS:-'?'} error(s) detected by VDR recorded" >> "${VIDEO}/checkrec.log"

    [[ "$REC_NAME" == "${NEW_REC_NAME:=$REC_NAME}" ]] && exit  # Keine weitere Aktion nötig

    while [[ -e "$MARKAD_PID" ]] ; do  # Warten, bis markad beendet ist
      #f_logger 'Waiting for markad to finish…'
      sleep 30
    done

    # Wird die Aufnahme gerade abgespielt?
    mapfile -t DBUS_STATUS < <(vdr-dbus-send /Status status.IsReplaying)
    #method return time=1666943022.845569 sender=:1.42 -> destination=:1.71 serial=1467 reply_serial=2
    #  string "The Magicians~Von alten Göttern und Monstern  (S04E11)"
    #  string "/video/The_Magicians/Von_alten_Göttern_und_Monstern__(S04E11)/2022-06-26.20.53.26-0.rec"
    #boolean true
    read -r -a STATUS_STRING <<< "${DBUS_STATUS[2]}"
    if [[ "${STATUS_STRING[2]}" =~ $2 ]] ; then   # string "" wenn nichts abgespielt wird
      f_logger "Recording $REC_NAME is cuttently playing. Exit!"
      exit
    fi

    # Verzeichnis umbenennen, wenn Aufnahme kleiner 99% (*_[63,5%]) oder SxxExx fehlt
    if [[ -d "$REC_DIR" ]] ; then  # Verzeichnis existiert noch?
      mkdir --parents "${VIDEO}/${NEW_REC_NAME}" \
        || { f_logger "Error: Failed to create ${VIDEO}/${NEW_REC_NAME}" ; exit ;}
      if mv "$REC_DIR" "${VIDEO}/${NEW_REC_NAME}/${REC_DATE}" ; then
        touch "${VIDEO}/.update"   # Aufnahmen neu einlesen
      else
        f_logger "Error: Renaming of recording $REC_DIR -> ${VIDEO}/${NEW_REC_NAME}/${REC_DATE} failed!"
      fi  # mv
    fi  # -d REC_DIR
    ;;
esac

exit
