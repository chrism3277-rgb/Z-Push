# Anleitung: Z-Push für openDesk nutzen, betreiben und weiterentwickeln

Dieser Fork von [Z-Hub/Z-Push](https://github.com/Z-Hub/Z-Push) macht Z-Push 2.7.7 zum
ActiveSync-Gateway für openDesk. Smartphones (Android, iOS, Outlook-App) richten openDesk damit als
„Exchange“-Konto ein und bekommen Mail, Kalender, Aufgaben und Kontakte per Push.

- Was geändert wurde und warum: [README.md](README.md)
- Einrichtung, Betrieb und Weiterentwicklung: diese Datei
- Reproduzierbare Testfälle zu jeder Änderung: [TESTFAELLE.md](TESTFAELLE.md)

---

## 1. Aufbau

```
Smartphone ──HTTPS──> Ingress (webmail.<DOMAIN>/Microsoft-Server-ActiveSync)
                         │
                         ▼
                    Z-Push (Namespace zpush)
                    ├── IMAP (STARTTLS) ──> Dovecot          (Mail lesen)
                    ├── SMTP (STARTTLS) ──> postfix-ox       (Mail senden)
                    └── HTTPS CalDAV/CardDAV ──> dav.<DOMAIN> (OX App Suite: Kalender, Aufgaben, Kontakte)
```

Z-Push speichert **keine Passwörter**. Es reicht die Anmeldung des Geräts an Dovecot, postfix und OX
weiter, die sie über Keycloak prüfen. Auf dem Volume `/var/lib/z-push` liegen nur der Sync-Status pro
Gerät und die Logs.

## 2. Inhalt des Repositorys

| Pfad | Inhalt |
|---|---|
| `src/` | Z-Push-Quellcode (PHP) mit den openDesk-Fixes |
| `src/backend/caldav/caldav.php` | Kalender/Aufgaben, hier liegen die meisten Fixes |
| `src/backend/carddav/carddav.php` | Kontakte |
| `src/include/z_caldav.php` | CalDAV-Client (HTTP-Anfragen) |
| `opendesk/Dockerfile` | Container-Image (Debian bookworm, Apache, PHP 8.2, AWL) |
| `opendesk/entrypoint.sh` | konfiguriert Z-Push beim Start aus Umgebungsvariablen |
| `opendesk/combined-config.php` | ordnet Ordnertypen den Backends zu (Mail → IMAP, Kalender/Aufgaben → CalDAV, Kontakte → CardDAV) |
| `opendesk/k8s/zpush.yaml` | Kubernetes-Manifest (Namespace, Volume, Deployment, Service, Ingress) |
| `.github/workflows/opendesk-image.yml` | baut bei jedem Push das Image nach `ghcr.io` |

Branch: **`opendesk`**. Er beginnt beim offiziellen Tag `2.7.7`, darauf folgen die Fixes und der
openDesk-Teil (alles unter `opendesk/`).

## 3. Quellcode holen

```bash
git clone -b opendesk https://github.com/chrism3277-rgb/Z-Push.git
cd Z-Push
git log --oneline 2.7.7..opendesk     # alle Änderungen gegenüber dem Original
```

Die Änderungen gegenüber dem Original als Patch:

```bash
git diff 2.7.7 opendesk -- src/ > opendesk-z-push.patch
```

## 4. Image bauen

### Automatisch (empfohlen)

Jeder Push auf `opendesk` startet den Workflow **openDesk-Image** (GitHub → Actions). Er erzeugt:

| Tag | Bedeutung |
|---|---|
| `ghcr.io/chrism3277-rgb/z-push:opendesk` | immer der neueste Stand |
| `ghcr.io/chrism3277-rgb/z-push:opendesk-<sha>` | fester Stand eines Commits (7 Zeichen), **für den Betrieb verwenden** |

Ein Git-Tag `opendesk-<name>` erzeugt zusätzlich ein gleichnamiges Image-Tag, z. B. `opendesk-1.0`.

### Lokal

```bash
docker build -f opendesk/Dockerfile -t z-push:opendesk .
```

Das Image ist nur für amd64 getestet.

## 5. Konfiguration

Alles läuft über Umgebungsvariablen im Deployment. Die Standardwerte passen für openDesk im Namespace
`opendesk`.

| Variable | Standard | Bedeutung |
|---|---|---|
| `ZPUSH_DAV_SERVER` | **Pflicht** | Hostname der OX-DAV-Schnittstelle, z. B. `dav.in.example.de` |
| `ZPUSH_DAV_PORT` | `443` | |
| `ZPUSH_IMAP_SERVER` | `dovecot.opendesk.svc.cluster.local` | |
| `ZPUSH_IMAP_PORT` | `143` | |
| `ZPUSH_IMAP_OPTIONS` | `/tls-sslv23/novalidate-cert/norsh` | STARTTLS zu Dovecot (siehe Abschnitt 10). Wer den Wert selbst setzt, überschreibt damit auch `ZPUSH_TLS_VERIFY` für IMAP |
| `ZPUSH_TLS_VERIFY` | `false` | `true` prüft die Zertifikate von Dovecot und postfix (siehe „Zertifikate prüfen“) |
| `ZPUSH_CA_FILE` | leer | Pfad zu einer eigenen CA (PEM), die dem Truststore des Containers hinzugefügt wird |
| `ZPUSH_SMTP_SERVER` | `postfix-ox.opendesk.svc.cluster.local` | Versand mit den Zugangsdaten des Geräts |
| `ZPUSH_SMTP_PORT` | `25` | |
| `ZPUSH_TIMEZONE` | `Europe/Berlin` | Serverzeitzone, auch Ersatz, wenn ein Gerät keine Zeitzone schickt |
| `ZPUSH_LOGLEVEL` | `INFO` | `ERROR`, `WARN`, `INFO`, `DEBUG`, `WBXML` (siehe „Logs und Datenschutz“ in Abschnitt 8) |
| `ZPUSH_LOG_KEEP_DAYS` | `14` | Logs werden täglich rotiert und nach so vielen Tagen gelöscht |
| `ZPUSH_SHARED_MAILBOX_LOGIN` | `true` | Funktionspostfach-Login `<login>@<adresse>` erlauben (nur Mail) |
| `ZPUSH_PING_MAX_LIFETIME` | `900` | maximale Dauer einer Push-Verbindung in Sekunden |

Feste Einstellungen, die das Startskript immer setzt: Login mit vollem Namen erlaubt, Standardkalender und
Standardadressbuch werden automatisch erkannt (`AUTO`), IMAP-Ordner `Sent`, `Drafts`, `Trash`, `Junk`.

### Zertifikate prüfen

Die Verbindung zu OX (CalDAV/CardDAV) läuft über `dav.<DOMAIN>` und wird immer geprüft. Zu Dovecot und
postfix spricht Z-Push verschlüsselt (STARTTLS), prüft das Zertifikat im Standard aber **nicht**: Beide
zeigen das Zertifikat für `*.<DOMAIN>`, Z-Push erreicht sie jedoch über ihren Cluster-Namen
(`dovecot.opendesk.svc.cluster.local`), und der steht nicht im Zertifikat. Die Daten bleiben dabei im
Cluster-Netz. Wer die Prüfung trotzdem will (z. B. als Vorgabe im öffentlichen Sektor):

1. Dovecot und postfix unter einem Namen ansprechen, der zum Zertifikat passt. Am einfachsten per
   `hostAliases` auf die Cluster-IPs der beiden Services:
   ```bash
   kubectl -n opendesk get svc dovecot postfix-ox -o custom-columns=NAME:.metadata.name,IP:.spec.clusterIP
   ```
   ```yaml
   hostAliases:
   - ip: <Cluster-IP dovecot>
     hostnames: [imap-intern.<DOMAIN>]
   - ip: <Cluster-IP postfix-ox>
     hostnames: [smtp-intern.<DOMAIN>]
   env:
   - {name: ZPUSH_IMAP_SERVER, value: imap-intern.<DOMAIN>}
   - {name: ZPUSH_SMTP_SERVER, value: smtp-intern.<DOMAIN>}
   - {name: ZPUSH_TLS_VERIFY, value: "true"}
   ```
   Die Namen müssen nicht im DNS stehen. Eine Cluster-IP ändert sich, wenn der Service gelöscht und neu
   angelegt wird. Dann schlägt die Anmeldung fehl, bis die IP im Manifest nachgezogen ist.
2. Stammt das Zertifikat von einer eigenen CA (kein Let's Encrypt o. ä.), die CA als Datei einhängen und
   `ZPUSH_CA_FILE` auf den Pfad setzen, z. B. aus einem Secret oder einer ConfigMap mit dem CA-Zertifikat
   von openDesk. Sie gilt dann auch für die Verbindung zu `dav.<DOMAIN>`.
3. Vorab im laufenden Pod prüfen, ob Name und Kette passen:
   ```bash
   kubectl -n zpush exec deploy/zpush -- sh -c 'echo | openssl s_client -connect dovecot.opendesk.svc.cluster.local:143 \
     -starttls imap -verify_hostname imap-intern.<DOMAIN> 2>/dev/null | grep Verif'
   # erwartet: "Verification: OK"
   ```

## 6. In Kubernetes installieren

Voraussetzungen: openDesk läuft im Namespace `opendesk`, der Ingress-Controller ist haproxy-ingress und das
Wildcard-Zertifikat liegt im Secret `opendesk-certificates-tls`.

1. `opendesk/k8s/zpush.yaml` anpassen:
   - `image:` auf ein festes Tag `opendesk-<sha>` setzen
   - `ZPUSH_DAV_SERVER` auf euren `dav.<DOMAIN>`
   - `hostAliases`: IP eures Ingress-Controllers und `dav.<DOMAIN>`, damit der Pod OX direkt intern erreicht
   - Ingress-`host`: der Hostname, unter dem die Geräte Z-Push erreichen sollen
   - `storageClassName` des Volumes
2. Ausrollen:
   ```bash
   kubectl apply -f opendesk/k8s/zpush.yaml
   kubectl -n zpush rollout status deploy/zpush
   ```
3. Prüfen: `https://<host>/Microsoft-Server-ActiveSync` muss **401** mit `WWW-Authenticate: Basic realm="ZPush"` liefern.

Wichtig am Ingress sind die langen Timeouts (`timeout-server`/`timeout-client` 1000 s). Push-Verbindungen
bleiben bis zu 15 Minuten offen, mit dem Standard-Timeout von 60 s bricht Push ab.

### Update auf einen neuen Stand

```bash
# neues Image-Tag aus GitHub → Actions bzw. aus "git log" (erste 7 Zeichen)
kubectl -n zpush set image deploy/zpush zpush=ghcr.io/chrism3277-rgb/z-push:opendesk-<sha>
kubectl -n zpush rollout status deploy/zpush
```

Den Stand danach auch in `zpush.yaml` eintragen, sonst setzt das nächste `kubectl apply` ihn zurück.
Die Geräte merken vom Update nichts, ihr Sync-Status liegt auf dem Volume.

## 7. Geräte einrichten

**Eigenes Konto**

| Feld | Wert |
|---|---|
| Kontotyp | Exchange / ActiveSync |
| E-Mail | eigene Adresse, z. B. `vorname.nachname@firma.de` |
| Benutzer | openDesk-Login (z. B. `vnachname`) oder E-Mail-Adresse |
| Passwort | openDesk-Passwort |
| Server | `webmail.<DOMAIN>` (bzw. der Ingress-Host) |
| Domain | leer |

**Funktionspostfach**: ein **eigenes** Konto pro Postfach (es gibt dort nur Mail)

| Feld | Wert |
|---|---|
| E-Mail | die Adresse, die Empfänger sehen sollen, z. B. `info@firma.de` |
| Benutzer | `<eigener-login>@<adresse-des-funktionspostfachs-in-opendesk>`, z. B. `vnachname@info@in.firma.de` |
| Passwort | das **eigene** openDesk-Passwort |

Der Benutzer braucht in openDesk Rechte auf das Funktionspostfach. Gibt es auf dem Gerät schon ein Konto
mit demselben Benutzernamen, lässt Android kein zweites zu: erst das alte Konto entfernen.

**Zwei-Faktor-Anmeldung (Authenticator)**: Ein Konto, für das in Keycloak ein Authenticator (OTP)
eingerichtet ist, kann ActiveSync **nicht** nutzen. Z-Push reicht nur Benutzer und Passwort weiter, Dovecot
prüft sie per Passwort-Anmeldung („Direct Grant“) bei Keycloak, und Keycloak verlangt dort für solche Konten
zusätzlich den Einmalcode. Den kann ein ActiveSync-Gerät nicht mitschicken. Das Gerät meldet „Anmeldung
fehlgeschlagen“, als wäre das Passwort falsch. Ein angehängter Einmalcode hinter dem Passwort hilft nicht,
App-Passwörter gibt es in openDesk nicht.

- Richtet ein Benutzer den Authenticator ein, während sein Gerät schon verbunden ist, bricht die
  Synchronisierung wenige Minuten später ab (so lange merkt sich Dovecot eine erfolgreiche Anmeldung).
- Umgekehrt heißt das: ActiveSync-Zugänge sind nur durch das Passwort geschützt. Wer Z-Push anbietet,
  sollte den Endpunkt nicht offen ins Internet stellen (z. B. nur per VPN) oder das bewusst entscheiden.
- Geprüft mit openDesk 1.19.3 und einem Testkonto: mit Authenticator HTTP 401, nach Entfernen des
  Authenticators wieder Anmeldung und Ordnerliste.

**Absenderadresse**: Wenn intern andere Adressen gelten als extern (z. B. `@in.firma.de`), schreibt
postfix-ox den Absender um. Damit das auch für Z-Push gilt, braucht postfix-ox

```
local_header_rewrite_clients = permit_inet_interfaces, permit_sasl_authenticated
sender_canonical_maps = lmdb:/etc/postfix/sender_canonical.map
```

In openDesk geht das über `customization.release.postfixOx` → `postfix.overrides`.

## 8. Betrieb

### Logs

```bash
kubectl -n zpush logs deploy/zpush -f            # Apache-Zugriffe + Z-Push-Log
kubectl -n zpush exec deploy/zpush -- tail -f /var/lib/z-push/log/z-push-error.log
```

### Logs und Datenschutz

Die Logs enthalten **personenbezogene Daten**. Wer Z-Push betreibt, sollte das in sein
Verarbeitungsverzeichnis und sein Löschkonzept aufnehmen.

| Loglevel | Inhalt |
|---|---|
| `ERROR`, `WARN` | Fehler und Warnungen mit Loginname, bei abgelehnten Anmeldungen auch die IP-Adresse |
| `INFO` (Standard) | zusätzlich jede Anfrage: Loginname, Geräte-ID und Gerätetyp, IP-Adresse, Zeitpunkt, Befehl, Ordnernamen. **Keine** Mail- oder Termininhalte |
| `DEBUG` | zusätzlich technische Details zu einzelnen Elementen (Kennungen, Pfade, Serverantworten) |
| `WBXML` | zusätzlich der **vollständige Inhalt** jeder Synchronisation: Mails, Termine, Aufgaben, Kontakte |

- **Sparsam loggen:** Für den Dauerbetrieb genügt `ZPUSH_LOGLEVEL=WARN`. `INFO` ist der Standard, weil
  die Fehlersuche in Abschnitt 10 darauf aufbaut (z. B. ob ein Gerät Push nutzt). `DEBUG` und `WBXML` nie
  dauerhaft für alle einschalten.
- **Detail-Log nur gezielt und befristet:** Das ausführliche Log für einen einzelnen Benutzer (nächster
  Abschnitt) enthält dessen Mails und Termine im Klartext. Nur mit Wissen des Benutzers einschalten, nach
  der Fehlersuche wieder ausschalten und die Datei sofort löschen.
- **Aufbewahrung:** Die Logs unter `/var/lib/z-push/log` werden täglich rotiert und nach
  `ZPUSH_LOG_KEEP_DAYS` Tagen (Standard 14) gelöscht, auch vergessene Detail-Logs.
- **Container-Log:** Das Apache-Zugriffslog und eine Kopie des Z-Push-Logs gehen zusätzlich in die
  Standardausgabe des Pods (`kubectl logs`). Dort stehen Loginname und Geräte-ID in der Adresse jeder
  Anfrage. Sammelt ein zentrales Logsystem die Pod-Logs ein, gelten dessen Fristen und Zugriffsrechte.
- **Zugriff:** Lesen kann die Logs, wer im Namespace `zpush` `exec` ausführen oder das Volume einhängen
  darf. Diese Rechte entsprechend knapp halten.

### Geräte verwalten (z-push-admin)

```bash
ZA='kubectl -n zpush exec deploy/zpush -- su -s /bin/sh www-data -c'
$ZA 'php /usr/share/z-push/z-push-admin.php -a list'                              # alle Geräte
$ZA 'php /usr/share/z-push/z-push-admin.php -a list -u <login> -d <geraete-id>'   # Status, Sync-Fortschritt, Fehler
$ZA 'php /usr/share/z-push/z-push-admin.php -a resync -u <login> -d <geraete-id>' # Neusynchronisierung erzwingen
$ZA 'php /usr/share/z-push/z-push-admin.php -a remove -u <login> -d <geraete-id>' # Gerät entfernen
$ZA 'php /usr/share/z-push/z-push-admin.php -a wipe -u <login> -d <geraete-id>'   # Fernlöschung beim nächsten Sync
```

### Ausführliches Log für einen Benutzer

Zum Beispiel wenn ein Termin nicht ankommt. Diese Änderung gilt nur bis zum nächsten Neustart des Pods.

```bash
kubectl -n zpush exec deploy/zpush -- sh -c "sed -i \
  \"s/define('LOGUSERLEVEL', LOGLEVEL_DEVICEID);/define('LOGUSERLEVEL', LOGLEVEL_WBXML);/; \
   s/^    \\\$specialLogUsers = array();/    \\\$specialLogUsers = array('<login>');/\" \
  /usr/share/z-push/config.php"
# Log: /var/lib/z-push/log/<login>-<geraete-id>.log
```

**Achtung:** Diese Datei enthält die Mails, Termine und Kontakte des Benutzers im Klartext (siehe „Logs und
Datenschutz“). Nach der Fehlersuche den Pod neu starten und die Datei löschen:

```bash
kubectl -n zpush rollout restart deploy/zpush
kubectl -n zpush exec deploy/zpush -- sh -c 'rm -v /var/lib/z-push/log/<login>-*.log*'
```

## 9. Weiterentwickeln

### Ablauf

```bash
git checkout opendesk
# ... Änderung in src/ ...
php -l src/backend/caldav/caldav.php          # Syntax prüfen (PHP 8.2)
docker build -f opendesk/Dockerfile -t z-push:test .
git commit -m "CalDAV: <was> - <warum>"
git push origin opendesk                       # baut das Image automatisch
```

Zum Prüfen gegen einen Server braucht man keine Geräte. Die CalDAV-Antworten von OX lassen sich mit `curl`
abfragen (`PROPFIND`, `REPORT`), Vorgehen und Beispiele stehen in [TESTFAELLE.md](TESTFAELLE.md).

### Regeln für Änderungen

- **Ein Fehler, ein Commit.** In der Nachricht stehen das Symptom, die Ursache und die Lösung, auf Englisch,
  falls es später upstream gehen soll.
- **Kommentare im Code auf Englisch.** So bleibt der Code für die Z-Push-Maintainer lesbar.
- **Serverspezifisches Verhalten abschaltbar machen** (Konstante in `config.php`, Standard „aus“), damit sich
  für andere Server nichts ändert. Beispiele: `CALDAV_PERSONAL = 'AUTO'`, `DAV_SKIP_SHARED_MAILBOX_LOGIN`.
- **openDesk-Spezifisches nur unter `opendesk/`.** Dazu gehören Image, Startskript und Manifest.

### Auf eine neue Z-Push-Version heben

```bash
git remote add upstream https://github.com/Z-Hub/Z-Push.git
git fetch upstream --tags
git checkout -b opendesk-<neue-version> opendesk
git rebase --onto <neues-tag> 2.7.7          # Fixes auf die neue Version setzen
# Konflikte lösen, ggf. sind Fixes upstream schon enthalten -> Commit weglassen
```

Danach alle Testfälle aus TESTFAELLE.md erneut prüfen.

### Fixes an Z-Push zurückgeben

Die Commits unter `src/` sind so geschrieben, dass sie einzeln als Pull Request an
[Z-Hub/Z-Push](https://github.com/Z-Hub/Z-Push) gehen können: je ein PR pro Commit, mit dem passenden Testfall
aus TESTFAELLE.md als Beschreibung. Der Commit zu `DAV_SKIP_SHARED_MAILBOX_LOGIN` und alles unter `opendesk/`
sind openDesk-spezifisch.

## 10. Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| Gerät: „Anmeldung fehlgeschlagen“ | Benutzer/Passwort falsch, oder beim Funktionspostfach fehlen die Rechte. `z-push-error.log` zeigt `failed to authenticate user` |
| „Anmeldung fehlgeschlagen“, obwohl das Passwort stimmt | Für das Konto ist ein Authenticator (2FA) eingerichtet (Abschnitt 7). Im Z-Push-Log sieht das aus wie ein falsches Passwort, im Keycloak-Log steht `LOGIN_ERROR` mit `clientId="opendesk-dovecot-grant"` und `error="invalid_user_credentials"` |
| Gerät: „Fehler. Versuchen Sie es später erneut“, im Log aber Provision/FolderSync erfolgreich | Auf dem Gerät gibt es schon ein Konto mit demselben Benutzernamen. Altes Konto entfernen |
| Termine vom Gerät kommen nicht in OX an | Log nach `server refused` durchsuchen, dort steht der Grund (z. B. keine Schreibrechte). Danach ausführliches Log (Abschnitt 8) |
| Termine aus OX kommen erst nach Minuten | Gerät nutzt kein Push. Im Log stehen dann keine `cmd='Ping'`. Auf dem Gerät „Synchronisierung: Push/Automatisch“ einstellen |
| Push bricht ständig ab | Ingress-Timeouts zu kurz (Abschnitt 6) |
| Absender ist die interne `@in.`-Adresse | postfix-ox ohne `local_header_rewrite_clients` bzw. ohne Eintrag in `sender_canonical.map` (Abschnitt 7) |
| `SSL negotiation failed` zu Dovecot | `ZPUSH_IMAP_OPTIONS` mit `/tls` statt `/tls-sslv23`. c-client spricht mit `/tls` nur TLS 1.0 |
| Mit `ZPUSH_TLS_VERIFY=true` scheitert jede Anmeldung, im Log `Certificate failure` | Servername passt nicht zum Zertifikat oder die CA ist unbekannt (Abschnitt 5, „Zertifikate prüfen“) |
| Pod startet, Ingress liefert 503 | Pod noch nicht bereit (`kubectl -n zpush get pods`) oder Service im Namespace `opendesk` fehlt |
| Uhrzeiten von Serien nach der Zeitumstellung verschoben | Gerät hat den Termin vor dem Zeitzonen-Fix bekommen. Serie in OX neu anlegen oder Gerät per `resync` neu synchronisieren |

## 11. Lizenz

AGPLv3 wie Z-Push. Wer diese Version als Dienst für andere betreibt, muss den Nutzern den Quellcode
anbieten. Ein Link auf dieses Repository genügt.
