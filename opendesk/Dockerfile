# Z-Push (Branch opendesk) als ActiveSync-Gateway fuer openDesk
# IMAP/SMTP: Dovecot/Postfix von openDesk, Kalender/Kontakte: CalDAV/CardDAV von OX App Suite
FROM debian:bookworm-slim

ARG AWL_VERSION=r0.65

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl apache2 libapache2-mod-php8.2 \
      php8.2-imap php8.2-curl php8.2-mbstring php8.2-xml php8.2-intl php8.2-cli \
 && rm -rf /var/lib/apt/lists/*

# AWL (XMLDocument.php) fuer das CalDAV-Backend - in Debian bookworm nicht paketiert
RUN mkdir -p /usr/share/awl/inc \
 && curl -fsSL "https://gitlab.com/davical-project/awl/-/archive/${AWL_VERSION}/awl-${AWL_VERSION}.tar.gz" \
    | tar -xz --strip-components=2 -C /usr/share/awl/inc "awl-${AWL_VERSION}/inc"

COPY src/ /usr/share/z-push/
COPY opendesk/apache-zpush.conf /etc/apache2/conf-available/z-push.conf
COPY opendesk/php-zpush.ini /etc/php/8.2/apache2/conf.d/99-z-push.ini
COPY opendesk/combined-config.php /usr/share/z-push/backend/combined/config.php
COPY opendesk/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN a2enconf -q z-push \
 && echo ok > /var/www/html/healthz \
 && sed -i 's/^ErrorLog .*/ErrorLog \/dev\/stderr/' /etc/apache2/apache2.conf \
 && sed -i 's/^\(\s*\)CustomLog .*/\1CustomLog \/dev\/stdout combined/' /etc/apache2/sites-available/000-default.conf \
 && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
VOLUME ["/var/lib/z-push"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
