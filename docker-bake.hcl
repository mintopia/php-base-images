variable "PHP_VERSION" { default = "8.5" }
variable "OS" { default = "alpine" }
variable "PLATFORMS" { default = "" }
variable "PHP_TAG" {
  default = ""
  validation {
    condition     = PHP_TAG != ""
    error_message = "PHP_TAG (php-src tag, e.g. php-8.5.11) is required; use scripts/resolve-php-tag.sh."
  }
}
# space-separated build products restored under PRODUCTS_DIR, used instead of building them (ADR 0023)
variable "PRODUCTS" { default = "" }
variable "PRODUCTS_DIR" { default = "products" }

variable "ALPINE_VERSION" { default = "3" }
# changes per CI day so final stages re-run apk/apt upgrade instead of reusing cached package layers
variable "PKG_STAMP" { default = "" }
variable "FRANKENPHP_SRC_VERSION" { default = "1.13.1" }
variable "FRANKENPHP_SRC_SHA256" { default = "0c9776464a805966d1fc74c119eb3fbe72145d0a6323b1b8512e9eab6a853a8d" }
variable "GO_VERSION" { default = "1.27" }
variable "WATCHER_VERSION" { default = "0.14.5" }
variable "WATCHER_SHA256" { default = "190bbe5e19923083db2beb3aa68f4e99a563c8f685d8037b0536780b0116c4d3" }
variable "NGINX_VERSION" { default = "1.30.6" }
variable "S6_OVERLAY_VERSION" { default = "3.2.3.2" }
variable "PIE_VERSION" { default = "1.5.3" }
variable "GRPC_VERSION" { default = "" }
variable "REDIS_VERSION" { default = "6.3.0" }
variable "APCU_VERSION" { default = "5.1.28" }
variable "MONGODB_VERSION" { default = "2.5.5" }
variable "OPENTELEMETRY_VERSION" { default = "1.4.2" }
variable "PROTOBUF_VERSION" { default = "35.1" }

# git commit, set by CI
variable "REVISION" { default = "" }

variable "NGINX_BASE_DIGEST" { default = "" }

function "grpc_version" {
  params = []
  result = GRPC_VERSION != "" ? GRPC_VERSION : { alpine = "1.78.1", trixie = "1.51.1" }[OS]
}

function "ext_versions" {
  params = []
  result = {
    grpc          = grpc_version()
    redis         = REDIS_VERSION
    apcu          = APCU_VERSION
    mongodb       = MONGODB_VERSION
    opentelemetry = OPENTELEMETRY_VERSION
    protobuf      = PROTOBUF_VERSION
  }
}

# extensions built as their own product, if this PHP version has them
function "ext_products" {
  params = []
  result = [for ext, v in ext_versions() : ext if contains(VERSIONS[PHP_VERSION].extensions, ext)]
}

function "product_names" {
  params = []
  result = concat(["php"], VERSIONS[PHP_VERSION].frankenphp ? ["frankenphp"] : [], [for ext in ext_products() : "ext-${ext}"])
}

# named contexts for the restored products among names
function "products" {
  params = [names]
  result = { for n in names : n => "${PRODUCTS_DIR}/${n}" if contains(split(" ", PRODUCTS), n) }
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

function "php_labels" {
  params = []
  result = merge(base_labels(os_base(), NGINX_BASE_DIGEST), {
    "net.mintopia.php.source" = "php-src"
    "net.mintopia.php.tag"    = PHP_TAG
  })
}

group "default" {
  targets = concat(
    ["cli", "php-fpm", "php-fpm-nginx", "nginx"],
    VERSIONS[PHP_VERSION].frankenphp ? ["frankenphp"] : [],
  )
}

# every build product of the Lane, each exported on its own by the products job
group "products" {
  targets = [for n in product_names() : "product-${n}"]
}

target "_common" {
  dockerfile = "${OS}.Dockerfile"
  platforms  = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  args = {
    NGINX_VERSION      = NGINX_VERSION
    S6_OVERLAY_VERSION = S6_OVERLAY_VERSION
    PKG_STAMP          = PKG_STAMP
  }
  labels = merge(oci_labels(trimprefix(PHP_TAG, "php-")), {
    for ext, version in ext_versions() : "net.mintopia.ext.${ext}.version" => version if contains(VERSIONS[PHP_VERSION].extensions, ext)
  })
}

target "cli" {
  inherits = ["_common"]
  target   = "cli"
  tags     = [tag("cli")]
  labels   = php_labels()
  contexts = { zts = "target:src-zts", ext = "target:src-ext" }
}

target "frankenphp" {
  inherits = ["_common"]
  target   = "frankenphp"
  tags     = [tag("frankenphp")]
  labels   = merge(php_labels(), { "net.mintopia.frankenphp.version" = FRANKENPHP_SRC_VERSION })
  contexts = { zts-frankenphp = "target:src-frankenphp", ext = "target:src-ext" }
}

target "php-fpm" {
  inherits = ["_common"]
  target   = "php-fpm"
  tags     = [tag("php-fpm")]
  labels   = php_labels()
  contexts = { fpm = "target:src-fpm", ext = "target:src-ext" }
}

target "php-fpm-nginx" {
  inherits = ["_common"]
  target   = "php-fpm-nginx"
  tags     = [tag("php-fpm-nginx")]
  contexts = { fpm = "target:src-fpm", ext = "target:src-ext" }
  labels = merge(php_labels(), {
    "net.mintopia.nginx.version" = NGINX_VERSION
    "net.mintopia.s6.version"    = S6_OVERLAY_VERSION
  })
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
}

target "_src" {
  dockerfile = "php-src.Dockerfile"
  platforms  = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  # anonymous GitHub API calls hit the shared runner IP rate limit
  secret = ["id=github_token,env=GITHUB_TOKEN"]
  args = {
    PHP_TAG                = PHP_TAG
    OS                     = OS
    ALPINE_VERSION         = ALPINE_VERSION
    PIE_VERSION            = PIE_VERSION
    FRANKENPHP_SRC_VERSION = FRANKENPHP_SRC_VERSION
    FRANKENPHP_SRC_SHA256  = FRANKENPHP_SRC_SHA256
    GO_VERSION             = GO_VERSION
    WATCHER_VERSION        = WATCHER_VERSION
    WATCHER_SHA256         = WATCHER_SHA256
    EXTENSIONS             = join(" ", VERSIONS[PHP_VERSION].extensions)
    GRPC_VERSION           = grpc_version()
    REDIS_VERSION          = REDIS_VERSION
    APCU_VERSION           = APCU_VERSION
    MONGODB_VERSION        = MONGODB_VERSION
    OPENTELEMETRY_VERSION  = OPENTELEMETRY_VERSION
    PROTOBUF_VERSION       = PROTOBUF_VERSION
  }
}

target "src-zts" {
  inherits = ["_src"]
  target   = "zts"
  contexts = products(["php"])
}

target "src-fpm" {
  inherits = ["_src"]
  target   = "fpm"
  contexts = products(["php"])
}

target "src-frankenphp" {
  inherits = ["_src"]
  target   = "zts-frankenphp"
  contexts = products(["php", "frankenphp"])
}

target "src-ext" {
  inherits = ["_src"]
  target   = "ext"
  contexts = products(concat(["php"], [for ext in ext_products() : "ext-${ext}"]))
}

target "product-php" {
  inherits = ["_src"]
  target   = "php"
}

target "product-frankenphp" {
  inherits = ["_src"]
  target   = "frankenphp"
  contexts = products(["php"])
}

target "product-ext" {
  name     = "product-ext-${ext}"
  matrix   = { ext = ext_products() }
  inherits = ["_src"]
  target   = "ext-${ext}"
  contexts = products(["php"])
}
