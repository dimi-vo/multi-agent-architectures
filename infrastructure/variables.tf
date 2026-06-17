variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "cc_region" {
  type        = string
  description = "The region where our CC cluster resides"
}

variable "prefix" {
  description = "Prefix for resources"
  type        = string
  default     = "dvogiatzis"
}

variable "cloud_provider" {
  description = "The cloud provider for the Kafka cluster."
  type        = string
  default     = "AWS"
}

# AWS Bedrock
variable "aws_access_key" {
  description = "AWS access key for Bedrock connection"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key for Bedrock connection"
  type        = string
  sensitive   = true
}

variable "bedrock_endpoint" {
  description = "AWS Bedrock model endpoint URL"
  type        = string
  default     = "https://bedrock-runtime.us-east-1.amazonaws.com/model/global.anthropic.claude-sonnet-4-6/invoke"
}

# A2A agent endpoints (ngrok URLs)
variable "a2a_url_market_research" {
  description = "Public URL (ngrok) for the market research A2A agent"
  type        = string
}

variable "a2a_url_creative_design" {
  description = "Public URL (ngrok) for the creative design A2A agent"
  type        = string
}

variable "a2a_url_copywriting" {
  description = "Public URL (ngrok) for the copywriting A2A agent"
  type        = string
}

variable "a2a_password" {
  description = "Password for A2A connections. It does not matter."
  type        = string
  sensitive   = true
  default = "password"
}
