# Decision: Published images are never deleted

Status: accepted
Date: 2026-10-24

## Context
A tag moves on every rebuild, and the old digest is the only way to pin a build. Users pin digests, and the site lists every build (ADR 0027), so a build that stops resolving breaks a pinned user and a listed page.

## Decision
- Nothing under `ghcr.io/mintopia/php` or `ghcr.io/mintopia/nginx` is deleted, except the per-arch index that a merge job consumes (ADR 0025).
- No cleanup workflow runs against these packages.
- A superseded digest keeps resolving, so `@sha256:` pins stay valid.

## Consequences
- Storage grows with every publish.
- Orphaned untagged indexes from failed runs stay in place. Any future cleanup must keep every digest that a tag or the site record refers to.

## Supersedes
None
