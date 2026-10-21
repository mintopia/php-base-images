# Agent Guidance

## Background and Rules

 - Replacing 2 existing repositories:
   - https://github.com/mintopia/php-docker
   - https://github.com/mintopia/php-frankenphp-base

 - Images being built in GitHub using GitHub actions and published to GHCR
 - PIE is used for installing extensions where-ever possible
 - Hadolint for linting dockerfiles
 - Follow best practices
 - Build from common base images
 - Share stages and build caches
 - Multi-architecture builds should be run in parallel and then have manifests merged

## The project

A series of PHP base images.

### Options

#### Variants

 - CLI
 - nginx + php-fpm (separate images)
 - nginx + php-fpm (combined image)
 - FrankenPHP

#### Supported PHP Versions

 - 8.2
 - 8.3
 - 8.4
 - 8.5
 - 8.6 (if we have an RC available, extensions if they're available)

#### OS Versions

 - debian-slim
 - alpine

#### CPU Architectures

 - amd64
 - arm64

#### PHP Extensions

 - bcmath
 - grpc
 - opentelemetry
 - pcntl
 - pdo
 - pdo_mysql
 - pdo_pgsql
 - pdo_sqlite
 - pdo_odbc
 - protobuf
 - redis
 - gd
 - snmp

#### Security

 - root
 - PUID/PGID support

### Tags

Tags consist of <version>-<os>-<type>. There should also be simple tags:

 - `latest` - Latest stable PHP (8.5) CLI with Alpine Linux
 - `develop` - Latest unstable PHP (8.6) CLI with Alpine Linux

If any of the components in the tag are missing, then they get the default, eg:

 - `8.5` - PHP 8.5, CLI, Alpine Linux
 - `8.5-trixie` - PHP 8.5, CLI, Debian Slim Trixie
 - `8.5-frankenphp` - PHP 8.5, FrankenPHP, Alpine Linux
 - `trixie-frankenphp` - PHP 8.5, Debian Slim Trixie, FrankenPHP

#### Versions

 - `<empty>` - Latest stable PHP 8 (8.5)
 - `8` - Latest stable PHP 8 (8.5)
 - `8.2` - Latest stable PHP 8.2
 - `8.2.x` - Specific version of PHP 8.2
 - `8.3` - Latest stable PHP 8.3
 - `8.3.x` - Specific version of PHP 8.3
 - `8.4` - Latest stable PHP 8.4
 - `8.4.x` - Specific version of PHP 8.4
 - `8.5` - Latest stable PHP 8.5
 - `8.5.x` - Specific version of PHP 8.5
 - `8.6` - Latest PHP 8.6
 - `8.6.x` - Specific version of PHP 8.6
 - `8.6-rcX` - Specific RC of PHP 8.6

#### OS

 - `<empty>` - Alpine Linux (latest stable)
 - `trixie` - Debian Slim Trixie
 - `alpine` - Alpine Linux (latest stable)

#### Type

 - `<empty>` - CLI
 - `cli` - CLI
 - `php-fpm` - PHP-FPM
 - `php-fpm-nginx` - PHP-FPM and Nginx in one container
 - `frankenphp` - FrankenPHP

### Nginx Image

There should also be an nginx image with the same OS options running latest stable nginx. It
should be configured to use PHP-FPM with a configurable hostname and port for the PHP-FPM server

### Configuration

 - The default PHP production configuration should be copied into the config directory
 - PHP-FPM tuning parameters should be available as ENV variables to be either set at runtime or overridden
 - Base directory for serving the application should be configurable as ENV
 - PGID and PUID optional for setting user and group to run the processes as, default will be as root if omitted
 - PHP-FPM Status page should be optionally published with allowlist of IPs and configurable path

### Tools

 - PIE and PHP docker extensions installer should be available
 - Composer should *not* be available
