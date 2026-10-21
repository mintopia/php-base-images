variable "PHP_VERSION" { default = "8.5" }
variable "OS" { default = "alpine" }
variable "PLATFORMS" { default = "" }
variable "PUSH" { default = "false" }
variable "CACHE_REF" { default = "" }

variable "ALPINE_VERSION" { default = "3" }
variable "FRANKENPHP_VERSION" { default = "1" }
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
  labels     = base_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-zts-${OS}", ZTS_DIGEST)
  cache-from = cache_from("cli")
  cache-to   = cache_to("cli")
}

target "frankenphp" {
  inherits   = ["_common"]
  target     = "frankenphp"
  tags       = [tag("frankenphp")]
  labels     = base_labels("docker.io/dunglas/frankenphp:${FRANKENPHP_VERSION}-php${VERSIONS[PHP_VERSION].tag}-${OS}", FRANKENPHP_DIGEST)
  cache-from = cache_from("frankenphp")
  cache-to   = cache_to("frankenphp")
}

target "php-fpm" {
  inherits   = ["_common"]
  target     = "php-fpm"
  tags       = [tag("php-fpm")]
  labels     = base_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-fpm-${OS}", FPM_DIGEST)
  cache-from = cache_from("php-fpm")
  cache-to   = cache_to("php-fpm")
}

target "php-fpm-nginx" {
  inherits = ["_common"]
  target   = "php-fpm-nginx"
  tags     = [tag("php-fpm-nginx")]
  labels = merge(base_labels("docker.io/library/php:${VERSIONS[PHP_VERSION].tag}-fpm-${OS}", FPM_DIGEST), {
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
  labels = merge(base_labels({ alpine = "docker.io/library/alpine:${ALPINE_VERSION}", trixie = "docker.io/library/debian:trixie-slim" }[OS], NGINX_BASE_DIGEST), {
    "net.mintopia.nginx.version" = NGINX_VERSION
  })
  cache-from = cache_from("nginx")
  cache-to   = cache_to("nginx")
}
