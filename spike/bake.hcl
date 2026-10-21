# Overlay: swaps upstream php:* bases for from-source builds.
# docker buildx bake -f docker-bake.hcl -f versions.json -f spike/bake.hcl --set '*.output=type=docker' cli php-fpm php-fpm-nginx
variable "PHP_TAG" { default = "php-8.5.11" }

function "spike_tag" {
  params = [variant]
  result = "spike:${PHP_VERSION}-${OS}-${variant}"
}

target "_src" {
  dockerfile = "spike/src.Dockerfile"
  platforms  = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  args       = { PHP_TAG = PHP_TAG, OS = OS }
}

target "src-zts" {
  inherits = ["_src"]
  target   = "zts"
}

target "src-nts" {
  inherits = ["_src"]
  target   = "nts"
}

# ponytail: frankenphp omitted; needs FrankenPHP built against our libphp (xcaddy), not dunglas/frankenphp
target "_contexts" {
  contexts = {
    "php:${VERSIONS[PHP_VERSION].tag}-zts-${OS}" = "target:src-zts"
    "php:${VERSIONS[PHP_VERSION].tag}-fpm-${OS}" = "target:src-nts"
  }
}

target "cli" {
  inherits = ["_contexts"]
  tags     = [spike_tag("cli")]
}

target "php-fpm" {
  inherits = ["_contexts"]
  tags     = [spike_tag("php-fpm")]
}

target "php-fpm-nginx" {
  inherits = ["_contexts"]
  tags     = [spike_tag("php-fpm-nginx")]
}
