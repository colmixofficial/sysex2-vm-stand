# SYSEX2 3TPIF1 · VM auf den Kursstand bringen

Für die Lehrkraft: bringt eine Ubuntu-VM auf den Stand, den die Klasse nach den Stunden von Kapitel 4 und 5 hat (Ordner Weber, Preisliste, /srv/weber, Rechnungen, Pakete). So sind mehrere VMs gleich.

```
git clone https://github.com/colmixofficial/sysex2-vm-stand
cd sysex2-vm-stand
less stand.sh                  # erst lesen
bash stand.sh --liste          # Stunden und was dazugehört
bash stand.sh --pruefen        # nur prüfen, ändert nichts
sudo bash stand.sh             # Stand bis gestern
sudo bash stand.sh 30.10       # Stand bis einschließlich 30.10.
```

Optionen: `--upgrade` (zusätzlich apt upgrade), `--ohne-apt` (nur Dateien).
Löscht nichts im Home. Abweichende Dateien kommen vorher nach `~/.sysex2-stand/<Zeitstempel>/`.

Ohne git: `wget https://raw.githubusercontent.com/colmixofficial/sysex2-vm-stand/main/stand.sh`
