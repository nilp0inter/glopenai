import gleam/option.{type Option, None, Some}

/// Default OpenAI API v1 base URL.
pub const default_api_base = "https://api.openai.com/v1"

/// Configuration for OpenAI API requests.
pub type Config {
  Config(
    api_base: String,
    api_key: String,
    org_id: Option(String),
    project_id: Option(String),
    custom_headers: List(#(String, String)),
  )
}

/// Create a new config with the given API key and the default base URL.
pub fn new(api_key api_key: String) -> Config {
  Config(
    api_base: default_api_base,
    api_key: api_key,
    org_id: None,
    project_id: None,
    custom_headers: [],
  )
}

/// Set a custom API base URL (e.g. for proxies or compatible APIs).
pub fn with_api_base(config: Config, api_base: String) -> Config {
  Config(..config, api_base: api_base)
}

/// Set the organization ID header (OpenAI-Organization).
pub fn with_org_id(config: Config, org_id: String) -> Config {
  Config(..config, org_id: Some(org_id))
}

/// Set the project ID header (OpenAI-Project).
pub fn with_project_id(config: Config, project_id: String) -> Config {
  Config(..config, project_id: Some(project_id))
}

/// Add a custom header to all requests.
pub fn with_header(config: Config, key: String, value: String) -> Config {
  Config(..config, custom_headers: [#(key, value), ..config.custom_headers])
}

/// Configuration for Azure OpenAI Service.
pub type AzureConfig {
  AzureConfig(
    api_base: String,
    api_key: String,
    deployment_id: String,
    api_version: String,
  )
}

/// Create a new Azure config.
pub fn new_azure(
  api_base api_base: String,
  api_key api_key: String,
  deployment_id deployment_id: String,
  api_version api_version: String,
) -> AzureConfig {
  AzureConfig(
    api_base: api_base,
    api_key: api_key,
    deployment_id: deployment_id,
    api_version: api_version,
  )
}
