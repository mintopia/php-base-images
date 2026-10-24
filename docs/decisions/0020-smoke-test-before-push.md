# Decision: Each Lane smoke-tests every target before anything is pushed

Status: accepted
Date: 2026-10-24

## Context
A published digest is permanent (ADR 0026), so a broken image must never reach GHCR. The build has to be checked before the push.

## Decision
- A Lane bakes its targets into the local Docker daemon, without attestations, because the docker exporter cannot load an index.
- `tests/smoke.sh` runs for each target. It checks that every extension listed in `versions.json` loads, that intl has de_DE locale data, that mongodb has TLS, and the forwarded-header values PHP receives with trusted and untrusted proxies (ADR 0008).
- The Lane records the PHP version and the loaded modules for the merge job.
- Only after the smoke test passes does the Lane bake again, with a push-by-digest output. That run is served from the layer cache.
- A failed smoke test stops the Lane before the push.

## Consequences
- Pull requests run the smoke test too, without pushing.
- A Lane bakes twice. The second bake uses cached layers and does not rebuild them.
- A failed push partway through can leave untagged per-arch images in GHCR (ADR 0025).

## Supersedes
None
