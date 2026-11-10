# Staging stack: the app and Prometheus on a private network, both hardened the same way as the
# local compose files (non-root, read-only root filesystem, no capabilities, resource limits).

locals {
  prefix = "sdl-${var.environment}"
}

resource "docker_network" "stack" {
  name = "${local.prefix}-net"
}

resource "docker_container" "app" {
  name  = "${local.prefix}-app"
  image = var.app_image

  user          = "10001:10001"
  read_only     = true
  restart       = "unless-stopped"
  memory        = 256
  memory_swap   = 256
  cpu_shares    = 512
  security_opts = ["no-new-privileges:true"]
  env           = ["APP_VERSION=${var.app_version}"]
  tmpfs         = { "/tmp" = "size=16m" }

  capabilities {
    drop = ["ALL"]
  }

  ports {
    internal = 8080
    external = var.app_host_port
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name    = docker_network.stack.name
    aliases = ["app"]
  }

  healthcheck {
    test         = ["CMD", "python", "-c", "import urllib.request as u, sys; sys.exit(0 if u.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"]
    interval     = "10s"
    timeout      = "3s"
    start_period = "5s"
    retries      = 3
  }
}

resource "docker_image" "prometheus" {
  name         = var.prometheus_image
  keep_locally = true
}

resource "docker_container" "prometheus" {
  name  = "${local.prefix}-prometheus"
  image = docker_image.prometheus.image_id

  user          = "65534:65534"
  read_only     = true
  restart       = "unless-stopped"
  memory        = 512
  memory_swap   = 512
  security_opts = ["no-new-privileges:true"]
  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/tmp/prometheus",
    "--storage.tsdb.retention.time=1d",
  ]
  tmpfs = { "/tmp" = "size=128m,uid=65534,gid=65534" }

  capabilities {
    drop = ["ALL"]
  }

  ports {
    internal = 9090
    external = var.prometheus_host_port
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = docker_network.stack.name
  }

  # Config is uploaded into the container instead of bind-mounting a host path.
  upload {
    file    = "/etc/prometheus/prometheus.yml"
    content = file("${path.module}/../../observability/prometheus.yml")
  }

  depends_on = [docker_container.app]
}
