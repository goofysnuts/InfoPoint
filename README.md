# InfoPoint für iOS

Begleit-App zur InfoPoint-WebApp. Damit richtest du Displays auch dann ein, wenn der
InfoPoint-Container offline ist.

- **Firmwares liegen in der App.** Jeder Abgleich mit dem Server lädt neue oder neu gebaute
  Firmwares automatisch herunter (beim Öffnen, beim Zurückkehren in die App und regelmäßig im
  Hintergrund). Ältere Stände werden erst gelöscht, wenn der neue vollständig und mit
  geprüfter MD5-Summe da ist.
- **Displays im WLAN** findet die App per Bonjour (`_infopoint._tcp`). Ist das Display nicht zu
  sehen, trägst du die IP-Adresse von Hand ein.
- **Vorlage übertragen:** Die App spielt bei Bedarf die passende Firmware per OTA auf, wartet
  den Neustart ab und schickt dann die Einstellungen (inklusive WLAN) direkt ans Display.
- **Offline-Änderungen** meldet die App dem Server, sobald er wieder erreichbar ist. Der Server
  setzt ein Display, das ihm voraus ist, in der Zwischenzeit nicht zurück.

Ohne Server funktionieren weiterhin nicht: Kalender (iCloud/ICS läuft über den Server),
Abfahrten, Nachrichten und OTA-Aufträge aus der WebApp. Wetter und Bundesliga holen ihre Daten
selbst.

## Voraussetzungen

1. Server und Firmware auf dem Stand mit **App-Schnittstelle**: Container neu bauen und jedes
   Display **einmal** über die WebApp aktualisieren (OTA oder USB). Erst danach antwortet ein
   Display der App (`GET /info`, `POST /ota`, `POST /config`, nur mit Geräte-Token).
2. iPhone und Display im selben WLAN.
3. Beim ersten Start fragt iOS nach dem Zugriff auf das **lokale Netzwerk**. Erlauben, sonst
   findet die App keine Displays. (Später: Einstellungen → Datenschutz → Lokales Netzwerk.)

## Bauen ohne Mac (GitHub Actions + Sideloadly)

Repository: `goofysnuts/InfoPoint`.

1. Jeder Push auf `main` startet unter **Actions** den Lauf „iOS-Build“ (manuell: *Run workflow*).
2. Nach ca. 5 Minuten liegt unter dem Lauf das Artefakt **InfoPoint-ipa** (ZIP mit `InfoPoint.ipa`).
3. `InfoPoint.ipa` mit **Sideloadly** aufs iPhone spielen.
4. Ein Tag `v1.0.0` erzeugt zusätzlich ein GitHub-Release mit der IPA.

Schlägt der Build fehl, hängt das Artefakt **build-log** mit dem vollständigen Xcode-Protokoll an.

## Anmeldung

- Server-Adresse wie im Browser, z. B. `http://192.168.30.145:8790` oder die Tailscale-Adresse
  `https://<nas>.<tailnet>.ts.net:8443`.
- Für `https://…:8791` (selbst signiert) den Schalter „Selbst signiertes Zertifikat erlauben“
  einschalten.
- Das Passwort liegt im iOS-Schlüsselbund. Geräte-Konfigurationen (mit WLAN-Passwörtern und
  Geräte-Token) speichert die App geschützt in ihrem Datenordner, damit sie offline arbeiten kann.
  Abmelden löscht alles.

## Aufbau

| Datei | Inhalt |
|---|---|
| `InfoPoint/AppModel.swift` | Zustand, Abgleich, Firmware-Cache, Nachmelden offline gesetzter Vorlagen |
| `InfoPoint/Clients.swift` | Server-API (`/api/app/sync`, Login, Downloads) und Display-API (`/info`, `/ota`, `/config`) |
| `InfoPoint/Discovery.swift` | Bonjour-Suche, Zuordnung über `tid` (SHA-256 des Geräte-Tokens, 12 Zeichen) |
| `InfoPoint/Transfer.swift` | Ablauf: verbinden → Firmware → Neustart → Einstellungen → melden |
| `InfoPoint/*View.swift` | Oberfläche (SwiftUI, iOS 17) |
| `project.yml` | XcodeGen-Projekt |
| `.github/workflows/build.yml` | unsignierter Build + IPA |
