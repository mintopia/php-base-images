# Decision: versions.json is the Matrix file and the only list of supported versions

Status: accepted
Date: 2026-10-24

## Context
The build needs one place that says which PHP versions, OSes and extensions get built, so that the workflows, the bake file and the site cannot disagree.

## Decision
- `versions.json` (the Matrix file) lists each supported PHP minor under `VERSIONS.default`, with its `tag`, `stable` flag, `os` list, `frankenphp` flag, `extensions` list and, for 8.6, `dropped` entries with reasons.
- `scripts/resolve-matrix.sh` derives every Lane, plan and bake variable from it. The bake file, the workflows and the site read it too, and nothing repeats its contents.

## Consequences
- Adding a PHP minor is one `versions.json` entry.
- Removing a minor stops every patch lane under it (ADR 0017).
- The `dropped` list is the only record of extensions removed from a version.

## Supersedes
None
