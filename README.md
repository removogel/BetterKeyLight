# BetterKeyLight

Eine kleine macOS-Menüleisten-App (macOS 14+) zur Steuerung eines Elgato Key Light über dessen lokale HTTP-API (`http://<IP>:9123/elgato/lights`).

## Funktionen
- Glühbirnen-Symbol in der Menüleiste (gefüllt = an)
- Ein/Aus-Schalter, Helligkeit (3–100 %), Farbtemperatur (2900–7000 K), Schnellwahl-Tasten
- Einstellungen: IP-Adresse und Port manuell, Verbindungstest, „Bei Anmeldung starten“
- Zeitsteuerung: beliebig viele Regeln (Uhrzeit, Wochentage, Ein/Aus, optional Helligkeit), global abschaltbar, „Jetzt ausführen“-Knopf

## Bauen
```bash
./build.sh
```
Ergebnis: `build/BetterKeyLight.app` – nach `/Programme` ziehen und starten.
Benötigt nur die Xcode Command Line Tools.

## Hinweise
- Zeitregeln laufen nur, solange die App läuft und der Mac wach ist. Nach dem Aufwachen werden Regeln, die höchstens 10 Minuten verpasst wurden, nachgeholt.
- Beim ersten Zugriff fragt macOS ggf. nach der Berechtigung für das lokale Netzwerk – bitte erlauben.
- Der Zustand wird alle 15 s abgefragt, damit Änderungen aus der Elgato-App sichtbar werden.
