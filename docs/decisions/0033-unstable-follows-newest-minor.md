# Decision: `unstable` follows the newest minor

Status: accepted
Date: 2026-11-19

## Context
ADR 0016 put `unstable` only on an unstable minor. When PHP 8.6 went GA there was no RC line left, so `unstable` would stay on the last 8.6 RC until 8.7 reaches RC. Published images are never deleted (ADR 0026), so that tag would go stale.

## Decision
- `unstable` points at the Alpine cli image of the newest minor in the Matrix file, stable or not.
- `scripts/resolve-matrix.sh` passes the newest minor to `scripts/tags.sh` as its sixth argument.
- With no RC line, `unstable` and `latest` point at the same image.

## Consequences
- `unstable` always means "newest PHP" and never holds an old RC.
- Users of `unstable` move straight to the next RC as soon as it enters the Matrix file.

## Supersedes
ADR 0016, the `unstable` rule only
