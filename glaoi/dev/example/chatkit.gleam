// Port of: examples/chatkit/src/main.rs
//
// Creates a ChatKit session for a given workflow, then cancels it.
//
// ChatKit is in beta — it requires the `OpenAI-Beta: chatkit_beta=v1` header.
//
// Run with:
//   export OPENAI_API_KEY=...
//   export CHATKIT_WORKFLOW_ID=wf_...
//   gleam run -m example/chatkit

import example/env
import gleam/httpc
import gleam/int
import gleam/io
import glaoi/chatkit
import glaoi/config

pub fn main() -> Nil {
  let api_key = env.get_api_key()
  let workflow_id = case env.get_env_var("CHATKIT_WORKFLOW_ID") {
    Ok(value) -> value
    Error(Nil) -> {
      io.println(
        "Error: CHATKIT_WORKFLOW_ID environment variable not set",
      )
      panic as "CHATKIT_WORKFLOW_ID not set"
    }
  }

  io.println("Using workflow_id: " <> workflow_id)

  // ChatKit is in beta and the dedicated header must be sent on every call.
  let cfg =
    config.new(api_key: api_key)
    |> config.with_header("OpenAI-Beta", "chatkit_beta=v1")

  // 1. Create a session.
  io.println("\n=== Creating ChatKit Session ===")

  let workflow = chatkit.new_workflow_param(workflow_id)
  let body = chatkit.new_create_chat_session_body(workflow, "example_user")

  let create_req = chatkit.session_create_request(cfg, body)
  let assert Ok(create_http_resp) = httpc.send(create_req)
  let assert Ok(session) = chatkit.session_create_response(create_http_resp)

  io.println("Created session:")
  io.println("  ID: " <> session.id)
  io.println("  Status: " <> status_to_string(session.status))
  io.println("  Expires at: " <> int.to_string(session.expires_at))
  io.println("  Client secret: " <> session.client_secret)
  io.println("  Workflow ID: " <> session.workflow.id)
  io.println("  User: " <> session.user)

  // 2. Cancel the session for cleanup.
  io.println("\n=== Cancelling Session ===")
  let cancel_req = chatkit.session_cancel_request(cfg, session.id)
  let assert Ok(cancel_http_resp) = httpc.send(cancel_req)
  let assert Ok(cancelled) = chatkit.session_cancel_response(cancel_http_resp)

  io.println("Cancelled session: " <> cancelled.id)
  io.println("  Status: " <> status_to_string(cancelled.status))
}

fn status_to_string(status: chatkit.ChatSessionStatus) -> String {
  case status {
    chatkit.SessionActive -> "active"
    chatkit.SessionExpired -> "expired"
    chatkit.SessionCancelled -> "cancelled"
  }
}
