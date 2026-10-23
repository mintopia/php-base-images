# Decision: Bundle intl, zip, exif, sockets, gmp, soap, apcu, igbinary and mongodb

Status: accepted
Date: 2026-10-23

## Context
Most PHP applications need some extensions beyond the original set (bcmath, gd, grpc, opentelemetry, pcntl, pdo_*, protobuf, redis, snmp). intl is required by packages such as Filament and used by Laravel and Symfony; zip by Composer archives and spreadsheet libraries; sockets by RoadRunner and AMQP clients; apcu and igbinary are common caching and serialisation choices; mongodb is the driver for MongoDB. Without them, nearly every derived image needs a compiler stage, which the trixie runtime does not carry (ADR 0010).

A spike measured the cost on 8.5 cli (arm64): alpine 65.9 → 79.3 MB compressed (+20%), trixie 106 → 123 MB (+16%). ICU accounts for about 36 MB uncompressed on each OS; the eight extension objects total about 2.3 MB. mongodb, with its bundled libmongoc, adds about 5 MB compressed on each OS.

## Decision
- Bundle intl, zip, exif, sockets, gmp, soap, apcu, igbinary and mongodb on every PHP version that builds them.
- Alpine installs `icu-data-full`, since `icu-libs` only carries English locale data and intl would silently fall back to it.
- apcu, igbinary and mongodb install through PIE and are tracked as labelled upstream versions (ADR 0003), like redis. igbinary uses the PECL stable release, currently 3.2.17RC1, which is also the only version on Packagist.
- redis is built after igbinary with `--enable-redis-igbinary`.
- mongodb is built against OpenSSL so TLS connections, required by MongoDB Atlas, work.
- On 8.6, apcu and igbinary fail to compile and are listed under `dropped` in `versions.json` rather than patched.

## Consequences
- Images are 16-20% larger compressed, almost all of it ICU.
- Common frameworks run without a derived image; `install-php-extensions` and PIE remain for anything else.
- Three more upstream versions drive daily rebuild checks.
- Removing an extension later is a breaking change for users who rely on it.

## Supersedes
None
