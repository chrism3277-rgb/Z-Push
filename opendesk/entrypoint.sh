#!/bin/bash
# Konfiguriert Z-Push beim Start aus Umgebungsvariablen (Standardwerte passen fuer openDesk im Namespace opendesk)
set -euo pipefail

: "${ZPUSH_DAV_SERVER:?ZPUSH_DAV_SERVER fehlt (z. B. dav.example.org)}"
: "${ZPUSH_TIMEZONE:=Europe/Berlin}"
: "${ZPUSH_LOGLEVEL:=INFO}"
: "${ZPUSH_IMAP_SERVER:=dovecot.opendesk.svc.cluster.local}"
: "${ZPUSH_IMAP_PORT:=143}"
# STARTTLS; "tls-sslv23" statt "tls", weil c-client mit "/tls" nur TLS 1.0 spricht (Dovecot verlangt >= 1.2)
# novalidate-cert: Dovecot ist nur cluster-intern erreichbar, sein Zertifikat passt nicht zum Service-Namen
: "${ZPUSH_IMAP_OPTIONS:=/tls-sslv23/novalidate-cert/norsh}"
: "${ZPUSH_SMTP_SERVER:=postfix-ox.opendesk.svc.cluster.local}"
: "${ZPUSH_SMTP_PORT:=25}"
: "${ZPUSH_DAV_PORT:=443}"
: "${ZPUSH_SHARED_MAILBOX_LOGIN:=true}"
: "${ZPUSH_PING_MAX_LIFETIME:=900}"

Z=/usr/share/z-push

# define('NAME', ...) in einer Z-Push-Konfigdatei setzen und pruefen
setdef() {
  N="$2" V="$3" perl -pi -e 's/^(\s*)define\(\x27$ENV{N}\x27\s*,.*\);/$1define(\x27$ENV{N}\x27, $ENV{V});/' "$1"
  grep -qF "define('$2', $3);" "$1" || { echo "setdef fehlgeschlagen: $2 in $1" >&2; exit 1; }
}

C=$Z/config.php
setdef $C TIMEZONE "'${ZPUSH_TIMEZONE}'"
setdef $C BACKEND_PROVIDER "'BackendCombined'"
setdef $C USE_CUSTOM_REMOTE_IP_HEADER "'HTTP_X_FORWARDED_FOR'"
setdef $C USE_FULLEMAIL_FOR_LOGIN "true"
setdef $C STATE_DIR "'/var/lib/z-push/state/'"
setdef $C LOGFILEDIR "'/var/lib/z-push/log/'"
setdef $C LOGLEVEL "LOGLEVEL_${ZPUSH_LOGLEVEL}"
setdef $C LOGAUTHFAIL "true"
setdef $C PING_HIGHER_BOUND_LIFETIME "${ZPUSH_PING_MAX_LIFETIME}"
setdef $C DAV_SKIP_SHARED_MAILBOX_LOGIN "${ZPUSH_SHARED_MAILBOX_LOGIN}"

I=$Z/backend/imap/config.php
setdef $I IMAP_SERVER "'${ZPUSH_IMAP_SERVER}'"
setdef $I IMAP_PORT "${ZPUSH_IMAP_PORT}"
setdef $I IMAP_OPTIONS "'${ZPUSH_IMAP_OPTIONS}'"
setdef $I IMAP_SMTP_METHOD "'smtp'"
setdef $I IMAP_FOLDER_CONFIGURED "true"
setdef $I IMAP_FOLDER_SENT "'Sent'"
setdef $I IMAP_FOLDER_DRAFT "'Drafts'"
setdef $I IMAP_FOLDER_TRASH "'Trash'"
setdef $I IMAP_FOLDER_SPAM "'Junk'"
setdef $I IMAP_FOLDER_ARCHIVE "'Archive'"
setdef $I IMAP_EXCLUDED_FOLDERS "'confirmed-ham|confirmed-spam'"
# Versand mit den Zugangsdaten des Geraets (SASL + STARTTLS), Zertifikat cluster-intern nicht pruefen
H="$ZPUSH_SMTP_SERVER" PT="$ZPUSH_SMTP_PORT" perl -pi -e 's/^\$imap_smtp_params = array\(.*\);/\$imap_smtp_params = array("host" => "$ENV{H}", "port" => $ENV{PT}, "auth" => true, "username" => "imap_username", "password" => "imap_password", "verify_peer" => false, "verify_peer_name" => false, "allow_self_signed" => true);/' $I
grep -q "\"host\" => \"${ZPUSH_SMTP_SERVER}\"" $I || { echo "SMTP-Parameter nicht gesetzt" >&2; exit 1; }

K=$Z/backend/caldav/config.php
setdef $K CALDAV_PROTOCOL "'https'"
setdef $K CALDAV_SERVER "'${ZPUSH_DAV_SERVER}'"
setdef $K CALDAV_PORT "'${ZPUSH_DAV_PORT}'"
setdef $K CALDAV_PATH "'/caldav/'"
setdef $K CALDAV_PERSONAL "'AUTO'"

A=$Z/backend/carddav/config.php
setdef $A CARDDAV_PROTOCOL "'https'"
setdef $A CARDDAV_SERVER "'${ZPUSH_DAV_SERVER}'"
setdef $A CARDDAV_PORT "'${ZPUSH_DAV_PORT}'"
setdef $A CARDDAV_PATH "'/carddav/'"
setdef $A CARDDAV_DEFAULT_PATH "'AUTO'"
setdef $A CARDDAV_CONTACTS_FOLDER_NAME "'Kontakte'"

mkdir -p /var/lib/z-push/state /var/lib/z-push/log
touch /var/lib/z-push/log/z-push.log /var/lib/z-push/log/z-push-error.log
chown -R www-data:www-data /var/lib/z-push

tail -n0 -F /var/lib/z-push/log/z-push.log /var/lib/z-push/log/z-push-error.log &
exec apache2ctl -D FOREGROUND
