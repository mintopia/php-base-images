variable "PHP_VERSION" { default = "8.5" }
variable "OS" { default = "alpine" }
variable "PLATFORMS" { default = "" }
variable "PUSH" { default = "false" }
variable "CACHE_REF" { default = "" }
variable "PHP_SOURCE" {
  default = "upstream"
  validation {
    condition     = contains(["upstream", "src"], PHP_SOURCE)
    error_message = "PHP_SOURCE must be upstream or src."
  }
}
variable "PHP_TAG" {
  default = ""
  validation {
    condition     = PHP_SOURCE != "src" || PHP_TAG != ""
    error_message = "PHP_TAG (php-src tag, e.g. php-8.5.11) is required when PHP_SOURCE=src."
  }
}

variable "ALPINE_VERSION" { default = "3" }
variable "FRANKENPHP_VERSION" { default = "1" }
variable "FRANKENPHP_SRC_VERSION" { default = "1.13.1" }
variable "GO_VERSION" { default = "1.27" }
variable "WATCHER_VERSION" { default = "0.14.5" }
variable "NGINX_VERSION" { default = "1.30.6" }
variable "S6_OVERLAY_VERSION" { default = "3.2.3.2" }
variable "GRPC_VERSION" { default = "" }
variable "REDIS_VERSION" { default = "6.3.0" }
variable "OPENTELEMETRY_VERSION" { default = "1.4.2" }
variable "PROTOBUF_VERSION" { default = "35.1" }

variable "ZTS_DIGEST" { default = "" }
variable "FPM_DIGEST" { default = "" }
variable "FRANKENPHP_DIGEST" { default = "" }
variable "NGINX_BASE_DIGEST" { default = "" }

function "grpc_version" {
  params = []
  result = GRPC_VERSION != "" ? GRPC_VERSION : { alpine = "1.78.1", trixie = "1.51.1" }[OS]
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

function "php_contexts" {
  params = [variant]
  result = PHP_SOURCE == "src" ? { "php:${VERSIONS[PHP_VERSION].tag}-${variant}-${OS}" = "target:src-${variant}" } : {}
}

function "cache_from" {
  params = [variant]
  result = CACHE_REF == "" ? [] : ["type=registry,ref=${CACHE_REF}-${variant}"]
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
  output     = ["type=image,push=${PUSH}"]
  args = {
    PHP_VERSION           = VERSIONS[PHP_VERSION].tag
    FRANKENPHP_VERSION    = FRANKENPHP_VERSION
    NGINX_VERSION         = NGINX_VERSION
    S6_OVERLAY_VERSION    = S6_OVERLAY_VERSION
    GRPC_VERSION          = grpc_version()
    REDIS_VERSION         = REDIS_VERSION
    OPENTELEMETRY_VERSION = OPENTELEMETRY_VERSION
    PROTOBUF_VERSION      = PROTOBUF_VERSION
    EXTENSIONS            = join(" ", VERSIONS[PHP_VERSION].extensions)
  }
  labels = {
    for ext, version in {
      grpc          = grpc_version()
      redis         = REDIS_VERSION
      opentelemetry = OPENTELEMETRY_VERSION
      protobuf      = PROTOBUF_VERSION
    } : "net.mintopia.ext.${ext}.version" => version if contains(VERSIONS[PHP_VERSION].extensions, ext)
  }
}

target "cli" {
  inherits   = ["_common"]
  target     = "cli"
  tags       = [tag("cli")]
  labels     = php_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-zts-${OS}", ZTS_DIGEST)
  contexts   = php_contexts("zts")
  cache-from = cache_from("cli")
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
  contexts = merge(php_contexts("zts"), PHP_SOURCE == "src" ? {
    "dunglas/frankenphp:${FRANKENPHP_VERSION}-php${VERSIONS[PHP_VERSION].tag}-${OS}" = "target:src-frankenphp"
  } : {})
  cache-from = cache_from("frankenphp")
  cache-to   = cache_to("frankenphp")
}

target "php-fpm" {
  inherits   = ["_common"]
  target     = "php-fpm"
  tags       = [tag("php-fpm")]
  labels     = php_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-fpm-${OS}", FPM_DIGEST)
  contexts   = php_contexts("fpm")
  cache-from = cache_from("php-fpm")
  cache-to   = cache_to("php-fpm")
}

target "php-fpm-nginx" {
  inherits = ["_common"]
  target   = "php-fpm-nginx"
  tags     = [tag("php-fpm-nginx")]
  contexts = php_contexts("fpm")
  labels = merge(php_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-fpm-${OS}", FPM_DIGEST), {
    "net.mintopia.nginx.version" = NGINX_VERSION
    "net.mintopia.s6.version"    = S6_OVERLAY_VERSION
  })
  cache-from = cache_from("php-fpm-nginx")
  cache-to   = cache_to("php-fpm-nginx")
}

target "nginx" {
  dockerfile = "${OS}.Dockerfile"
  platforms  = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  output     = ["type=image,push=${PUSH}"]
  target     = "nginx"
  tags       = [tag("nginx")]
  args       = { NGINX_VERSION = NGINX_VERSION, ALPINE_VERSION = ALPINE_VERSION }
  labels = merge(base_labels(os_base(), NGINX_BASE_DIGEST), {
    "net.mintopia.nginx.version" = NGINX_VERSION
  })
  cache-from = cache_from("nginx")
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
  cache-from = cache_from("src-zts")
  cache-to   = cache_to("src-zts")
}

target "src-frankenphp" {
  inherits   = ["_src"]
  target     = "frankenphp"
  args       = { FRANKENPHP_SRC_VERSION = FRANKENPHP_SRC_VERSION, GO_VERSION = GO_VERSION, WATCHER_VERSION = WATCHER_VERSION }
  cache-from = cache_from("src-frankenphp")
  cache-to   = cache_to("src-frankenphp")
}

target "src-fpm" {
  inherits   = ["_src"]
  target     = "fpm"
  cache-from = cache_from("src-fpm")
  cache-to   = cache_to("src-fpm")
}
