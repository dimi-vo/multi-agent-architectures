CREATE CONNECTION my_bedrock_connection
  WITH (
    'type' = 'bedrock',
    'endpoint'       = 'https://bedrock-runtime.us-east-1.amazonaws.com/model/global.anthropic.claude-sonnet-4-6/invoke',
    'aws-access-key' = '*****',
    'aws-secret-key' = '*****'
  );

CREATE MODEL `llm-model`
  INPUT (`text` VARCHAR(2147483647))
  OUTPUT (`output` VARCHAR(2147483647))
  WITH (
    'provider'                   = 'bedrock',
    'task'                       = 'text_generation',
    'bedrock.connection'         = 'my_bedrock_connection',
    'bedrock.params.max_tokens'  = '50000',
    'bedrock.system_prompt'      = 'You are a polite assistant.'
  );

CREATE CONNECTION a2a_connection_market_research
  WITH (
    'type' = 'a2a',
    'endpoint' = '*******',
    'username' = '*******',
    'password' = '*******'
  );

CREATE TOOL a2a_service_market_research
USING CONNECTION a2a_connection_market_research
WITH (
  'type' = 'a2a',
  'agent_card_path' = '/.well-known/agent-card.json',
  'request_timeout' = '30'
);

CREATE CONNECTION a2a_connection_creative_design
  WITH (
    'type' = 'a2a',
    'endpoint' = '*******',
    'username' = '*******',
    'password' = '*******'
  );

CREATE TOOL a2a_service_creative_design
USING CONNECTION a2a_connection_creative_design
WITH (
  'type' = 'a2a',
  'agent_card_path' = '/.well-known/agent-card.json',
  'request_timeout' = '30'
);

CREATE CONNECTION a2a_connection_copywriting
  WITH (
    'type' = 'a2a',
    'endpoint' = '*******',
    'username' = '*******',
    'password' = '*******'
  );

CREATE TOOL a2a_service_copywriting
USING CONNECTION a2a_connection_copywriting
WITH (
  'type' = 'a2a',
  'agent_card_path' = '/.well-known/agent-card.json',
  'request_timeout' = '30'
);

CREATE AGENT marketing_orchestrator_agent
USING MODEL `llm-model`
USING PROMPT '
You are orchestrating the market research. 
As the supervisor agent you analyze the campaign requirements, identify key deliverables, determine resource
allocation, and create a strategic execution plan. For the specific tasks make use of the tool available to you.
When you respond start the sentence with the word "AHOI!"
'
USING TOOLS a2a_service_market_research, a2a_service_creative_design, a2a_service_copywriting
WITH (
  'tokens_management_strategy' = 'summarize',
  'max_tokens_threshold'       = '80000',
  'summarization_prompt'       = 'concise',
  'handle_exception'           = 'fail',
  'max_consecutive_failures'   = '1',
  'max_iterations'             = '3',
  'request_timeout'            = '60'
);

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
