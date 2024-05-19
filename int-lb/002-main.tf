#VPC network
resource "google_compute_network" "ilb_network" {
  name                    = "net1"
  provider                = google-beta
  auto_create_subnetworks = false
  project = var.project
}
#>>>

#Proxy-only subnet - Note: For multi region/subnet distribution 2 proxy subents are needed
resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "l7-ilb-proxy-subnet"
  project       = var.project
  provider      = google-beta
  ip_cidr_range = "10.133.2.0/24"
  region        = "europe-central2"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = google_compute_network.ilb_network.id
}
#>>>

#Backend subnet Note: For multi region/subnet distribution 2 backend subnets are needed
resource "google_compute_subnetwork" "ilb_subnet" {
  name          = "l7-ilb-subnet"
  provider      = google-beta
  project       = var.project
  ip_cidr_range = "10.132.32.0/24"
  region        = "europe-central2"
  network       = google_compute_network.ilb_network.id
  purpose = "PRIVATE"#hooooo
}
#>>>>>>

#Forwarding rule - regional Note: For Mulitiple subnet distribution only 1 fwd rule in the original region is needed
resource "google_compute_forwarding_rule" "google_compute_forwarding_rule" {
  name                  = "l7-ilb-forwarding-rule"
  project               = var.project
  provider              = google-beta
  region                = "europe-central2"
  depends_on            = [google_compute_subnetwork.proxy_subnet]
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"#INTERNAL_MANAGED check it again
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.default.id
  network               = google_compute_network.ilb_network.id
  subnetwork            = google_compute_subnetwork.ilb_subnet.id#hooooS
  network_tier          = "PREMIUM"
  allow_global_access   = true
}
#>>>

#HTTP target proxy -regional Note: For multiple subnet distribution proxy points to a modified URL map
resource "google_compute_region_target_http_proxy" "default" {
  name     = "l7-ilb-target-http-proxy"
  project  = var.project
  provider = google-beta
  region   = "europe-central2" #DISABLE FOR GLOBAL RESOURCES
  url_map  = google_compute_region_url_map.default.id
}
#>>>
#URL map - regional
resource "google_compute_region_url_map" "default" {
  name            = "l7-ilb-regional-url-map"
  project         = var.project
  provider        = google-beta
  region          = "europe-central2"
  default_service = google_compute_region_backend_service.default.id
}
#>>>

#Regional backend service Note: 2 backends needed for multi subnet distribution
resource "google_compute_region_backend_service" "default" {
  name                  = "l7-ilb-backend-subnet"
  project               = var.project
  provider              = google-beta
  region                = "europe-central2"
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"#CHECK IT - INTERNAL_MANAGED
  timeout_sec           = 10
  health_checks         = [google_compute_region_health_check.default.id]
  backend {
    group           = google_compute_region_instance_group_manager.mig.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}
#>>>
#Health check-regional Note: For multi subnet distribution 2 health checks are needed
resource "google_compute_region_health_check" "default" {
  name     = "l7-ilb-hc"
  project  = var.project
  provider = google-beta
  region   = "europe-central2" 
  http_health_check {
    port_specification = "USE_SERVING_PORT"
    request_path = "/"#Important
  }
}
#>>>>>>

#Instance-template Note: For multi subnet distribution 2 instance templates are needed
resource "google_compute_instance_template" "instance_template" {
  name         = "l7-ilb-mig-template"
  project      = var.project
  provider     = google-beta
  machine_type = "e2-small"
  tags         = ["http-server"]

  network_interface {
    network    = google_compute_network.ilb_network.id
    subnetwork = google_compute_subnetwork.ilb_subnet.id
    access_config {
      # add external ip to fetch packages- Needed for Healthy Load Balancer, Does not bode well when removed. 
    }
  }
  disk {
    source_image = "debian-cloud/debian-10"
    auto_delete  = true
    boot         = true
  }
  # install script for simple web server
  metadata = {
    startup-script = file("${path.module}/script.sh")
  }
  lifecycle {
    create_before_destroy = true
  }
}
#>>> Note: For multi subnet distribution 2 instance groups are needed
#Managed instance group
resource "google_compute_region_instance_group_manager" "mig" {
  name     = "l7-ilb-mig1"
  project  = var.project
  provider = google-beta
  region   = "europe-central2"
  version {
    instance_template = google_compute_instance_template.instance_template.id
    name              = "primary"
  }
  base_instance_name = "vm"
  target_size        = 3

    named_port {
    name = "http"
    port = 80
  }
}
#>>>
#Auto-scaling policy
resource "google_compute_region_autoscaler" "scale_1" {
  name     = "autoscaler"
  project  = var.project
  provider = google-beta
  target   = google_compute_region_instance_group_manager.mig.id
  region     = "europe-central2"
  autoscaling_policy {
    max_replicas = 8
    min_replicas = 3

    cpu_utilization {
      target = 0.6  # Target 60% CPU utilization
    }
  }
}
#>>>>>>

#Firewall rules
#Allow all access from google into my health check
resource "google_compute_firewall" "fw_iap" {
  name          = "l7-ilb-fw-allow-iap-hc"
  project = var.project
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.ilb_network.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports = ["80"]
  }
}
#>>>
#Allow http from proxy subnet to backends & Regional and Peering internal traffic
resource "google_compute_firewall" "fw_ilb_to_backends" {
  name          = "l7-ilb-fw-allow-ilb-to-backends"
  project = var.project
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.ilb_network.id
  source_ranges = ["10.133.2.0/24","10.176.32.0/24","10.176.76.0/24"] #proxy subnet range "10.133.2.0/24","10.176.32.0/24"
  target_tags   = ["http-server"]
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
}
#>>>

#SSH rule
resource "google_compute_firewall" "sssshhh" {
  name          = "sssshhh-rule"
  network       = google_compute_network.ilb_network.name
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
#>>>
#RDP Rule
resource "google_compute_firewall" "rule_poop" {
  name          = "rpoop"
  network       = google_compute_network.ilb_network.name
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["3389"]
  } 
}
#>>>>>>

#AUXILIARY RESOURCES
#Test instance inter-balancer region
resource "google_compute_instance" "vm_test" {
  name         = "imperial-advisor"
  project      = var.project
  provider     = google-beta
  zone         = "europe-central2-a"
  machine_type = "e2-small"
  network_interface {
    network    = google_compute_network.ilb_network.id
    subnetwork = google_compute_subnetwork.ilb_subnet.id
  }
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
}
#>>>

