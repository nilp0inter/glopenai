// Port of: examples/chat-store/
//
// Create a stored chat completion, then retrieve, list, and delete it.
//
// Run with: gleam run -m example/chat_store

import example/env
import gleam/dict
import gleam/io
import gleam/httpc
import gleam/option.{Some}
import glaoi/chat
import glaoi/config

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let metadata =
    dict.from_list([
      #("role", "manager"),
      #("department", "accounting"),
      #("source", "homepage"),
    ])

  let request =
    chat.new_create_request(model: "gpt-4o-mini", messages: [
      chat.system_message("You are a corporate IT support expert."),
      chat.user_message("How can I hide the dock on my Mac?"),
    ])
    |> chat.with_max_completion_tokens(512)
    |> chat.with_store(True)
    |> chat.with_metadata(metadata)

  let http_request = chat.create_request(cfg, request)

  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = chat.create_response(http_response)

  io.println("Chat Completion Response:")
  io.println("  id: " <> response.id)
  case response.choices {
    [choice, ..] ->
      case choice.message.content {
        Some(content) -> io.println("  content: " <> content)
        _ -> Nil
      }
    [] -> Nil
  }

  // The API doesn't return the chat completion immediately, so retrieval
  // doesn't work right away — sleep briefly before retrieving.
  sleep(5000)

  // Retrieve the stored completion
  io.println("\n--- Retrieve ---")
  let retrieve_req = chat.retrieve_request(cfg, response.id)
  let assert Ok(http_response) = httpc.send(retrieve_req)
  let assert Ok(retrieved) = chat.retrieve_response(http_response)
  io.println("  Retrieved id: " <> retrieved.id)

  // List stored completions
  io.println("\n--- List ---")
  let list_req = chat.list_request(cfg)
  let assert Ok(http_response) = httpc.send(list_req)
  let assert Ok(completions) = chat.list_response(http_response)
  io.println(
    "  has_more: " <> case completions.has_more {
      True -> "true"
      False -> "false"
    },
  )

  // Delete the completion
  io.println("\n--- Delete ---")
  let delete_req = chat.delete_request(cfg, response.id)
  let assert Ok(http_response) = httpc.send(delete_req)
  let assert Ok(deleted) = chat.delete_response(http_response)
  io.println(
    "  deleted: " <> case deleted.deleted {
      True -> "true"
      False -> "false"
    },
  )
}

@external(erlang, "timer", "sleep")
fn sleep(milliseconds: Int) -> anything
