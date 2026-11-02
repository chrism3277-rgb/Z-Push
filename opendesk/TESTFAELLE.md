# Testfälle

Geprüft gegen openDesk 1.19.3 (OX App Suite, Dovecot) mit Android Mail (`Android-Mail/2026.10.19`, ActiveSync 14.0).
Zum Nachvollziehen für den betroffenen Benutzer `LOGUSERLEVEL = LOGLEVEL_WBXML` und `$specialLogUsers` in
`config.php` setzen. Die Benutzer-Logdatei enthält dann die CalDAV-Anfragen und -Antworten.

| # | Fix | Schritte | Ohne Fix | Mit Fix |
|---|---|---|---|---|
| 1 | VALARM DESCRIPTION | Termin auf dem Gerät anlegen (Standarderinnerung 10 min) | PUT → `400` `CAL-4005 Invalid alarm [alarm 0]`, Termin fehlt in OX | PUT → `201`, `VALARM` enthält `DESCRIPTION:<Betreff>` |
| 2 | PUT-Fehler melden | Termin in einem nur lesbaren Kalender anlegen | Gerät meldet Erfolg, Termin verschwindet beim nächsten Sync | Log `server refused ... with HTTP 403`, Gerät erhält Status 5 |
| 3 | ETag per PROPFIND | Termin auf dem Gerät anlegen, nächsten Sync abwarten | PUT `201` ohne ETag, HEAD leer → `O <Add>` desselben Termins → Doppel auf dem Gerät | Log `ETag via PROPFIND '1-...'`, beim nächsten Export `Found '0' changes` |
| 4 | StatMessage per Objekt-URL | Bestehenden Termin auf dem Gerät ändern | `calendar-query` mit UID-Filter liefert alle Objekte → falscher ETag → `Conflict detected. Data from PIM will be dropped` | PROPFIND auf die Objekt-URL, Änderung landet in OX |
| 5 | Zeitzone in Ortszeit | Serientermin in OX (Europe/Berlin) über die Zeitumstellung, auf dem Gerät anzeigen | `TIME_ZONE_INFORMATION` mit Umstellung 01:00 (UTC) → Gerät speichert UTC, Serie im Winter 1 h verschoben | Umstellung 03:00/02:00, `tzidFromMSTZ()` liefert wieder `Europe/Berlin` |
| 6 | Leere Gerätezeitzone | Einzelinstanz einer Serie auf dem Gerät ändern (Gerät sendet Nullzeitzone) | `TZID=Africa/Abidjan` | `TZID=Europe/Berlin` (Server-`TIMEZONE`) |
| 7 | Organizer in Ausnahmen | Einzelinstanz einer Serie auf dem Gerät ändern | PUT → `403 same-organizer-in-all-components` (Ausnahme mit `MAILTO:<login>`) | Ausnahme mit dem Organizer des Mastertermins, PUT `201`, `RECURRENCE-ID` in OX |
| 8 | `CALDAV_PERSONAL = 'AUTO'` | FolderSync | Kein Standardkalender, jede Sammlung doppelt (C und T) | Standardkalender über Principal → `schedule-inbox-URL` → `schedule-default-calendar-URL`, Kalender/Aufgaben getrennt, Fallback: erste beschreibbare Sammlung |
| 9 | `CARDDAV_DEFAULT_PATH = 'AUTO'` | Kontakt auf dem Gerät anlegen | landet im ersten Adressbuch („Gesammelte Adressen“) | landet in „Kontakte“ |
| 10 | Funktionspostfach-Login | Konto mit Benutzer `<login>@<adresse>@<domain>` anlegen | Logon scheitert an CalDAV/CardDAV | Nur Mail-Ordner, Log `shared mailbox login ..., skipping DAV` |

## Prüfung von Zeitzone und Erkennung ohne Gerät

`_GetTimezoneString('Europe/Berlin')` muss den Schlüssel `-60/-60/10/5/0/3/3/5/0/2` erzeugen
(Bias -60, Winterzeit Oktober letzte Woche Sonntag 03:00, Sommerzeit März letzte Woche Sonntag 02:00).
`tzidFromMSTZ()` muss daraus wieder `Europe/Berlin` machen und für eine Nullzeitzone (172 Byte `\0`) die
Server-Zeitzone liefern.

Für `_discover()` reichen nachgebaute PROPFIND-Antworten: Sammlungen mit `supported-calendar-component-set`
und `current-user-privilege-set` (eine davon nur `read`), Principal mit `schedule-inbox-URL`, Inbox mit bzw. ohne
`schedule-default-calendar-URL`. Ohne Default muss die erste **beschreibbare** VEVENT-Sammlung gewählt werden.
