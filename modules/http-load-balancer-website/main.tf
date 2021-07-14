# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A STATIC SITE WITH HTTP CLOUD LOAD BALANCER
# This module deploys a HTTP Load Balancer that directs traffic to Cloud Storage Bucket
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  # This module is now only being tested with Terraform 0.14.x. However, to make upgrading easier, we are setting
  # 0.12.26 as the minimum version, as that version added support for required_providers with source URLs, making it
  # forwards compatible with 0.14.x code.
  required_version = ">= 0.12.26"
}

# ------------------------------------------------------------------------------
# PREPARE COMMONLY USED LOCALS
# ------------------------------------------------------------------------------

locals {
  # We have to use dashes instead of dots in the bucket name, because
  # that bucket is not a website
  website_domain_name_dashed = replace(var.website_domain_name, ".", "-")

  # default
  redirect_website = length(var.default_host_redirect) > 0
}

module "load_balancer" {
  source = "github.com/othree/terraform-google-load-balancer.git//modules/http-load-balancer?ref=static-site"

  name                  = local.website_domain_name_dashed
  project               = var.project
  url_map               = google_compute_url_map.urlmap.self_link
  url_map_http          = var.default_https_redirect ? google_compute_url_map.urlmap_http[0].self_link : google_compute_url_map.urlmap.self_link
  create_dns_entries    = var.create_dns_entry
  custom_domain_names   = [var.website_domain_name]
  dns_managed_zone_name = var.dns_managed_zone_name
  dns_record_ttl        = var.dns_record_ttl
  enable_http           = var.enable_http || var.default_https_redirect
  enable_ssl            = var.enable_ssl
  ssl_certificates      = [var.ssl_certificate]
  custom_labels         = var.custom_labels
}

# ------------------------------------------------------------------------------
# CREATE THE URL MAP WITH THE BACKEND BUCKET AS DEFAULT SERVICE
# ------------------------------------------------------------------------------

resource "google_compute_url_map" "urlmap" {
  provider = google-beta
  project  = var.project

  name        = "${local.website_domain_name_dashed}-url-map"
  description = "URL map for ${local.website_domain_name_dashed}"

  default_service = !local.redirect_website ? google_compute_backend_bucket.static[0].self_link : null

  dynamic "default_url_redirect" {
    for_each = local.redirect_website ? ["default_redirect"] : []
    content {
      host_redirect          = length(var.default_host_redirect) > 0 ? var.default_host_redirect : null
      strip_query            = false
    }
  }
}

resource "google_compute_url_map" "urlmap_http" {
  provider = google-beta
  count    = var.default_https_redirect ? 1 : 0
  project  = var.project

  name        = "${local.website_domain_name_dashed}-url-map-http"
  description = "URL map for ${local.website_domain_name_dashed} http protocol"

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
  }
}

# ------------------------------------------------------------------------------
# CREATE THE BACKEND BUCKET
# ------------------------------------------------------------------------------

resource "google_compute_backend_bucket" "static" {
  provider = google-beta
  count    = local.redirect_website ? 0 : 1
  
  project  = var.project

  name                    = "${local.website_domain_name_dashed}-bucket"
  bucket_name             = module.site_bucket[0].website_bucket_name
  custom_response_headers = var.custom_headers
  enable_cdn              = var.enable_cdn
}

# ------------------------------------------------------------------------------
# CREATE CLOUD STORAGE BUCKET FOR CONTENT AND ACCESS LOGS
# ------------------------------------------------------------------------------

module "site_bucket" {
  source = "../cloud-storage-static-website"
  count    = local.redirect_website ? 0 : 1

  project = var.project

  website_domain_name   = local.website_domain_name_dashed
  website_acls          = var.website_acls
  website_location      = var.website_location
  website_storage_class = var.website_storage_class
  force_destroy_website = var.force_destroy_website

  index_page     = var.index_page
  not_found_page = var.not_found_page

  enable_versioning = var.enable_versioning

  access_log_prefix                   = var.access_log_prefix
  access_logs_expiration_time_in_days = var.access_logs_expiration_time_in_days
  force_destroy_access_logs_bucket    = var.force_destroy_access_logs_bucket

  website_kms_key_name     = var.website_kms_key_name
  access_logs_kms_key_name = var.access_logs_kms_key_name

  enable_cors          = var.enable_cors
  cors_extra_headers   = var.cors_extra_headers
  cors_max_age_seconds = var.cors_max_age_seconds
  cors_methods         = var.cors_methods
  cors_origins         = var.cors_origins

  # We don't want a separate CNAME entry
  create_dns_entry = false

  custom_labels = var.custom_labels
}
