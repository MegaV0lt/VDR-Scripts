#!/bin/bash
# ---
# vdr_rec_msg.sh
# Skript dient zur Anzeige von "Aufnahme"- und "Beendet"-Meldugen
# ---

# VERSION=221103

source /_config/bin/yavdr_funcs.sh

[[ "${VIDEO: -1}" != '/' ]] && VIDEO+='/'
REC="$2"  # Aufnahme-Pfad

# "Aufnahme:" und "Beendet:"-Meldung verschönern
TITLE="${REC%/*}" ; TITLE="${TITLE#*$VIDEO}"

# Sofortaufnahmezeichen (@) entfernen
while [[ "${TITLE:0:1}" == '@' ]] ; do
  TITLE="${TITLE:1}"
done

# ~ durch / ersetzen, aber auch den Unterverzeichnistrenner / durch ~
while IFS='' read -r -d '' -n 1 char ; do
  case "$char" in   # Zeichenweises Suchen und Ersetzen
    '/') NTITLE+='~' ;;  # "/" durch "~"
    '~') NTITLE+='/' ;;  # "~" durch "/"
    '_') NTITLE+=' ' ;;  # "_" durch " "
      *) NTITLE+="$char"  ;;  # Originalzeichen
  esac
done < <(printf %s "$TITLE")
TITLE="$NTITLE"  # Bearbeitete Version übernehmen

# Sonderzeichen übersetzen
while [[ "${TITLE//#}" != "$TITLE" ]] ; do
  tmp="${TITLE#*#}"  # Ab dem ersten '#'
  char="${tmp:0:2}"  # Zeichen in HEX (4E = N)
  printf -v ch '%b' "\x${char}"  # ASCII-Zeichen  # ch="$(echo -e "\x$char")"
  OUT="${OUT}${TITLE%%#*}${ch}"
  TITLE="${tmp:2}"
done
TITLE="${OUT}${TITLE}"

# Sonderzeichen, welche die Anzeige stören oder nicht mit dem Dateisystem harmonieren maskieren
SPECIALCHARS='\ $ ` "'  # Teilweise Dateisystemabhängig
for ch in $SPECIALCHARS ; do
  TITLE="${TITLE//${ch}/\\${ch}}"
  REC="${REC//${ch}/\\${ch}}"
done

REC_FLAG="${REC}/.rec"  # Kennzeichnung für laufende Aufnahme
PID_WAIT=13             # Zeit, die gewartet wird, um PID-Wechsel zu erkennen (Im Log schon mal 11 Sekunden!)

case "$1" in
  before)
    if [[ -e "$REC_FLAG" ]] ; then
      f_logger "$TITLE: Recording already running? (PID change?) No Message!"
      touch "$REC_FLAG"
      exit 1  # REC_FLAG existiert - Exit
    else
      until [[ -d "$REC" ]] ; do  # Warte auf Verzeichnis
        f_logger "$TITLE: Waiting for directory…"
        sleep 0.5 ; ((cnt++))
        [[ $cnt -gt 5 ]] && break
      done
      touch "$REC_FLAG" || f_logger "Could not create REC_FLAG: $REC_FLAG"
      MESG="Aufnahme:  $TITLE"
    fi
    ;;
  after)
    if [[ -e "$REC_FLAG" ]] ; then
      sleep "$PID_WAIT"  # Wartezeit für PID-Wechsel
      printf -v ACT_DATE '%(%s)T\n' -1 ; FDATE="$(stat -c %Y "$REC_FLAG")"
      DIFF=$((ACT_DATE - FDATE))
      if [[ $DIFF -le $PID_WAIT ]] ; then  # Letzter Start vor x Sekunden!
        f_logger "$TITLE: Last start ${DIFF} seconds ago! (PID change?)"
        exit 1  # Exit
      else
        f_logger "$TITLE: Normal end of recording. Removing REC_FLAG!"
        rm -f "$REC_FLAG"
      fi
    else
      f_logger "REC_FLAG not found: $REC_FLAG"
    fi
    MESG="Beendet:  $TITLE"
    ;;
  *) ;;  # f_logger -s "ERROR: unknown state: $1"
esac

if [[ -n "$MESG" ]] ; then  # Meldung ausgeben
  sleep 0.25
  f_logger -o "$MESG"
fi
