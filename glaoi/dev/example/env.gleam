// Shared environment helpers for examples.

import gleam/io

/// Get the OPENAI_API_KEY from environment, or panic with a helpful message.
pub fn get_api_key() -> String {
  case get_env("OPENAI_API_KEY") {
    Ok(key) -> key
    Error(Nil) -> {
      io.println("Error: OPENAI_API_KEY environment variable not set")
      panic as "OPENAI_API_KEY not set"
    }
  }
}

@external(erlang, "example_env_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)
