# ========================================
# Flink Compute Pool, Connections, Model, Tools, Agent
# ========================================

resource "confluent_flink_compute_pool" "flinkpool-main" {
  display_name = "${var.prefix}_standard_compute_pool_${random_id.resource_suffix.hex}"
  cloud        = var.cloud_provider
  region       = var.cc_region
  max_cfu      = 10
  environment {
    id = confluent_environment.staging.id
  }
}

data "confluent_flink_region" "main" {
  cloud  = var.cloud_provider
  region = var.cc_region
}

# Service account that owns the Flink API key
resource "confluent_service_account" "flink-manager" {
  display_name = "${var.prefix}-flink-manager"
  description  = "Service account that owns the Flink API key"
}

# Service account that runs Flink statements as principal
resource "confluent_service_account" "flink-statements-runner" {
  display_name = "${var.prefix}-flink-statements-runner"
  description  = "Service account that runs Flink statements"
}

resource "confluent_role_binding" "flink-manager-flink-developer" {
  principal   = "User:${confluent_service_account.flink-manager.id}"
  role_name   = "FlinkDeveloper"
  crn_pattern = confluent_environment.staging.resource_name
}

resource "confluent_role_binding" "flink-statements-runner-environment-admin" {
  principal   = "User:${confluent_service_account.flink-statements-runner.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.staging.resource_name
}

resource "confluent_role_binding" "flink-manager-assigner" {
  principal   = "User:${confluent_service_account.flink-manager.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.flink-statements-runner.id}"
}

resource "confluent_api_key" "flink-manager-flink-api-key" {
  display_name = "${var.prefix}-flink-api-key"
  description  = "Flink API Key owned by 'flink-manager' service account"
  owner {
    id          = confluent_service_account.flink-manager.id
    api_version = confluent_service_account.flink-manager.api_version
    kind        = confluent_service_account.flink-manager.kind
  }

  managed_resource {
    id          = data.confluent_flink_region.main.id
    api_version = data.confluent_flink_region.main.api_version
    kind        = data.confluent_flink_region.main.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.flink-manager-flink-developer,
    confluent_role_binding.flink-manager-assigner,
  ]
}

locals {
  flink_properties = {
    "sql.current-catalog"  = confluent_environment.staging.display_name
    "sql.current-database" = confluent_kafka_cluster.standard.display_name
  }
}

# ========================================
# Bedrock Connection (first-class resource)
# ========================================

resource "confluent_flink_connection" "bedrock" {
  display_name   = "my-bedrock-connection"
  type           = "BEDROCK"
  endpoint       = var.bedrock_endpoint
  aws_access_key = var.aws_access_key
  aws_secret_key = var.aws_secret_key

  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }
}

# ========================================
# LLM Model
# ========================================

resource "confluent_flink_statement" "create-model-llm" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE MODEL `llm-model`
      INPUT (`text` VARCHAR(2147483647))
      OUTPUT (`output` VARCHAR(2147483647))
      WITH (
        'provider'                   = 'bedrock',
        'task'                       = 'text_generation',
        'bedrock.connection'         = 'my-bedrock-connection',
        'bedrock.params.max_tokens'  = '50000',
        'bedrock.system_prompt'      = 'You are a polite assistant.'
      );
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [confluent_flink_connection.bedrock]
}

# ========================================
# A2A Connections (via flink_statement — A2A type not supported by flink_connection)
# ========================================

resource "confluent_flink_statement" "a2a-connection-market-research" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement  = <<-SQL
    CREATE CONNECTION a2a_connection_market_research
      WITH (
        'type'     = 'a2a',
        'endpoint' = '${var.a2a_url_market_research}',
        'username' = 'username',
        'password' = '{{sessionconfig/sql.secrets.a2a_password}}'
      );
  SQL
  properties = local.flink_properties
  properties_sensitive = {
    "sql.secrets.a2a_password" = var.a2a_password
  }
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }
}

resource "confluent_flink_statement" "a2a-connection-creative-design" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement  = <<-SQL
    CREATE CONNECTION a2a_connection_creative_design
      WITH (
        'type'     = 'a2a',
        'endpoint' = '${var.a2a_url_creative_design}',
        'username' = 'username',
        'password' = '{{sessionconfig/sql.secrets.a2a_password}}'
      );
  SQL
  properties = local.flink_properties
  properties_sensitive = {
    "sql.secrets.a2a_password" = var.a2a_password
  }
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }
}

resource "confluent_flink_statement" "a2a-connection-copywriting" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement  = <<-SQL
    CREATE CONNECTION a2a_connection_copywriting
      WITH (
        'type'     = 'a2a',
        'endpoint' = '${var.a2a_url_copywriting}',
        'username' = 'username',
        'password' = '{{sessionconfig/sql.secrets.a2a_password}}'
      );
  SQL
  properties = local.flink_properties
  properties_sensitive = {
    "sql.secrets.a2a_password" = var.a2a_password
  }
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }
}

# ========================================
# A2A Tools
# ========================================

resource "confluent_flink_statement" "tool-market-research" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE TOOL a2a_service_market_research
    USING CONNECTION a2a_connection_market_research
    WITH (
      'type' = 'a2a',
      'agent_card_path' = '/.well-known/agent-card.json',
      'request_timeout' = '30'
    );
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [confluent_flink_statement.a2a-connection-market-research]
}

resource "confluent_flink_statement" "tool-creative-design" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE TOOL a2a_service_creative_design
    USING CONNECTION a2a_connection_creative_design
    WITH (
      'type' = 'a2a',
      'agent_card_path' = '/.well-known/agent-card.json',
      'request_timeout' = '30'
    );
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [confluent_flink_statement.a2a-connection-creative-design]
}

resource "confluent_flink_statement" "tool-copywriting" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE TOOL a2a_service_copywriting
    USING CONNECTION a2a_connection_copywriting
    WITH (
      'type' = 'a2a',
      'agent_card_path' = '/.well-known/agent-card.json',
      'request_timeout' = '30'
    );
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [confluent_flink_statement.a2a-connection-copywriting]
}

# ========================================
# Marketing Orchestrator Agent
# ========================================

resource "confluent_flink_statement" "agent-marketing-orchestrator" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE AGENT marketing_orchestrator_agent
    USING MODEL `llm-model`
    USING PROMPT 
    '
      You are the supervisor agent. But this is just a test. Since we are in a test environment, you just need to check that each tool gives you a response.
      Use each one of the tools at your disposal. Pass the following text as input to the tool "Foobar".
      Collect the responses from all the tools and concatenate them. Do not analyze them.
      Your response should read
      [tool] - [tool response]
      Do that for every tool use.
      When you respond start the sentence with the word "AHOI!
    '
    USING TOOLS a2a_service_market_research, a2a_service_creative_design, a2a_service_copywriting
    WITH (
      'tokens_management_strategy' = 'summarize',
      'max_tokens_threshold'       = '80000',
      'summarization_prompt'       = 'concise',
      'handle_exception'           = 'fail',
      'max_consecutive_failures'   = '1',
      'max_iterations'             = '3',
      'request_timeout'            = '180'
    );
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [
    confluent_flink_statement.create-model-llm,
    confluent_flink_statement.tool-market-research,
    confluent_flink_statement.tool-creative-design,
    confluent_flink_statement.tool-copywriting,
  ]
}

# ========================================
# CTAS — Agent Responses Table
# ========================================

resource "confluent_flink_statement" "ctas-marketing-event-agent-responses" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE TABLE marketing_event_agent_responses AS
    SELECT
      me.`message`,
      agent_result.status,
      agent_result.response
    FROM `marketing_event` AS me,
    LATERAL TABLE (
      AI_RUN_AGENT(
        'marketing_orchestrator_agent',
        CONCAT('Topic: ', DECODE(me.`key`, 'UTF-8'), ' Request: ', me.`message`)
      )
    ) AS agent_result(status, response);
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [
    confluent_flink_statement.agent-marketing-orchestrator,
    confluent_kafka_topic.marketing_event,
  ]
}

# ========================================
# Marketing Finalizer Agent
# ========================================

resource "confluent_flink_statement" "agent-marketing-finalizer" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE AGENT marketing_finalizer_agent
    USING MODEL `llm-model`
    USING PROMPT 'Your task is to beautify the input you receive. Nothing else. Just make the text prettier and easier to read.'
    WITH (
      'tokens_management_strategy' = 'summarize',
      'max_tokens_threshold'       = '80000',
      'summarization_prompt'       = 'concise',
      'handle_exception'           = 'fail',
      'max_consecutive_failures'   = '1',
      'max_iterations'             = '3',
      'request_timeout'            = '180'
    );
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [
    confluent_flink_statement.create-model-llm,
  ]
}

# ========================================
# CTAS — Finalizer Agent Responses Table
# ========================================

resource "confluent_flink_statement" "ctas-finalizer-agent-responses" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.flink-statements-runner.id
  }
  statement     = <<-SQL
    CREATE TABLE finalizer_agent_responses AS
    SELECT
      mar.`message`,
      agent_result.status,
      agent_result.response
    FROM `marketing_event_agent_responses` AS mar,
    LATERAL TABLE (
      AI_RUN_AGENT(
        'marketing_finalizer_agent',
        mar.`message`
      )
    ) AS agent_result(status, response);
  SQL
  properties    = local.flink_properties
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-manager-flink-api-key.id
    secret = confluent_api_key.flink-manager-flink-api-key.secret
  }

  depends_on = [
    confluent_flink_statement.agent-marketing-finalizer,
    confluent_flink_statement.ctas-marketing-event-agent-responses,
  ]
}
