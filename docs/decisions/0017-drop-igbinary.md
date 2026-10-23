# Decision: Drop igbinary and delete the builds that carried it

Status: accepted
Date: 2026-10-23

## Context
ADR 0014 bundled igbinary and built redis with `--enable-redis-igbinary`. igbinary is not wanted in the images. The builds that carried it were published only in the days before this decision, and nobody outside the project has pulled them.

## Decision
- igbinary is no longer installed, and redis is built without its igbinary serializer.
- As a one-off exception to ADR 0015, every published build with an `net.mintopia.ext.igbinary.version` label is deleted from `php`, along with its platform images, attestations and signature, and removed from the site, once rebuilt images hold its tags.

## Consequences
- Applications using `Redis::SERIALIZER_IGBINARY` or `igbinary_*` functions must install igbinary and rebuild redis themselves.
- The removal is an image input change, so merging it rebuilds every lane.
- Digests of the deleted builds stop resolving. ADR 0015 stands for every other build.

## Supersedes
The igbinary parts of ADR 0014; ADR 0015 is not superseded, this is a recorded exception.
