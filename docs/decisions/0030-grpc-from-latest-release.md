# Decision: grpc builds from the latest grpc release, not the distro's libgrpc

Status: accepted
Date: 2026-10-26

## Context
ADR 0011 linked grpc against each distro's libgrpc. On 2026-10-26 Alpine 3.24 shipped grpc 1.78.1 and trixie shipped 1.51.1. Both are affected by GHSA-hf3w-6hpw-qp67 (high, fixed in 1.82.2 and 1.83.1). Trixie also had five open CVEs that Debian had not fixed: CVE-2023-32732, CVE-2023-33953, CVE-2023-44487, CVE-2023-4785 and CVE-2024-7246. No Alpine or Debian release, edge, backports or sid included, shipped a fixed version. Every other component follows its latest upstream release, so that fixes arrive with the version.

## Decision
- `GRPC_VERSION` is the latest stable release of grpc/grpc on GitHub, resolved by `scripts/resolve-matrix.sh` like PIE and s6-overlay. Both OSes build the same version. A new release changes the `net.mintopia.ext.grpc.version` label, so the daily check (ADR 0022) rebuilds every target that has grpc.
- A `libgrpc` build product holds gRPC core and its bundled abseil, c-ares, re2 and upb as static PIC archives, plus the matching `src/php/ext/grpc` source. `build/libgrpc.sh` builds it with CMake. OpenSSL and zlib come from the OS, so OS updates and the OS CVE scan cover them.
- `libgrpc` does not depend on PHP. There is one per OS and architecture, keyed on the grpc version, the OS, the Alpine minor, the architecture and `build/libgrpc.sh` (`scripts/product-keys.sh --libgrpc`). It has its own key prefix, so `scripts/product-plan.sh` leaves it out of each leg's plan.
- A `libgrpc` job in `build.yml` runs before the PHP versions' lanes, on `main` only. It applies the ADR 0024 lifecycle: build if missing or over 30 days old, and restore if idle for 5 days. Products jobs and lanes restore `libgrpc` only when they have to build `ext-grpc`. If it is not in the cache, it is built inline.
- `build/grpc.sh` builds the extension with phpize and links `grpc.so` statically against the archives. `--exclude-libs,ALL` hides their symbols, so grpc's upb and abseil cannot clash with the protobuf extension's. The ext-grpc product key includes the libgrpc key.
- The images no longer install `libgrpc` or `libgrpc29t64`. `grpc.so` needs only libssl, libcrypto, zlib and libstdc++ from the OS.
- grpc stays dropped on PHP 8.6 (ADR 0015). The extension source still uses `XtOffsetOf`.

## Consequences
- grpc security fixes ship on the first daily run after a grpc release.
- A grpc release costs one cold `libgrpc` build per OS and architecture, about 20 to 30 minutes each. After that, every PHP version and patch reuses it. Each `ext-grpc` build takes seconds.
- Trivy no longer sees libgrpc, because it isn't an OS package. The grpc/grpc advisories, matched against the grpc label, cover it (ADR 0029), together with the libraries it bundles.
- The trixie zend_exception sed is gone, because it only worked around libgrpc 1.51's headers.
- The compile uses about 1.5 GB of memory per job, so `build/libgrpc.sh` caps parallel jobs by available memory to keep local builds from running out.

## Supersedes
0011-grpc-system-libgrpc.md
