// Port of: examples/chat/
//
// Basic chat completion with multi-turn conversation.
//
// Run with: gleam run -m example/chat

import example/env
import gleam/io
import gleam/httpc
import gleam/option.{Some}
import glopenai/chat
import glopenai/config

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let request =
    chat.new_create_request(model: "gpt-4o-mini", messages: [
      chat.system_message("You are a helpful assistant."),
      chat.user_message("Who won the world series in 2020?"),
      chat.assistant_message(
        "The Los Angeles Dodgers won the World Series in 2020.",
      ),
      chat.user_message("Where was it played?"),
    ])
    |> chat.with_max_completion_tokens(512)

  let http_request = chat.create_request(cfg, request)

  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = chat.create_response(http_response)

  io.println("\nResponse:\n")
  case response.choices {
    [choice, ..] ->
      case choice.message.content {
        Some(content) -> io.println(content)
        _ -> io.println("(no content)")
      }
    [] -> io.println("(no choices)")
  }
}
