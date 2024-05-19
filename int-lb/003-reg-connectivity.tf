#Alternative test subent within network 1
resource "google_compute_subnetwork" "test_subnet" {
  name          = "test-subnet"
  project       = var.project
  provider      = google-beta
  ip_cidr_range = "10.176.32.0/24"
  region        = "europe-north1"
  role          = "ACTIVE"
  network       = google_compute_network.ilb_network.id
}
#>>>>>>

#Windows VM
resource "google_compute_instance" "vm_instance_2" {
  name         = "viking-1"
  machine_type = "n2-standard-4"
  zone         = "europe-north1-a"
  boot_disk {
    initialize_params {
      image = "projects/windows-cloud/global/images/windows-server-2022-dc-v20240415"
      size = 50 
      type = "pd-balanced"
    }
  }
  network_interface {
    access_config {
      // Ephemeral IP
      network_tier = "PREMIUM"
    }
    subnetwork = google_compute_subnetwork.test_subnet.id
    stack_type  = "IPV4_ONLY"
  }
  service_account {
    email  = "876288284083-compute@developer.gserviceaccount.com"
    scopes = ["https://www.googleapis.com/auth/devstorage.read_only", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write", "https://www.googleapis.com/auth/service.management.readonly", "https://www.googleapis.com/auth/servicecontrol", "https://www.googleapis.com/auth/trace.append"]
  }
  depends_on = [ google_compute_subnetwork.test_subnet]
  tags   = ["http-server"]
}
#>>>

#Debian Machine
resource "google_compute_instance" "vm_test2" {
  name         = "viking-2"
  project      = var.project
  provider     = google-beta
  zone         = "europe-north1-a"
  machine_type = "e2-small"
  network_interface {
    network    = google_compute_network.ilb_network.id
    subnetwork = google_compute_subnetwork.test_subnet.id
  }
  tags = ["http-server"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
}
#>>>>>>

#Peering Test Network
resource "google_compute_network" "iabc" {
  name                    = "net2"
  provider                = google-beta
  auto_create_subnetworks = false
  project = var.project
}
#>>>

#Test Subnet within network 2
resource "google_compute_subnetwork" "test_subnet2" {
  name          = "test-subnet22"
  project       = var.project
  provider      = google-beta
  ip_cidr_range = "10.176.76.0/24"
  region        = "europe-north1"
  role          = "ACTIVE"
  network       = google_compute_network.iabc.id
}
#>>>>>

#Test Instance within network 2 - DEBIAN
resource "google_compute_instance" "vm_test3" {
  name         = "viking-3"
  project      = var.project
  provider     = google-beta
  zone         = "europe-north1-a"
  machine_type = "e2-small"
  network_interface {
    network    = google_compute_network.iabc.id
    subnetwork = google_compute_subnetwork.test_subnet2.id
  }
  tags = ["http-server"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
  depends_on = [ google_compute_subnetwork.test_subnet2 ]
}
#>>>>>>

#Peering configuration
resource "google_compute_network_peering" "peering1" {
  name         = "peering1"
  network      = google_compute_network.ilb_network.self_link
  peer_network = google_compute_network.iabc.self_link
}
#>>>
resource "google_compute_network_peering" "peering2" {
  name         = "peering2"
  network      = google_compute_network.iabc.self_link
  peer_network = google_compute_network.ilb_network.self_link
}
#>>>>>

#Firewall rules
resource "google_compute_firewall" "rpoop2" {
  name          = "rpoop2"
  network       = google_compute_network.iabc.id
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
#>>>

