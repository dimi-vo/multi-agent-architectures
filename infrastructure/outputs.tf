output "dotenv" {
  value = <<-EOT
# Kafka cluster
KAFKA_BOOTSTRAP_SERVERS="${replace(confluent_kafka_cluster.standard.bootstrap_endpoint, "SASL_SSL://", "")}"
# producer
KAFKA_API_KEY="${confluent_api_key.app-producer-kafka-api-key.id}"
KAFKA_API_SECRET="${confluent_api_key.app-producer-kafka-api-key.secret}"
# consumer
KAFKA_CONSUMER_API_KEY="${confluent_api_key.app-consumer-kafka-api-key.id}"
KAFKA_CONSUMER_API_SECRET="${confluent_api_key.app-consumer-kafka-api-key.secret}"

# Schema Registry
SCHEMA_REGISTRY_URL="${data.confluent_schema_registry_cluster.advanced.rest_endpoint}"
SCHEMA_REGISTRY_API_KEY="${confluent_api_key.env-manager-schema-registry-api-key.id}"
SCHEMA_REGISTRY_API_SECRET="${confluent_api_key.env-manager-schema-registry-api-key.secret}"
EOT

  sensitive = true
}

output "producer_properties" {
  description = "Content for producer/producer.properties"
  value       = <<-EOT
bootstrap.servers=${replace(confluent_kafka_cluster.standard.bootstrap_endpoint, "SASL_SSL://", "")}
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
sasl.username=${confluent_api_key.app-producer-kafka-api-key.id}
sasl.password=${confluent_api_key.app-producer-kafka-api-key.secret}
schema.registry.url=${data.confluent_schema_registry_cluster.advanced.rest_endpoint}
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${confluent_api_key.env-manager-schema-registry-api-key.id}:${confluent_api_key.env-manager-schema-registry-api-key.secret}
EOT

  sensitive = true
}
