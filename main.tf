terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {
  host = var.docker_host_path != null ? var.docker_host_path : null
}

resource "docker_network" "appnet" {
  name = "appnet"
}

resource "docker_image" "api_image" {
  name = "api-image"
  build {
    context = "./api"
  }
}

# --- CHANGE 1: Pin HAProxy to a specific version ---
resource "docker_image" "haproxy_image" {
  name         = "haproxy:2.8"
  keep_locally = true
}

resource "docker_container" "api_onprem" {
  name = "api-onprem"
  image = docker_image.api_image.image_id
  ports {
    internal = 5000
    external = 5000
  }
  networks_advanced {
    name = docker_network.appnet.name
  }
}

resource "docker_container" "api_cloud" {
  name = "api-cloud"
  image = docker_image.api_image.image_id
  ports {
    internal = 5000
    external = 5001
  }
  networks_advanced {
    name = docker_network.appnet.name
  }
}

resource "docker_container" "haproxy" {
  name = "haproxy-server"
  image = docker_image.haproxy_image.image_id

  ports {
    internal = 80
    external = 80
  }
  volumes {
    host_path      = "${path.cwd}/haproxy"
    container_path = "/usr/local/etc/haproxy"
    read_only      = true
  }
  networks_advanced {
    name = docker_network.appnet.name
  }
  depends_on = [
    docker_container.api_onprem,
    docker_container.api_cloud,
  ]
}

resource "docker_container" "haproxy_exporter" {
  name  = "haproxy-exporter"
  image = "prom/haproxy-exporter:v0.14.0" 

  command = ["--haproxy.scrape-uri=http://admin:password@haproxy-server/haproxy?stats;csv"]

  networks_advanced {
    name = docker_network.appnet.name
  }

  depends_on = [
    docker_container.haproxy,
  ]
}

resource "docker_container" "prometheus" {
  name  = "prometheus"
  image = "prom/prometheus:v2.45.0"

  networks_advanced {
    name = docker_network.appnet.name
  }

  ports {
    internal = 9090
    external = 9090
  }

  volumes {
    host_path      = "${path.cwd}/prometheus"
    container_path = "/etc/prometheus"
    read_only      = true
  }

  depends_on = [
    docker_container.haproxy_exporter,
  ]
}

resource "docker_container" "grafana" {
  name  = "grafana"
  image = "grafana/grafana:9.5.1"

  networks_advanced {
    name = docker_network.appnet.name
  }

  ports {
    internal = 3000
    external = 3000
  }

  depends_on = [
    docker_container.prometheus,
  ]
}

resource "docker_container" "alertmanager" {
  name  = "alertmanager"
  image = "prom/alertmanager:v0.25.0"

  ports {
    internal = 9093
    external = 9093
  }

  networks_advanced {
    name = docker_network.appnet.name
  }

  volumes {
    host_path      = "${path.cwd}/alertmanager"
    container_path = "/etc/alertmanager"
    read_only      = true
  }
}


