variable "PHP_VERSION" { default = "8.5" }
variable "OS" { default = "alpine" }
variable "PLATFORMS" { default = "" }
variable "CACHE_REF" { default = "" }
variable "PHP_SOURCE" {
  default = "src"
  validation {
    condition     = contains(["upstream", "src"], PHP_SOURCE)
    error_message = "PHP_SOURCE must be upstream or src."
  }
}
variable "PHP_TAG" {
  default = ""
  validation {
    condition     = PHP_SOURCE != "src" || PHP_TAG != ""
    error_message = "PHP_TAG (php-src tag, e.g. php-8.5.11) is required when PHP_SOURCE=src (the default); use scripts/resolve-php-tag.sh."
  }
}

variable "ALPINE_VERSION" { default = "3" }
# changes per CI day so final stages re-run apk/apt upgrade instead of reusing cached package layers
variable "PKG_STAMP" { default = "" }
variable "FRANKENPHP_VERSION" { default = "1" }
variable "FRANKENPHP_SRC_VERSION" { default = "1.13.1" }
variable "FRANKENPHP_SRC_SHA256" { default = "0c9776464a805966d1fc74c119eb3fbe72145d0a6323b1b8512e9eab6a853a8d" }
variable "GO_VERSION" { default = "1.27" }
variable "WATCHER_VERSION" { default = "0.14.5" }
variable "WATCHER_SHA256" { default = "190bbe5e19923083db2beb3aa68f4e99a563c8f685d8037b0536780b0116c4d3" }
variable "NGINX_VERSION" { default = "1.30.6" }
variable "S6_OVERLAY_VERSION" { default = "3.2.3.2" }
variable "GRPC_VERSION" { default = "" }
variable "REDIS_VERSION" { default = "6.3.0" }
variable "APCU_VERSION" { default = "5.1.28" }
variable "MONGODB_VERSION" { default = "2.5.5" }
variable "OPENTELEMETRY_VERSION" { default = "1.4.2" }
variable "PROTOBUF_VERSION" { default = "35.1" }

# git commit, set by CI
variable "REVISION" { default = "" }

variable "ZTS_DIGEST" { default = "" }
variable "FPM_DIGEST" { default = "" }
variable "FRANKENPHP_DIGEST" { default = "" }
variable "NGINX_BASE_DIGEST" { default = "" }

function "grpc_version" {
  params = []
  result = GRPC_VERSION != "" ? GRPC_VERSION : { alpine = "1.78.1", trixie = "1.51.1" }[OS]
}

function "oci_labels" {
  params = [version]
  result = merge({
    "org.opencontainers.image.source"   = "https://github.com/mintopia/php-base-images"
    "org.opencontainers.image.licenses" = "MIT"
    "org.opencontainers.image.version"  = version
  }, REVISION == "" ? {} : { "org.opencontainers.image.revision" = REVISION })
}

function "tag" {
  params = [variant]
  result = "php:${PHP_VERSION}-${OS}-${variant}"
}

function "base_labels" {
  params = [name, digest]
  result = {
    "org.opencontainers.image.base.name"   = name
    "org.opencontainers.image.base.digest" = digest
  }
}

function "os_base" {
  params = []
  result = { alpine = "docker.io/library/alpine:${ALPINE_VERSION}", trixie = "docker.io/library/debian:trixie-slim" }[OS]
}

# PHP_SOURCE=src swaps the php:* bases for php-src.Dockerfile builds on the OS base; tags are unchanged
function "php_labels" {
  params = [upstream, digest]
  result = PHP_SOURCE == "src" ? merge(base_labels(os_base(), NGINX_BASE_DIGEST), {
    "net.mintopia.php.source" = "php-src"
    "net.mintopia.php.tag"    = PHP_TAG
  }) : base_labels(upstream, digest)
}

# src fpm is the same ZTS build as zts, so it shares that extension build
function "fpm_args" {
  params = []
  result = { EXT_BUILDER = PHP_SOURCE == "src" ? "zts" : "nts" }
}

function "php_contexts" {
  params = []
  result = PHP_SOURCE == "src" ? {
    for v in ["zts", "fpm"] : "php:${VERSIONS[PHP_VERSION].tag}-${v}-${OS}" => "target:src-${v}"
  } : {}
}

# every ref of the Lane: a sub-build that only imports its own ref misses layers another target exported
function "cache_from" {
  params = []
  result = CACHE_REF == "" ? [] : [
    for v in ["cli", "frankenphp", "php-fpm", "php-fpm-nginx", "nginx", "src-zts", "src-fpm", "src-frankenphp"] :
    "type=registry,ref=${CACHE_REF}-${v}"
  ]
}

function "cache_to" {
  params = [variant]
  result = CACHE_REF == "" ? [] : ["type=registry,ref=${CACHE_REF}-${variant},mode=max"]
}

group "default" {
  targets = concat(
    ["cli", "php-fpm", "php-fpm-nginx", "nginx"],
    VERSIONS[PHP_VERSION].frankenphp ? ["frankenphp"] : [],
  )
}

target "_common" {
  dockerfile = "${OS}.Dockerfile"
  platforms  = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  args = {
    PHP_VERSION           = VERSIONS[PHP_VERSION].tag
    FRANKENPHP_VERSION    = FRANKENPHP_VERSION
    NGINX_VERSION         = NGINX_VERSION
    S6_OVERLAY_VERSION    = S6_OVERLAY_VERSION
    GRPC_VERSION          = grpc_version()
    REDIS_VERSION         = REDIS_VERSION
    APCU_VERSION          = APCU_VERSION
    MONGODB_VERSION       = MONGODB_VERSION
    OPENTELEMETRY_VERSION = OPENTELEMETRY_VERSION
    PROTOBUF_VERSION      = PROTOBUF_VERSION
    EXTENSIONS            = join(" ", VERSIONS[PHP_VERSION].extensions)
    PKG_STAMP             = PKG_STAMP
  }
  labels = merge(oci_labels(PHP_SOURCE == "src" ? trimprefix(PHP_TAG, "php-") : VERSIONS[PHP_VERSION].tag), {
    for ext, version in {
      grpc          = grpc_version()
      redis         = REDIS_VERSION
      apcu          = APCU_VERSION
      mongodb       = MONGODB_VERSION
      opentelemetry = OPENTELEMETRY_VERSION
      protobuf      = PROTOBUF_VERSION
    } : "net.mintopia.ext.${ext}.version" => version if contains(VERSIONS[PHP_VERSION].extensions, ext)
  })
}

target "cli" {
  inherits   = ["_common"]
  target     = "cli"
  tags       = [tag("cli")]
  labels     = php_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-zts-${OS}", ZTS_DIGEST)
  contexts   = php_contexts()
  cache-from = cache_from()
  cache-to   = cache_to("cli")
}

target "frankenphp" {
  inherits   = ["_common"]
  target     = "frankenphp"
  tags       = [tag("frankenphp")]
  labels = merge(
    php_labels("docker.io/dunglas/frankenphp:${FRANKENPHP_VERSION}-php${VERSIONS[PHP_VERSION].tag}-${OS}", FRANKENPHP_DIGEST),
    PHP_SOURCE == "src" ? { "net.mintopia.frankenphp.version" = FRANKENPHP_SRC_VERSION } : {},
  )
  contexts = merge(php_contexts(), PHP_SOURCE == "src" ? {
    "dunglas/frankenphp:${FRANKENPHP_VERSION}-php${VERSIONS[PHP_VERSION].tag}-${OS}" = "target:src-frankenphp"
  } : {})
  cache-from = cache_from()
  cache-to   = cache_to("frankenphp")
}

target "php-fpm" {
  inherits   = ["_common"]
  target     = "php-fpm"
  args       = fpm_args()
  tags       = [tag("php-fpm")]
  labels     = php_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-fpm-${OS}", FPM_DIGEST)
  contexts   = php_contexts()
  cache-from = cache_from()
  cache-to   = cache_to("php-fpm")
}

target "php-fpm-nginx" {
  inherits = ["_common"]
  target   = "php-fpm-nginx"
  args     = fpm_args()
  tags     = [tag("php-fpm-nginx")]
  contexts = php_contexts()
  labels = merge(php_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-fpm-${OS}", FPM_DIGEST), {
    "net.mintopia.nginx.version" = NGINX_VERSION
    "net.mintopia.s6.version"    = S6_OVERLAY_VERSION
  })
  cache-from = cache_from()
  cache-to   = cache_to("php-fpm-nginx")
}

target "nginx" {
  dockerfile = "${OS}.Dockerfile"
  platforms  = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  target     = "nginx"
  tags       = [tag("nginx")]
  args       = { NGINX_VERSION = NGINX_VERSION, ALPINE_VERSION = ALPINE_VERSION }
  labels = merge(oci_labels(NGINX_VERSION), base_labels(os_base(), NGINX_BASE_DIGEST), {
    "net.mintopia.nginx.version" = NGINX_VERSION
  })
  cache-from = cache_from()
  cache-to   = cache_to("nginx")
}

target "_src" {
  dockerfile = "php-src.Dockerfile"
  platforms  = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  args       = { PHP_TAG = PHP_TAG, OS = OS, ALPINE_VERSION = ALPINE_VERSION }
}

target "src-zts" {
  inherits   = ["_src"]
  target     = "zts"
  cache-from = cache_from()
  cache-to   = cache_to("src-zts")
}

target "src-frankenphp" {
  inherits   = ["_src"]
  target     = "frankenphp"
  args = {
    FRANKENPHP_SRC_VERSION = FRANKENPHP_SRC_VERSION
    FRANKENPHP_SRC_SHA256  = FRANKENPHP_SRC_SHA256
    GO_VERSION             = GO_VERSION
    WATCHER_VERSION        = WATCHER_VERSION
    WATCHER_SHA256         = WATCHER_SHA256
  }
  cache-from = cache_from()
  cache-to   = cache_to("src-frankenphp")
}

target "src-fpm" {
  inherits   = ["_src"]
  target     = "fpm"
  cache-from = cache_from()
  cache-to   = cache_to("src-fpm")
}
