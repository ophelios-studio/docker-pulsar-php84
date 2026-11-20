FROM php:8.4.28-apache-bookworm

# Install utilities and libraries. No package brings its recommendations along (that alone kept exim4, a setuid MTA,
# and openssh-client in the image), and the Debian packages of the official image are brought up to date first, so
# the weekly rebuild takes their security fixes even before the official image is rebuilt. Each apt step empties the
# package lists it downloaded.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    && apt-get install -y --no-install-recommends \
    apt-utils gnupg lsb-release ca-certificates wget build-essential cron git curl zip unzip openssl dialog locales \
    libonig-dev libcurl4 libcurl4-openssl-dev supervisor libsqlite3-dev libsqlite3-0 zlib1g-dev libzip-dev libpq-dev libicu-dev libfreetype6-dev libjpeg62-turbo-dev libpng-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install APCu PHP extension
RUN pecl install apcu
RUN docker-php-ext-enable apcu --ini-name docker-php-ext-apcu.ini

# Install Freetype and GD extensions
RUN docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg
RUN docker-php-ext-install gd

# Install PHP extensions
RUN docker-php-ext-install pdo_pgsql && \
    docker-php-ext-install pgsql && \
    docker-php-ext-install curl && \
    docker-php-ext-install zip && \
    docker-php-ext-install intl && \
    docker-php-ext-install xml && \
    docker-php-ext-install mbstring && \
    docker-php-ext-install exif && \
    docker-php-ext-install gettext

# Install ssh2
RUN apt-get update && apt-get install -y --no-install-recommends \
    git libssh2-1 libssh2-1-dev \
    && rm -rf /var/lib/apt/lists/*
RUN pecl install ssh2-1.3.1
RUN docker-php-ext-enable ssh2

RUN apt-get update && \
    apt-get install -y --no-install-recommends libgmp-dev && \
    rm -rf /var/lib/apt/lists/*
RUN docker-php-ext-install gmp

# Install xdebug (but do not activate it)
RUN pecl install xdebug
RUN docker-php-ext-enable xdebug
RUN cd /usr/local/etc/php/ && mkdir -p disabled/ && mv conf.d/docker-php-ext-xdebug.ini disabled/

# Enable apache modules. mod_status is turned off: nothing reads /server-status, and a single line of configuration
# would otherwise reopen the request line of every request in flight. The build fails if it is still enabled.
RUN a2enmod rewrite headers expires \
    && a2dismod status \
    && test ! -e /etc/apache2/mods-enabled/status.load

# Install french language locale
RUN locale-gen en_CA.UTF-8
RUN locale-gen fr_CA.UTF-8
RUN update-locale

# Install cleanup
RUN rm -rf /usr/src/*

# Timezone
ENV TZ="America/Montreal"

# Mailcatcher
RUN apt-get update && apt-get install -y --no-install-recommends rubygems ruby-dev sqlite3 \
    && rm -rf /var/lib/apt/lists/*
RUN gem install mailcatcher --no-document

# Copy specific php.ini directives
COPY custom.ini /usr/local/etc/php/conf.d/base-custom.ini
COPY php2shell.ini /usr/local/etc/php/conf.d/zz-php2shell.ini

# Default virtual host, port 80 only
COPY vhosts/default.conf /etc/apache2/sites-enabled/default.conf

# AllowEncodedSlashes is not inherited from the server config into a <VirtualHost>, so it must sit inside every one,
# or a path holding %2F (an encoded slash in a route parameter) gets Apache's own HTML 404 before PHP runs. The vhost
# above carries it; Debian's 000-default.conf, still enabled and first on port 80, gets it here. The build fails
# if any enabled <VirtualHost> is left without it (a downstream image adding its own vhost must add the line too).
RUN set -eu; \
    sed -i --follow-symlinks 's#^\([[:space:]]*<VirtualHost[^>]*>\)[[:space:]]*$#\1\n\tAllowEncodedSlashes NoDecode#' \
        /etc/apache2/sites-enabled/000-default.conf; \
    total="$(grep -hciE '^[[:space:]]*<VirtualHost[[:space:]>]' /etc/apache2/sites-enabled/*.conf | awk '{n += $1} END {print n + 0}')"; \
    test "$total" -gt 0 || { echo "no <VirtualHost> is enabled" >&2; exit 1; }; \
    for vhost in /etc/apache2/sites-enabled/*.conf; do \
        vhosts="$(grep -ciE '^[[:space:]]*<VirtualHost[[:space:]>]' "$vhost" || true)"; \
        patched="$(grep -ciE '^[[:space:]]*AllowEncodedSlashes[[:space:]]+NoDecode[[:space:]]*$' "$vhost" || true)"; \
        test "$vhosts" = "$patched" || { echo "$vhost: $vhosts <VirtualHost>, $patched AllowEncodedSlashes NoDecode" >&2; exit 1; }; \
    done; \
    apache2ctl -t

# Apache names its release and distribution ("Apache/2.4.62 (Debian)") in the Server header of every response and at
# the foot of its own error pages, because Debian's security.conf ships ServerTokens OS and ServerSignature On. They
# are rewritten in that file rather than overridden from another one, so each has a single value. The build fails
# unless the enabled configuration holds exactly ServerTokens Prod and ServerSignature Off.
RUN set -eu; \
    sed -i \
        -e 's#^[[:space:]]*ServerTokens[[:space:]].*$#ServerTokens Prod#I' \
        -e 's#^[[:space:]]*ServerSignature[[:space:]].*$#ServerSignature Off#I' \
        /etc/apache2/conf-available/security.conf; \
    active="$(grep -hiE '^[[:space:]]*Server(Tokens|Signature)[[:space:]]' /etc/apache2/apache2.conf \
        /etc/apache2/conf-enabled/*.conf /etc/apache2/sites-enabled/*.conf | sed 's#^[[:space:]]*##; s#[[:space:]]*$##' | sort -u)"; \
    test "$active" = "$(printf 'ServerSignature Off\nServerTokens Prod')" || { echo "Server directives: $active" >&2; exit 1; }; \
    apache2ctl -t

# No TLS in the image: it ends in front of the container (Caddy, or the platform's edge), so there is no mod_ssl, no
# 443 vhost and no private key, which anyone pulling this public image would hold. The files of mod_ssl and
# mod_status stay in mods-available: `a2dismod ssl` or `a2dismod status` in a downstream image returns 0 on a module
# already off, but 1 once its files are gone. The build fails if any of this changes.
RUN set -eu; \
    test ! -e /etc/apache2/sites-enabled/default-ssl.conf; \
    test ! -e /etc/ssl/private/apache-selfsigned.key; \
    test -e /etc/apache2/mods-available/ssl.load; \
    test -e /etc/apache2/mods-available/status.load; \
    modules="$(apache2ctl -M 2>/dev/null)"; \
    printf '%s\n' "$modules" | grep -q ' rewrite_module ' || { echo "apache2ctl -M listed no module" >&2; exit 1; }; \
    if printf '%s\n' "$modules" | grep -qE ' (ssl|status)_module '; then echo "ssl or status is loaded" >&2; exit 1; fi

# Configure and run Supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
EXPOSE 80 1080
CMD ["/usr/bin/supervisord"]
