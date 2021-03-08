variable "aiven_api_token" {}
variable "aiven_project_name" {}

terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

resource "aiven_project" "sample" {
  project = var.aiven_project_name
}

resource "aiven_service" "cangrejokafka" {
  project                 = aiven_project.sample.project
  cloud_name              = "google-europe-west1"
  plan                    = "business-4"
  service_name            = "cangrejokafka"
  service_type            = "kafka"
  maintenance_window_dow  = "saturday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_version = "2.7"
  }
}

resource "aiven_kafka_topic" "orderstopic" {
  project         = aiven_project.sample.project
  service_name    = aiven_service.cangrejokafka.service_name
  topic_name      = "orderstopic"
  partitions      = 3
  replication     = 2
  config {
    retention_bytes = 1000000000
  }
}

resource "aiven_service_user" "kafkauser" {
  project      = aiven_project.sample.project
  service_name = aiven_service.cangrejokafka.service_name
  username     = "cangrejo"
}

#Alternatively a separate PG service for OLAP could be used, preferably only in case current perf issues can't be solved with SQL Tuning / Sharding etc.
resource "aiven_service" "pgservice" {
  project                 = aiven_project.sample.project
  cloud_name              = "google-europe-west1"
  plan                    = "business-4"
  service_name            = "pgservice"
  service_type            = "pg"
  maintenance_window_dow  = "saturday"
  maintenance_window_time = "12:00:00"
  pg_user_config {
    pg {
      idle_in_transaction_session_timeout = 900
    }
    #Cangrejo have v11 so we'd better maintain that to avoid surprises upstream
    pg_version = "11"
    #Separate OLAP instance could leverage Timescale:
    #variant    = "timescale"
  }
}

resource "aiven_database" "oltpdb" {
  project       = aiven_project.sample.project
  service_name  = aiven_service.pgservice.service_name
  database_name = "oltpdb"
}

resource "aiven_service_user" "cangrejouser" {
  project      = aiven_project.sample.project
  service_name = aiven_service.pgservice.service_name
  username     = "cangrejo"
}

resource "aiven_connection_pool" "samplepool" {
  project       = aiven_project.sample.project
  service_name  = aiven_service.pgservice.service_name
  database_name = aiven_database.oltpdb.database_name
  pool_name     = "samplepool"
  username      = aiven_service_user.cangrejouser.username
}

#Grafana would be used to integrate with Timescale (or with an alternative - e.g. ElasticSearch or M3DB whatever would be the best fit)
resource "aiven_service" "samplegrafana" {
  project      = aiven_project.sample.project
  cloud_name   = "google-europe-west1"
  plan         = "startup-4"
  service_name = "samplegrafana"
  service_type = "grafana"
  grafana_user_config {
    ip_filter = ["0.0.0.0/0"]
  }
}
