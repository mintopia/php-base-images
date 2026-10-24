# Decision: Tags are <version>-<os>-<variant>, and defaults are omitted

Status: accepted
Date: 2026-10-24

## Context
Users pick an image by PHP version, OS and Variant. Tags need short forms for the common choice, and a predictable set for each Lane.

## Decision
- A tag is `<version>-<os>-<variant>`. A component that matches its default is left out: `cli` for the variant, `alpine` for the OS, and the latest stable version for the version.
- `scripts/tags.sh` computes each Lane's tags at merge time. For each version form, it emits every OS and Variant combination with defaults omitted:
  - the full version (`8.5.11`) and the minor (`8.5`);
  - for an RC, `8.6-rc1` and `8.6`;
  - for the latest stable minor only, the major (`8`) and the version-less forms (`alpine-cli`, `latest`);
  - `unstable` on the Alpine cli image, only for an unstable minor.
- Nginx tags are `<os>`, and `latest` on Alpine.
- Each tag points at the new multi-arch index on every publish. A digest pins a fixed build (ADR 0026).
- `scripts/tags_test.sh` checks the rules.

## Consequences
- `latest` is the latest stable minor on Alpine cli, and `unstable` is the RC.
- Tags move on each rebuild. Pin a digest or a patch tag to hold a build still.

## Supersedes
None
