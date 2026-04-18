// Port of: examples/responses-stream/
//
// Streaming responses from the Responses API. This example uses gleam_httpc
// which buffers the full response body — a real production setup would use a
// true streaming HTTP client (custom FFI or an SSE library). We demonstrate
// the sans-io parsing API (`parse_stream_event`) by splitting the buffered
// SSE body into individual events.
//
// Run with: gleam run -m example/response_stream

import example/env
import gleam/httpc
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glopenai/config
import glopenai/response as resp

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let request =
    resp.new_create_response(input: resp.InputText(
      "Write a haiku about programming.",
    ))
    |> resp.with_model("gpt-4.1")
    |> resp.with_stream(True)

  let http_request = resp.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)

  io.println("Streaming response:")
  io.println("")

  // Split the SSE body into events. Each event is terminated by a blank line,
  // and each line within an event looks like "data: <json>" or "event: <type>".
  let events = string.split(http_response.body, on: "\n\n")
  list.each(events, fn(event_text) {
    // Extract the `data: ...` line from the event block.
    let data = extract_data_line(event_text)
    case data {
      "" -> Nil
      _ ->
        case resp.parse_stream_event(data) {
          Ok(Some(event)) -> handle_event(event)
          Ok(None) -> io.println("\n[stream done]")
          Error(_) -> Nil
        }
    }
  })
}

/// Extract the content of a "data: ..." line from an SSE event block.
fn extract_data_line(event_text: String) -> String {
  let lines = string.split(event_text, on: "\n")
  case list.find(lines, fn(l) { string.starts_with(l, "data: ") }) {
    Ok(data_line) -> string.drop_start(data_line, 6)
    Error(Nil) -> ""
  }
}

/// Print the delta for text events; skip others.
fn handle_event(event: resp.ResponseStreamEvent) -> Nil {
  case event {
    resp.EventResponseOutputTextDelta(delta: delta, ..) -> io.print(delta)
    resp.EventResponseCompleted(..) -> io.println("\n\n[completed]")
    resp.EventResponseError(message: message, code: code, ..) -> {
      io.println("\nError: " <> message)
      case code {
        Some(c) -> io.println("Code: " <> c)
        None -> Nil
      }
    }
    _ -> Nil
  }
}
