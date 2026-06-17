data "confluent_organization" "main" {}

resource "random_id" "resource_suffix" {
  byte_length = 4
}
# Create new environment
resource "confluent_environment" "staging" {
  display_name = "${var.prefix}-demo"

  stream_governance {
    package = "ADVANCED"
  }
}

# Get reference of Schema Registry Cluster
data "confluent_schema_registry_cluster" "advanced" {
  environment {
    id = confluent_environment.staging.id
  }

  depends_on = [
    confluent_kafka_cluster.standard
  ]
}

# Create standard Cluster
resource "confluent_kafka_cluster" "standard" {
  display_name = "${var.prefix}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = var.cloud_provider
  region       = var.cc_region
  standard {}
  environment {
    id = confluent_environment.staging.id
  }
}

# Create an SA to manage the cluster
resource "confluent_service_account" "app-manager" {
  display_name = "${var.prefix}-app-manager"
  description  = "Service account to manage Kafka cluster"
}

# Role Binding for interacting with the Kafka cluster
resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.standard.rbac_crn
}

# Confluent API Key for the app-manager SA
resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "${var.prefix}-app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]
}

resource "confluent_kafka_topic" "marketing_event" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name    = "marketing_event"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

# Enable RTCE for the purchases topic
resource "confluent_rtce_topic" "marketing_event" {
  cloud       = var.cloud_provider
  region      = var.cc_region
  description = "RTCE-enabled purchases topic for real-time querying"

  environment {
    id = confluent_environment.staging.id
  }

  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  topic_name = confluent_kafka_topic.marketing_event.topic_name
}

resource "confluent_service_account" "app-consumer" {
  display_name = "${var.prefix}-app-consumer"
  description  = "Service account to consume from Kafka topics"
}

resource "confluent_api_key" "app-consumer-kafka-api-key" {
  display_name = "${var.prefix}-app-consumer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-consumer' service account"
  owner {
    id          = confluent_service_account.app-consumer.id
    api_version = confluent_service_account.app-consumer.api_version
    kind        = confluent_service_account.app-consumer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
}

resource "confluent_kafka_acl" "app-consumer-all-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-consumer-all-groups" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "GROUP"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}


# SA for the producer
resource "confluent_service_account" "app-producer" {
  display_name = "${var.prefix}-app-producer"
  description  = "Service account to produce to Kafka topics"
}

# API Key for the producer SA
resource "confluent_api_key" "app-producer-kafka-api-key" {
  display_name = "${var.prefix}-app-producer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-producer' service account"
  owner {
    id          = confluent_service_account.app-producer.id
    api_version = confluent_service_account.app-producer.api_version
    kind        = confluent_service_account.app-producer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
}

# ACL for the producer to write to any topic
resource "confluent_kafka_acl" "app-producer-write-on-any-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

# SA for managing the environment. Needed to create the schema
resource "confluent_service_account" "env-manager" {
  display_name = "${var.prefix}-env-manager"
  description  = "Service account to manage 'Staging' environment"
}

# Grant Environment Admin role to the SA
resource "confluent_role_binding" "env-manager-environment-admin" {
  principal   = "User:${confluent_service_account.env-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.staging.resource_name
}

# Create API Key for the env-manager SA
resource "confluent_api_key" "env-manager-schema-registry-api-key" {
  display_name = "${var.prefix}-env-manager-schema-registry-api-key"
  description  = "Schema Registry API Key that is owned by 'env-manager' service account"
  owner {
    id          = confluent_service_account.env-manager.id
    api_version = confluent_service_account.env-manager.api_version
    kind        = confluent_service_account.env-manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.advanced.id
    api_version = data.confluent_schema_registry_cluster.advanced.api_version
    kind        = data.confluent_schema_registry_cluster.advanced.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.env-manager-environment-admin
  ]
}

resource "confluent_schema" "marketing_event_value" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.advanced.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.advanced.rest_endpoint
  subject_name  = "marketing_event-value"
  format        = "AVRO"
  schema = jsonencode({
    type      = "record"
    name      = "MarketingEvent"
    namespace = "com.vogiatzis.marketing"
    fields = [
      {
        name = "message"
        type = "string"
      }
    ]
  })
  credentials {
    key    = confluent_api_key.env-manager-schema-registry-api-key.id
    secret = confluent_api_key.env-manager-schema-registry-api-key.secret
  }
}


# ========================================
# Global API Key for RTCE MCP Server
# WARNING: This creates an OrganizationAdmin service account with cloud-level API key.
# In production, follow the principle of least privilege:
# - Use environment-scoped or resource-scoped keys when possible
# - Create a custom role with only the permissions needed for RTCE MCP access
# - Rotate keys regularly and store them securely (e.g., in a secrets manager)
# ========================================

# Create service account for RTCE MCP access
resource "confluent_service_account" "rtce-mcp" {
  display_name = "${var.prefix}-rtce-mcp-sa"
  description  = "Service account for RTCE MCP server access (OrgAdmin - NOT RECOMMENDED FOR PRODUCTION)"
}

# Grant OrganizationAdmin role (required for RTCE MCP access)
# NOTE: This is overly permissive for production use
resource "confluent_role_binding" "rtce-mcp-org-admin" {
  principal   = "User:${confluent_service_account.rtce-mcp.id}"
  role_name   = "OrganizationAdmin"
  crn_pattern = data.confluent_organization.main.resource_name
}

# Create cloud API key (not scoped to any specific resource)
resource "confluent_api_key" "rtce-mcp-cloud-api-key" {
  display_name = "${var.prefix}-rtce-mcp-cloud-api-key"
  description  = "Cloud API Key for RTCE MCP server (global scope)"

  owner {
    id          = confluent_service_account.rtce-mcp.id
    api_version = confluent_service_account.rtce-mcp.api_version
    kind        = confluent_service_account.rtce-mcp.kind
  }

  depends_on = [
    confluent_role_binding.rtce-mcp-org-admin
  ]
}
