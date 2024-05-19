terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "5.27.0"
    }
  }
 backend gcs {
    bucket = "armageddon-repository"
    credentials = "poop.json"
    prefix = "prod"
  }
 
}
#>>>

provider google {
  # Configuration options
  credentials = var.bonnefete 
  project = var.project
  region = var.region
}
#>>>
#Config-Variables
variable project {
    type= string
    default = "pooper-scooper"
    description = "ID Google project"
}

variable region {
    type= string
    default = "europe-central2"
    description = "Region Google project"
}

variable  data_project {
    type = string
    default = "general-storage-1"
    description = "Name of data pipeline project to use as resource prefix"
}

variable "bonnefete" {
    type = string
    default = "poop.json"
    description = "Path to the service account key file"
  
}
#>>>>>>