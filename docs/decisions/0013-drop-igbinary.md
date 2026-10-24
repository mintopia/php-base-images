# Decision: igbinary is not installed, and redis is built without its serializer

Status: accepted
Date: 2026-10-24

## Context
igbinary is not wanted in the images, and redis is the only extension that would otherwise use it.

## Decision
- igbinary is not installed on any PHP version.
- redis is built without the igbinary serializer, so `--enable-redis-igbinary` is not passed.

## Consequences
- Applications that use `Redis::SERIALIZER_IGBINARY` or `igbinary_*` functions must install igbinary and rebuild redis in a derived image.

## Supersedes
None
