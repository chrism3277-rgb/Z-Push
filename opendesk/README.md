# Z-Push für openDesk

Fork von [Z-Hub/Z-Push](https://github.com/Z-Hub/Z-Push) 2.7.7 als ActiveSync-Gateway für [openDesk](https://opendesk.eu):

- **Mail:** IMAP gegen Dovecot, Versand über `postfix-ox` mit den Zugangsdaten des Geräts
- **Kalender, Aufgaben, Kontakte:** CalDAV/CardDAV gegen OX App Suite (`dav.<DOMAIN>`)
- **Funktionspostfächer:** Login `benutzer@funktionsadresse` → nur Mail

**Einrichtung, Betrieb und Weiterentwicklung: [ANLEITUNG.md](ANLEITUNG.md)**

## Änderungen gegenüber 2.7.7

Jede Änderung ist ein eigener Commit auf dem Branch `opendesk`. Gefunden wurden sie im Betrieb mit OX App Suite (openDesk 1.19) und Android Mail.

| Commit | Problem | Upstream-tauglich |
|---|---|---|
| VALARM DESCRIPTION | OX lehnt Termine mit Erinnerung ab (CAL-4005), weil `DESCRIPTION` fehlt (RFC 5545) | ja |
| PUT-Fehler melden | Abgelehnte Termine verschwinden still; HEAD überschreibt den Statuscode | ja |
| ETag per PROPFIND | OX liefert beim PUT keinen ETag → Termin wird am Gerät verdoppelt | ja |
| StatMessage per Objekt-URL | OX ignoriert den UID-Filter → Scheinkonflikt, Änderungen vom Gerät verworfen | ja |
| Zeitzone in Ortszeit | Umstellungszeit in UTC → Gerät erkennt Europe/Berlin nicht, Serien um 1 h verschoben | ja |
| Leere Gerätezeitzone | Android sendet leere Zeitzone → wurde Africa/Abidjan | ja |
| Organizer in Ausnahmen | OX: 403 same-organizer-in-all-components | ja |
| `CALDAV_PERSONAL = 'AUTO'` | Standardkalender pro Benutzer (RFC 6638), Kalender/Aufgaben getrennt | ja (optional) |
| `CARDDAV_DEFAULT_PATH = 'AUTO'` | Standardadressbuch per Name | ja (optional) |
| `DAV_SKIP_SHARED_MAILBOX_LOGIN` | Funktionspostfach-Login nur mit IMAP | eher openDesk-spezifisch |

## Image und Betrieb

Der Workflow `.github/workflows/opendesk-image.yml` baut bei jedem Push auf `opendesk` das Image
`ghcr.io/chrism3277-rgb/z-push:opendesk`. Zusätzlich gibt es ein Tag `opendesk-<sha>` pro Commit, das man fest pinnen kann.

Konfiguration über Umgebungsvariablen (siehe `entrypoint.sh`):

| Variable | Standard |
|---|---|
| `ZPUSH_DAV_SERVER` | – (Pflicht, z. B. `dav.in.example.de`) |
| `ZPUSH_IMAP_SERVER` | `dovecot.opendesk.svc.cluster.local` |
| `ZPUSH_SMTP_SERVER` | `postfix-ox.opendesk.svc.cluster.local` |
| `ZPUSH_TIMEZONE` | `Europe/Berlin` |
| `ZPUSH_LOGLEVEL` | `INFO` |
| `ZPUSH_IMAP_OPTIONS` | `/tls-sslv23/novalidate-cert/norsh` (STARTTLS zu Dovecot) |
| `ZPUSH_SHARED_MAILBOX_LOGIN` | `true` |

Kubernetes-Beispiel: `opendesk/k8s/zpush.yaml`. Der Pod löst `dav.<DOMAIN>` per `hostAliases` direkt auf den Ingress auf.

## Bekannte Grenzen

- **Dauerhaft abgelehnte Termine:** Lehnt der CalDAV-Server einen Termin ab (z. B. fehlende Schreibrechte
  auf einen öffentlichen Kalender), bekommt das Gerät Status 5 (Serverfehler) und versucht es bei jedem Sync
  erneut, bis der Termin auf dem Gerät gelöscht oder korrigiert wird. Der Grund steht im Log
  (`server refused ... with HTTP ...`). Das ist gewollt: Vorher ging der Termin ohne Meldung verloren.
- **Funktionspostfächer:** Jedes Funktionspostfach braucht auf dem Gerät ein eigenes Konto
  (Benutzer `<login>@<funktionsadresse>`). Kalender und Kontakte gibt es dort nicht.
- **Globales Adressbuch (GAL):** Nicht angebunden. Die Empfängersuche auf dem Gerät findet nur eigene Kontakte.
- **Tests:** Z-Push hat keine Unit-Tests (nur Psalm). Die Fixes wurden gegen OX App Suite und Android Mail
  geprüft. Die Testfälle stehen reproduzierbar in [TESTFAELLE.md](TESTFAELLE.md).

## Lizenz

AGPLv3 wie Z-Push. Wer eine veränderte Version als Netzwerkdienst betreibt, muss den Nutzern den Quellcode anbieten. Dieser Fork erfüllt das.
