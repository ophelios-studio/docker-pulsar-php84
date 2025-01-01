[![Publish to ghcr](https://github.com/ophelios-studio/docker-pulsar-php84/actions/workflows/publish.yml/badge.svg)](https://github.com/ophelios-studio/docker-pulsar-php84/actions/workflows/publish.yml)

# Docker Pulsar PHP 8.4

Publication vers ghcr de l'image PHP (8.4) nécessaire pour les projets Pulsar. Pour publier une nouvelle version, 
simplement faire un _push_ sur la branche principale.

## Définitions

* PHP 8.4 (Apache-Bookworm)
* Composer
* XDebug
* Duplicity
* RClone
* Sudo (for Docker)
* SSH2
* MailCatcher
* Extensions PHP
  * pdo_pgsql
  * pgsql
  * curl
  * zip
  * intl
  * xml
  * mbstring
  * exif
  * gettext
  * APCu
  * GD (avec freetype)
* Modules Apache
  * rewrite
  * headers
  * expires
  * ssl

## Directives personnalisées pour PHP.ini

```ini
apc.enable_cli = 1

[xdebug]
xdebug.output_dir='/xdebug.d'
xdebug.mode = profile
xdebug.use_compression = true
```