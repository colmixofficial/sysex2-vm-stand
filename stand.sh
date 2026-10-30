#!/usr/bin/env bash
# =====================================================================
#  SYSEX2 3TPIF1 · VM auf den Stand des Kurses bringen (nur Lehrkraft)
#
#  Bringt eine Ubuntu-VM auf den Stand, den die Schüler nach den
#  Stunden von Kapitel 4 und 5 haben: Ordner Weber, Preisliste,
#  /srv/weber, Rechnungen und die Pakete aus Kapitel 5.
#  Gedacht für zwei VMs der Lehrkraft, damit beide gleich sind.
#
#  Benutzung (erst lesen, dann starten, wie im Kurs):
#    bash stand.sh --liste            Stunden und was dazugehört
#    bash stand.sh --pruefen          nur prüfen, nichts ändern (ohne sudo)
#    sudo bash stand.sh               Stand bis gestern (heute: vor der Stunde)
#    sudo bash stand.sh 30.10         Stand bis einschließlich 30.10.
#    sudo bash stand.sh 30.10 --upgrade      dazu apt upgrade (dauert)
#    sudo bash stand.sh 30.10 --ohne-apt     nur Dateien, keine Pakete
#
#  Sicher: löscht nichts aus deinem Home. Weicht eine Datei ab, kommt
#  die alte Fassung zuerst nach ~/.sysex2-stand/<Datum-Uhrzeit>/.
#  Ändert nur ~/Weber, ~/Weber_Sicherung, /srv/weber und Pakete.
# =====================================================================
set -u

ROT=$'\e[31m'; GRUEN=$'\e[32m'; GELB=$'\e[33m'; BLAU=$'\e[36m'; FETT=$'\e[1m'; AUS=$'\e[0m'
[ -t 1 ] || { ROT=; GRUEN=; GELB=; BLAU=; FETT=; AUS=; }

# ---------- Stunden (Datum, Nummer, Titel) ----------------------------
STUNDEN=(
  "2026-10-09|08|Die Ordner der Werkstatt anlegen"
  "2026-10-15|09|Die Preisliste mit nano schreiben"
  "2026-10-22|10|Als Administrator arbeiten"
  "2026-10-23|11|Programme installieren"
  "2026-10-29|12|Programme entfernen und aktualisieren"
  "2026-10-30|13|Suchen und finden"
)
INHALT=(
  "~/Weber/{Kunden,Rechnungen,Fotos}, mueller.txt (Termin), schmit.txt, Fotos/auto_schmit.jpg, ~/Weber_Sicherung"
  "~/Weber/preisliste.txt (9 Zeilen, Motoröl 95, Scheibenwischer 25)"
  "Preisliste: Reifenwechsel 45, Achsvermessung 79, ohne Autowäsche; /srv/weber/preisliste.txt (root)"
  "apt: htop, mc, tree"
  "mc entfernt + autoremove, htop mit purge entfernt, tree bleibt, hello aus .deb (~/hello_*.deb)"
  "Rechnungen r014 bis r018, ~/Weber/notiz.txt, apt: tealdeer (tldr), vim, git (für den Extra-Start)"
)

PRUEFEN=0; UPGRADE=0; OHNEAPT=0; ZIEL=""
for a in "$@"; do
  case "$a" in
    --liste|-l)
      echo "${FETT}SYSEX2 3TPIF1 · Stunden und Stand${AUS}"
      for i in "${!STUNDEN[@]}"; do IFS='|' read -r d n t <<<"${STUNDEN[$i]}"
        printf "  %s  Stunde %s  %-40s\n             %s\n" "$(date -d "$d" +%d.%m.)" "$n" "$t" "${INHALT[$i]}"; done
      exit 0 ;;
    --pruefen|-p) PRUEFEN=1 ;;
    --upgrade) UPGRADE=1 ;;
    --ohne-apt) OHNEAPT=1 ;;
    --hilfe|-h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    alles) ZIEL="2099-12-31" ;;
    [0-9]*.[0-9]*)
      t="${a%.}"; tag="${t%%.*}"; mon="${t#*.}"; mon="${mon%%.*}"
      ZIEL=$(printf "2026-%02d-%02d" "$((10#$mon))" "$((10#$tag))") ;;
    *) echo "${ROT}Unbekannt: $a${AUS}  (bash stand.sh --hilfe)"; exit 2 ;;
  esac
done

HEUTE=$(date +%F)
if [ -z "$ZIEL" ]; then
  # Standard: alle Stunden vor heute (am Kurstag also der Stand vor der Stunde)
  ZIEL=$(date -d "$HEUTE -1 day" +%F)
fi
bis() { [[ "$1" < "$ZIEL" || "$1" == "$ZIEL" ]]; }

# ---------- Wer, wo -----------------------------------------------------
if [ "$PRUEFEN" -eq 0 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "${ROT}Bitte mit sudo starten:${AUS} sudo bash $0 $*"
    echo "Nur prüfen geht ohne sudo: bash $0 --pruefen"
    exit 1
  fi
  BEN="${SUDO_USER:-}"
  if [ -z "$BEN" ] || [ "$BEN" = root ]; then
    echo "${ROT}Starte das Skript als normaler Benutzer mit sudo, nicht als root.${AUS}"; exit 1
  fi
else
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then BEN="$SUDO_USER"; else BEN=$(id -un); fi
fi
HOMEDIR=$(getent passwd "$BEN" | cut -d: -f6)
[ -d "$HOMEDIR" ] || { echo "${ROT}Home von $BEN nicht gefunden.${AUS}"; exit 1; }
GRP=$(id -gn "$BEN")
TS=$(date +%Y-%m-%d_%H%M%S)
BACKUP="$HOMEDIR/.sysex2-stand/$TS"
OK=0; NEU=0; ANDERS=0; FEHLT=0

ziel_text=$(date -d "$ZIEL" +%d.%m. 2>/dev/null || echo "$ZIEL")
[ "$ZIEL" = "2099-12-31" ] && ziel_text="alle Stunden"
echo "${FETT}SYSEX2 · Stand der VM für $BEN ($HOMEDIR), Ziel: bis $ziel_text${AUS}"
[ "$PRUEFEN" -eq 1 ] && echo "${BLAU}Nur prüfen, es wird nichts geändert.${AUS}"

if [ -e /var/lib/kevinwurm/start ]; then
  echo "${GELB}Achtung: KEVINWURM ist auf dieser VM aktiv. Erst: sudo bash notfall.sh im Ordner weber-turbo.${AUS}"
fi

melde() { # Zeichen Farbe Text
  printf "  %s%s%s %s\n" "$2" "$1" "$AUS" "$3"; }

sichern() { # alte Datei vor dem Überschreiben sichern
  local f="$1" rel="${1#/}"
  mkdir -p "$BACKUP/$(dirname "$rel")"
  cp -a "$f" "$BACKUP/$rel"
}

ordner() { # Pfad [root]
  local p="$1" wer="${2:-user}"
  if [ -d "$p" ]; then melde "✔" "$GRUEN" "$p"; OK=$((OK+1)); return; fi
  if [ "$PRUEFEN" -eq 1 ]; then melde "✘" "$ROT" "$p fehlt"; FEHLT=$((FEHLT+1)); return; fi
  mkdir -p "$p"
  [ "$wer" = user ] && chown "$BEN:$GRP" "$p"
  melde "+" "$BLAU" "$p angelegt"; NEU=$((NEU+1))
}

datei() { # Pfad Inhalt [root]   (Inhalt "" = leere Datei, egal was drin steht? nein: genau)
  local p="$1" inhalt="$2" wer="${3:-user}" tmp
  tmp=$(mktemp); [ -n "$inhalt" ] && printf '%s\n' "$inhalt" > "$tmp"
  if [ -f "$p" ] && cmp -s "$p" "$tmp"; then
    melde "✔" "$GRUEN" "$p"; OK=$((OK+1)); rm -f "$tmp"; return
  fi
  if [ "$PRUEFEN" -eq 1 ]; then
    if [ -f "$p" ]; then melde "≠" "$GELB" "$p hat einen anderen Inhalt"; ANDERS=$((ANDERS+1))
    else melde "✘" "$ROT" "$p fehlt"; FEHLT=$((FEHLT+1)); fi
    rm -f "$tmp"; return
  fi
  mkdir -p "$(dirname "$p")"
  if [ -f "$p" ]; then sichern "$p"; melde "✎" "$GELB" "$p angepasst (alt in ~/.sysex2-stand/$TS)"; ANDERS=$((ANDERS+1))
  else melde "+" "$BLAU" "$p angelegt"; NEU=$((NEU+1)); fi
  cat "$tmp" > "$p"; rm -f "$tmp"
  if [ "$wer" = user ]; then chown "$BEN:$GRP" "$p"; else chown root:root "$p"; chmod 644 "$p"; fi
}

hat_paket() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }
APT_UPDATE=0
apt_update() {
  [ "$APT_UPDATE" -eq 1 ] && return 0
  echo "  ${BLAU}…${AUS} sudo apt update"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || { melde "✘" "$ROT" "apt update ging nicht (Netz?)"; return 1; }
  APT_UPDATE=1
}
paket() { # name da|weg|purge
  local n="$1" soll="$2"
  if [ "$OHNEAPT" -eq 1 ]; then return; fi
  if [ "$soll" = da ]; then
    if hat_paket "$n"; then melde "✔" "$GRUEN" "Paket $n installiert"; OK=$((OK+1)); return; fi
    if [ "$PRUEFEN" -eq 1 ]; then melde "✘" "$ROT" "Paket $n fehlt"; FEHLT=$((FEHLT+1)); return; fi
    apt_update || return
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$n" >/dev/null 2>&1; then
      melde "+" "$BLAU" "Paket $n installiert"; NEU=$((NEU+1))
    else melde "✘" "$ROT" "Paket $n ließ sich nicht installieren"; FEHLT=$((FEHLT+1)); fi
  else
    if ! hat_paket "$n"; then melde "✔" "$GRUEN" "Paket $n ist nicht installiert (richtig)"; OK=$((OK+1)); return; fi
    if [ "$PRUEFEN" -eq 1 ]; then melde "≠" "$GELB" "Paket $n ist noch installiert"; ANDERS=$((ANDERS+1)); return; fi
    local wie=remove; [ "$soll" = purge ] && wie=purge
    DEBIAN_FRONTEND=noninteractive apt-get "$wie" -y -qq "$n" >/dev/null 2>&1 \
      && { melde "−" "$BLAU" "Paket $n entfernt ($wie)"; NEU=$((NEU+1)); } \
      || { melde "✘" "$ROT" "Paket $n ließ sich nicht entfernen"; FEHLT=$((FEHLT+1)); }
  fi
}

als_benutzer() { sudo -u "$BEN" -H bash -c "$1"; }

W="$HOMEDIR/Weber"
kopf() { echo; echo "${FETT}$1${AUS}"; }

# ---------- Stunde 8 · 09.10. -------------------------------------------
if bis 2026-10-09; then
  kopf "Stunde 8 · Fr 09.10. · Die Ordner der Werkstatt anlegen"
  ordner "$W"; ordner "$W/Kunden"; ordner "$W/Rechnungen"; ordner "$W/Fotos"
  datei "$W/Kunden/mueller.txt" "Termin: Montag 9 Uhr"
  datei "$W/Kunden/schmit.txt" ""
  datei "$W/Fotos/auto_schmit.jpg" ""
  S="$HOMEDIR/Weber_Sicherung"
  ordner "$S"; ordner "$S/Kunden"; ordner "$S/Rechnungen"; ordner "$S/Fotos"
  datei "$S/Kunden/mueller.txt" ""; datei "$S/Kunden/schmit.txt" ""; datei "$S/Fotos/auto_schmit.jpg" ""
  if [ -e "$W/Kunden/foto_schmit.jpg" ]; then
    melde "!" "$GELB" "$W/Kunden/foto_schmit.jpg liegt noch da (gehört nach Fotos/auto_schmit.jpg). Bleibt stehen."
  fi
fi

# ---------- Stunde 9 · 15.10. und Stunde 10 · 22.10. -----------------------
PREIS_09="Werkstatt Weber - Preisliste 2026
Motoröl wechseln: 95 Euro
Reifenwechsel: 40 Euro
Bremsen prüfen: 35 Euro
Klimaanlage füllen: 99 Euro
Inspektion klein: 149 Euro
Inspektion komplett: 289 Euro
Autowäsche: 15 Euro
Scheibenwischer wechseln: 25 Euro"
PREIS_10="Werkstatt Weber - Preisliste 2026
Motoröl wechseln: 95 Euro
Reifenwechsel: 45 Euro
Bremsen prüfen: 35 Euro
Klimaanlage füllen: 99 Euro
Inspektion klein: 149 Euro
Inspektion komplett: 289 Euro
Scheibenwischer wechseln: 25 Euro
Achsvermessung: 79 Euro"
if bis 2026-10-15; then
  kopf "Stunde 9 · Do 15.10. · Die Preisliste mit nano schreiben"
  if bis 2026-10-22; then
    melde "→" "$BLAU" "Preisliste kommt gleich im Stand von Stunde 10"
  else
    datei "$W/preisliste.txt" "$PREIS_09"
  fi
fi
if bis 2026-10-22; then
  kopf "Stunde 10 · Do 22.10. · Als Administrator arbeiten"
  datei "$W/preisliste.txt" "$PREIS_10"
  ordner /srv/weber root
  datei /srv/weber/preisliste.txt "$PREIS_10" root
  if [ -e /srv/weber/test.txt ]; then melde "!" "$GELB" "/srv/weber/test.txt aus 09.4 liegt noch da (wird im Kurs gelöscht). Bleibt stehen."; fi
fi

# ---------- Stunde 11 · 23.10. und Stunde 12 · 29.10. -----------------------
if bis 2026-10-23 && [ "$OHNEAPT" -eq 0 ]; then
  kopf "Stunde 11 · Fr 23.10. · Programme installieren"
  paket tree da
  if bis 2026-10-29; then
    melde "→" "$BLAU" "htop und mc: siehe Stunde 12 (dort wieder entfernt)"
  else
    paket htop da; paket mc da
  fi
fi
if bis 2026-10-29 && [ "$OHNEAPT" -eq 0 ]; then
  kopf "Stunde 12 · Do 29.10. · Programme entfernen und aktualisieren"
  paket mc weg
  paket htop purge
  if [ "$PRUEFEN" -eq 0 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq >/dev/null 2>&1 && melde "✔" "$GRUEN" "sudo apt autoremove"
  fi
  # hello aus einer .deb-Datei (11.3)
  if hat_paket hello && ls "$HOMEDIR"/hello_*.deb >/dev/null 2>&1; then
    melde "✔" "$GRUEN" "hello installiert, .deb liegt in ~"; OK=$((OK+1))
  elif [ "$PRUEFEN" -eq 1 ]; then
    hat_paket hello || { melde "✘" "$ROT" "Paket hello fehlt"; FEHLT=$((FEHLT+1)); }
    ls "$HOMEDIR"/hello_*.deb >/dev/null 2>&1 || { melde "✘" "$ROT" "~/hello_*.deb fehlt"; FEHLT=$((FEHLT+1)); }
  else
    apt_update
    als_benutzer "cd ~ && apt-get download hello >/dev/null 2>&1"
    if ls "$HOMEDIR"/hello_*.deb >/dev/null 2>&1; then
      (cd "$HOMEDIR" && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ./hello_*.deb >/dev/null 2>&1) \
        && { melde "+" "$BLAU" "hello aus ~/$(basename "$HOMEDIR"/hello_*.deb | head -1) installiert"; NEU=$((NEU+1)); } \
        || { melde "✘" "$ROT" "hello ließ sich nicht installieren"; FEHLT=$((FEHLT+1)); }
    else melde "✘" "$ROT" "apt download hello ging nicht (Netz?)"; FEHLT=$((FEHLT+1)); fi
  fi
  if [ "$UPGRADE" -eq 1 ] && [ "$PRUEFEN" -eq 0 ]; then
    apt_update && { echo "  ${BLAU}…${AUS} sudo apt upgrade (kann dauern)"
      DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null 2>&1 && melde "✔" "$GRUEN" "sudo apt upgrade"; }
  elif [ "$PRUEFEN" -eq 0 ]; then
    melde "·" "$BLAU" "apt upgrade übersprungen (mit --upgrade starten, wenn du es willst)"
  fi
fi

# ---------- Stunde 13 · 30.10. ---------------------------------------------
if bis 2026-10-30; then
  kopf "Stunde 13 · Fr 30.10. · Suchen und finden"
  datei "$W/Rechnungen/r014.txt" "Kunde: Schmit, Bremsen prüfen, 35 Euro"
  datei "$W/Rechnungen/r015.txt" "Kunde: Müller, Reifenwechsel, 40 Euro"
  datei "$W/Rechnungen/r016.txt" "Kunde: Schmit, Inspektion klein, 149 Euro"
  datei "$W/Rechnungen/r017.txt" "Kunde: Becker, Klimaanlage füllen, 99 Euro"
  datei "$W/Rechnungen/r018.txt" "Kunde: Becker, Scheibenwischer wechseln, 25 Euro"
  datei "$W/notiz.txt" "Herr Weber, die Rechnungen finden Sie mit grep."
  if [ "$OHNEAPT" -eq 0 ]; then
    paket tealdeer da; paket vim da; paket git da
    if [ "$PRUEFEN" -eq 0 ] && command -v tldr >/dev/null 2>&1; then
      als_benutzer "tldr --update >/dev/null 2>&1" && melde "✔" "$GRUEN" "tldr --update (Seiten geladen)" \
        || melde "!" "$GELB" "tldr --update ging nicht (Netz?), im Kurs einmal von Hand"
    fi
  fi
fi

# ---------- Zusammenfassung ---------------------------------------------------
echo
if [ "$PRUEFEN" -eq 1 ]; then
  echo "${FETT}Ergebnis:${AUS} ${GRUEN}$OK stimmen${AUS}, ${GELB}$ANDERS abweichend${AUS}, ${ROT}$FEHLT fehlend${AUS}"
  [ $((ANDERS+FEHLT)) -gt 0 ] && echo "Angleichen: sudo bash $0 $( [ "$ZIEL" = "$(date -d "$HEUTE -1 day" +%F)" ] || echo "$ziel_text")"
  exit $((ANDERS+FEHLT > 0))
else
  echo "${FETT}Fertig:${AUS} ${GRUEN}$OK waren schon richtig${AUS}, ${BLAU}$NEU neu${AUS}, ${GELB}$ANDERS angepasst${AUS}, ${ROT}$FEHLT Probleme${AUS}"
  [ -d "$BACKUP" ] && { chown -R "$BEN:$GRP" "$HOMEDIR/.sysex2-stand"; echo "Alte Fassungen: $BACKUP"; }
  echo "Kontrolle wie im Kurs: tree ~/Weber   ·   cat ~/Weber/preisliste.txt   ·   ls -l /srv/weber"
fi
