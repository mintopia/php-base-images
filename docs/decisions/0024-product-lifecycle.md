# Decision: A products job on main keeps build products fresh

Status: accepted
Date: 2026-10-24

## Context
Cache entries are evicted after 7 days without use, and a product is only useful while it matches the current PHP tag and inputs (ADR 0023). Without a scheduled job, a Lane would go cold after a quiet week, and a stale product would stay in use.

## Decision
- A `products` job in `lanes.yml` runs before each PHP version's lanes, on every non-PR run on `main`. It runs on native runners.
- It plans the current patch of each `versions.json` minor on both OSes and both architectures, whether stale or not. Older patch lanes are planned only when they build in that run.
- `scripts/product-plan.sh` makes one cache API call per leg (`actions/caches?key=<leg prefix>&ref=main`). For each product:
  - missing, or created more than 30 days ago: delete the old entry, then build and save it;
  - last used 5 or more days ago: restore it, so it is never evicted;
  - otherwise: do nothing.
- A rebuilt `php` rebuilds every other product of its leg, so no product is built against an older `php`. Building any other product restores `php` first.
- Lanes restore their products. A missing product is built inline. Pull request lanes restore only and never save, because the products job runs only on `main`.
- Filtered dispatches (`php_version`, `os`) cover only what they select.

## Consequences
- Each product is rebuilt at most 30 days after it was built.
- Older patch products that stay idle can be evicted. Their next build rebuilds them.
- The products job needs `actions: write`, to delete and save cache entries.
- Each replaced entry costs one delete. A failed lookup or delete warns and does not fail the run.

## Supersedes
None
