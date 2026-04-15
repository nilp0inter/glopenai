// Port of: examples/models/
//
// List all available models and retrieve a specific one.
//
// Run with: gleam run -m example/model

import example/env
import gleam/int
import gleam/io
import gleam/list
import gleam/httpc
import glaoi/config
import glaoi/model

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // List models
  let list_req = model.list_request(cfg)
  let assert Ok(http_response) = httpc.send(list_req)
  let assert Ok(model_list) = model.list_response(http_response)

  io.println(
    "Found " <> int.to_string(list.length(model_list.data)) <> " models",
  )
  list.each(model_list.data, fn(m) {
    io.println("  - " <> m.id <> " (owned by " <> m.owned_by <> ")")
  })

  // Retrieve a specific model
  io.println("\nRetrieving gpt-4o-mini:")
  let retrieve_req = model.retrieve_request(cfg, "gpt-4o-mini")
  let assert Ok(http_response) = httpc.send(retrieve_req)
  let assert Ok(m) = model.retrieve_response(http_response)
  io.println("  id: " <> m.id)
  io.println("  owned_by: " <> m.owned_by)
  io.println("  created: " <> int.to_string(m.created))
}
