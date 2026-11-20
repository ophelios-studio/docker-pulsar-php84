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

## Configuration Apache

* `AllowEncodedSlashes NoDecode` dans chaque `<VirtualHost>` activé (`default.conf` et le `000-default.conf` de
  Debian) : un `%2F` dans un chemin se rend à PHP au lieu de recevoir la page 404 d'Apache. La directive ne s'hérite
  pas de la configuration du serveur, donc un _vhost_ ajouté par une image dérivée doit la porter lui-même.
* `ServerTokens Prod` et `ServerSignature Off` (réécrits dans `security.conf`) : l'en-tête `Server` vaut simplement
  `Apache` et les pages d'erreur d'Apache ne nomment aucune version.
* `mod_status` est désactivé : aucune page `/server-status`. La construction échoue s'il est encore activé.
* Aucun TLS dans l'image : ni `mod_ssl`, ni _vhost_ 443, ni clé privée. Le TLS se termine devant le conteneur (Caddy
  ou la périphérie de l'hébergeur). La construction échoue si `ssl_module` est chargé ou si `default-ssl.conf` est
  activé.

## Retrait de mod_ssl (novembre 2026)

Jusqu'en novembre 2026, l'image activait `mod_ssl`, copiait `default-ssl.conf` en fichier dans `sites-enabled` (donc
hors de portée de `a2dissite`) et générait une clé auto-signée à la construction. Une image dérivée qui retirait
elle-même ce _vhost_ ou ce module se construit encore si elle tolère leur absence :

* supprimer un fichier avec `rm -f`, jamais `rm` seul, qui échoue quand le fichier n'existe pas;
* `a2dismod ssl`, comme `a2dismod status`, rend 0 sur un module déjà désactivé et 1 seulement quand ses fichiers ont
  disparu de `mods-available`. L'image les garde exprès, et sa construction échoue s'ils disparaissent.

## Directives personnalisées pour PHP.ini

```ini
apc.enable_cli = 1

[xdebug]
xdebug.output_dir='/xdebug.d'
xdebug.mode = profile
xdebug.use_compression = true
```

## Publication

* Un _push_ sur `main` publie `ghcr.io/ophelios-studio/docker-pulsar-php84:latest`.
* Une _pull request_ vers `main` publie `ghcr.io/ophelios-studio/docker-pulsar-php84-test:latest`.
* Chaque lundi à 7 h UTC, `CD - Prod` reconstruit l'image sans cache, depuis l'image officielle tirée à
  nouveau, et republie `latest` : les correctifs de sécurité de Debian et d'Apache y entrent même quand rien n'est
  poussé ici. Un lancement manuel de `CD - Prod` fait la même reconstruction. GitHub suspend une tâche planifiée après
  60 jours sans activité dans un dépôt public : la réactiver dans l'onglet _Actions_ si cela arrive.
* Une application reçoit ces correctifs à sa propre construction, si elle tire l'image à nouveau (`docker build
  --pull`).
* Les paquets Debian sont mis à jour à chaque construction et installés sans leurs recommandations
  (`--no-install-recommends`) : ni `exim4` ni le client `ssh` ne sont dans l'image. Une image dérivée qui en a besoin
  les installe elle-même.
