variable "environment" {
  description = "Name used to prefix every resource, so several stacks can share one Docker host."
  type        = string
  default     = "staging"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.environment))
    error_message = "environment must be lowercase letters, digits and dashes, 2-21 characters."
  }
}

variable "app_image" {
  description = "Application image, pinned by digest: ghcr.io/<owner>/secure-delivery-lab@sha256:<digest>."
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.app_image))
    error_message = "app_image must be pinned by digest (…@sha256:<64 hex>), never by a mutable tag."
  }
}

variable "app_version" {
  description = "Version string reported by the app."
  type        = string
  default     = "dev"
}

variable "app_host_port" {
  description = "Port published on 127.0.0.1 for the app."
  type        = number
  default     = 8080
}

variable "prometheus_host_port" {
  description = "Port published on 127.0.0.1 for Prometheus."
  type        = number
  default     = 9090
}

variable "prometheus_image" {
  description = "Prometheus image, pinned by digest."
  type        = string
  default     = "prom/prometheus:v3.5.0@sha256:63805ebb8d2b3920190daf1cb14a60871b16fd38bed42b857a3182bc621f4996"
}
