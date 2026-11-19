# Agent Guidance

<!-- shared-rules:start (source: mintopia/home AGENTS.md; edit there, then copy) -->
## Shared rules

### Talking to me
- Be extremely concise; sacrifice grammar for concision.
- British English in prose, docs, UI copy and commits; identifiers follow the language's convention. No em dashes.
- Plain industry-standard terms.

### Working
- Finish the task. Own problems found on the way, including pre-existing failures.
- Fix root causes.
- Prove it works against the real artifact (run it, read the value, inspect the diff) before saying done.
- Match UI to its mockup exactly; raise a wrong or missing mockup on the ticket.
- Type-system discipline: illegal states unrepresentable, parse at boundaries, exhaust variants, derive types from the authoritative schema.
- Model the domain in data structures, not scattered conditionals.
- Make operations idempotent across partial runs, crashes and retries.

### Quality gate
- Red/green TDD for new behaviour and bug fixes.
- Before commit: formatter, linter, static analysis and tests pass at the repo's level. The repo's AGENTS.md names commands and any coverage bar.
- Comments: non-obvious why only, one or two lines. Run /comment-check before finishing.

### Subagents
- Delegate to subagents; run parallel teams that coordinate by messaging.
- Set model and subagent type explicitly:
  - Planning, reasoning, deep debugging: Opus / Sol
  - Explore, coding, review: Sonnet / Terra
  - Trivial edits, docs: Haiku / Luna
- Long results go to a scratchpad file; return one line plus the path.

### Git
- Work on the branch you started on; parallel work goes in a worktree off it.
- Rebase only onto your own base branch.
- Delete merged or abandoned branches and worktrees, locally and on the remote.

### Decisions


Before proposing architecture, tooling, style, testing, repo structure, or workflow changes in any project:

1. Check for a `docs/decisions/` directory in the project root.
2. If it exists, search it for relevant ADRs (Architecture Decision Records).
3. Treat accepted ADRs as binding unless explicitly overridden by the user.
4. If a decision is outdated, propose a new ADR that supersedes it rather than silently ignoring.
5. Do not re-litigate accepted decisions unless new constraints are introduced.

When creating new ADRs, use this format:

```markdown
# Decision: [Title]

Status: [proposed|accepted|deprecated|superseded]
Date: [YYYY-MM-DD]

## Context
[Why this decision is needed]

## Decision
[What was decided]

## Consequences
[Trade-offs and implications]

## Supersedes
[Reference to previous ADR, or "None"]
```

### Code exploration

Always use jCodeMunch-MCP for code navigation. Never fall back to Read, Grep, Glob, or Bash for code exploration.
**Exception:** use `Read` when you are about to edit a file — the harness requires a `Read` before `Edit`/`Write`. Use jCodeMunch to *find and understand* code, then `Read` only the file you are changing.

This server runs the **front door** surface: three tools reach every jCodeMunch capability, so the tool list stays small and the catalogue is fetched only when you need it.

**Start any session:**
1. `order { "action": "resolve_repo", "args": { "path": "." } }` — confirm the project is indexed. If it is not: `order { "action": "index_folder", "args": { "path": "." } }`

**Then, for any task:**
- Know what you want → `order { "action": "<name>", "args": { ... } }`
- Know the goal, not the tool → `route { "query": "your task in a sentence" }` picks the action and shapes the arguments
- Want to see what exists → `menu { "query": "what you are trying to do" }` returns matching actions with example arguments
- Want the whole catalogue and the usage rules → `jcodemunch_guide`

`menu` and `jcodemunch_guide` list every action this server can run, including ones absent from your tool list. That is expected: the front door is the way to call them.

**Interpreting results:**
- A `verdict` of `no_implementation_found` is evidence of absence. Report the gap; do not re-search with different wording.
- A `verdict` of `degraded` means a channel was unavailable, so absence is NOT proven. Read the note before relying on the result.
- `source: ""` alongside `source_status` means the body could not be read, not that the symbol is empty.

**After editing files:**
- With PostToolUse hooks installed (Claude Code), edited files are reindexed automatically.
- Otherwise `order { "action": "register_edit", "args": { "paths": [...] } }` after an edit, batched for bulk changes.

**Announce your model once per session** so the server can size its answers: `announce_model { "model": "<your-model-id>" }`.

<!-- shared-rules:end -->

## Background and Rules

 - Replacing 2 existing repositories:
   - https://github.com/mintopia/php-docker
   - https://github.com/mintopia/php-frankenphp-base

 - Images being built in GitHub using GitHub actions and published to GHCR
 - PIE is used for installing extensions where-ever possible
 - Hadolint for linting dockerfiles
 - Build from common base images
 - Share stages and build caches
 - Multi-architecture builds should be run in parallel and then have manifests merged

## The project

A series of PHP base images.

### Options

#### Variants

 - CLI
 - nginx + php-fpm (separate images)
 - nginx + php-fpm (combined image)
 - FrankenPHP

#### Supported PHP Versions

 - 8.2
 - 8.3
 - 8.4
 - 8.5
 - 8.6
 - The next minor (8.7) once it has an RC, extensions if they're available

#### OS Versions

 - debian-slim
 - alpine

#### CPU Architectures

 - amd64
 - arm64

#### PHP Extensions

 - bcmath
 - grpc
 - opentelemetry
 - pcntl
 - pdo
 - pdo_mysql
 - pdo_pgsql
 - pdo_sqlite
 - pdo_odbc
 - protobuf
 - redis
 - gd
 - snmp
 - intl
 - zip
 - exif
 - sockets
 - gmp
 - soap
 - apcu
 - mongodb

#### Security

 - root
 - PUID/PGID support

### Tags

Tags consist of <version>-<os>-<type>. There should also be simple tags:

 - `latest` - Latest stable PHP (8.6) CLI with Alpine Linux
 - `unstable` - Newest PHP minor CLI with Alpine Linux: the RC when one exists, else the same as `latest` (8.6)

If any of the components in the tag are missing, then they get the default, eg:

 - `8.5` - PHP 8.5, CLI, Alpine Linux
 - `8.5-trixie` - PHP 8.5, CLI, Debian Slim Trixie
 - `8.5-frankenphp` - PHP 8.5, FrankenPHP, Alpine Linux
 - `trixie-frankenphp` - PHP 8.5, Debian Slim Trixie, FrankenPHP

#### Versions

 - `<empty>` - Latest stable PHP 8 (8.6)
 - `8` - Latest stable PHP 8 (8.6)
 - `8.2` - Latest stable PHP 8.2
 - `8.2.x` - Specific version of PHP 8.2
 - `8.3` - Latest stable PHP 8.3
 - `8.3.x` - Specific version of PHP 8.3
 - `8.4` - Latest stable PHP 8.4
 - `8.4.x` - Specific version of PHP 8.4
 - `8.5` - Latest stable PHP 8.5
 - `8.5.x` - Specific version of PHP 8.5
 - `8.6` - Latest stable PHP 8.6
 - `8.6.x` - Specific version of PHP 8.6
 - `8.6-rcX` - Specific RC of PHP 8.6 (published during the RC phase)

#### OS

 - `<empty>` - Alpine Linux (latest stable)
 - `trixie` - Debian Slim Trixie
 - `alpine` - Alpine Linux (latest stable)

#### Type

 - `<empty>` - CLI
 - `cli` - CLI
 - `php-fpm` - PHP-FPM
 - `php-fpm-nginx` - PHP-FPM and Nginx in one container
 - `frankenphp` - FrankenPHP

### Nginx Image

There should also be an nginx image with the same OS options running latest stable nginx. It
should be configured to use PHP-FPM with a configurable hostname and port for the PHP-FPM server

### Configuration

 - The default PHP production configuration should be copied into the config directory
 - PHP-FPM tuning parameters should be available as ENV variables to be either set at runtime or overridden
 - Base directory for serving the application should be configurable as ENV
 - PGID and PUID optional for setting user and group to run the processes as, default will be as root if omitted
 - PHP-FPM Status page should be optionally published with allowlist of IPs and configurable path

### Tools

 - PIE and PHP docker extensions installer should be available
 - Composer should *not* be available
