terraform {
  required_version = ">= 1.5.0"

  required_providers {
    scylladbcloud = {
      source  = "scylladb/scylladbcloud"
      version = "~> 1.9"
    }
  }
}

provider "scylladbcloud" {
  # Reads SCYLLA_API_TOKEN from environment
}
