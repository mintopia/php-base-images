# Decision: Delete untagged, unreferenced GHCR images daily

Status: superseded
Date: 2026-10-21

## Context
Every publish re-points tags at a new multi-arch index, and every cache export overwrites its `cache-*` tag. The previous index, its platform images and attestations, and the previous cache manifest remain as untagged package versions with no expiry. On 2026-10-21 `ghcr.io/mintopia/php` held 1132 versions, 776 of them untagged and referenced by nothing; `nginx` held 32 such of 42. ADR 0002's "bounded, overwritten in place" holds for tags, not for storage.

Platform images and attestations pushed by digest are themselves untagged versions, referenced only by a tagged index (184 at the time). A naive "delete untagged versions" would break every published multi-arch tag.

## Decision
`.github/workflows/cleanup.yml` runs `dataaxiom/ghcr-cleanup-action` daily on `php` and `nginx` with `delete-untagged` only. It works on images, not package versions: an untagged top-level image is deleted with its children; children of a tagged image are kept. No retention count or grace window for superseded digests. `older-than: 1 day` only protects platform digests of in-flight builds, which stay untagged until the merge job tags them. Manual runs default to dry-run.

## Consequences
- Superseded digests stop being pullable after a day; consumers must pin tags, or re-pin digests after each release.
- Storage is bounded by the live tag set plus one day of churn, which makes ADR 0002's bound true for storage.
- A build that takes over a day between push-by-digest and merge would lose its platform images; build jobs time out at 90 minutes.
- The workflow's `GITHUB_TOKEN` needs admin access to both packages (granted to the publishing repository by default).

## Supersedes
None (amends the storage consequence of ADR 0002)
