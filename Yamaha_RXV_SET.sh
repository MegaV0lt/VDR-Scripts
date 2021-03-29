#!/bin/bash

# Schaltet den Yamaha RX-V475 auf den Eingang HDMI1
# IP des RX-V475 ermitteln: ping RX-V475-A3AD55 (Beispiel)
# Man kann auch den eingestellten Netzwerknamen verwenden!
# Beim VDR-Start im Hintergrund starten (Gen2VDR) Beispiel:
# echo '/usr/local/sbin/Yamaha_RXV_SET.sh &' > /etc/vdr.d/8101_Yamaha_RXV_SET
VERSION=181031

IP='RX-V475-A3AD55'  # IP/Netzwerkname vom Yamaha RX-V Reciever
COMMAND='<YAMAHA_AV cmd="PUT"><Main_Zone><Input><Input_Sel>HDMI1</Input_Sel></Input></Main_Zone></YAMAHA_AV>'
HEADER="'Content-Type: text/xml; charset=UTF-8', 'Content-Length:' ${#COMMAND}"

[[ -z "$IP" ]] && { echo 'Bitte die IP-Adresse das Yamaha-Recievers eintragen!' ; exit 1 ;}

# Yamaha Reciever auf HDMI1 stellen
RESPONSE="$(curl --header "$HEADER" --data "$COMMAND" --silent "http://${IP}/YamahaRemoteControl/ctrl")"

if [[ "$RESPONSE" =~ RC=\"0\" ]] ; then
  echo "Befehl akzeptiert von: $IP"
else
  echo "FEHLER! Befehl abgelehnt von: $IP"
fi

# echo "Antwort vom Yamaha RX-V: $RESPONSE"

exit
