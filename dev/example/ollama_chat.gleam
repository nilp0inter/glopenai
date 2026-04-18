// Port of: examples/ollama-chat/
//
// Chat completion using Ollama's OpenAI-compatible endpoint.
//
// Run with: gleam run -m example/ollama_chat
//
// Requires Ollama running locally with a model pulled (e.g. llama3.2:1b).

import gleam/io
import gleam/string
import gleam/httpc
import gleam/option.{Some}
import glopenai/chat
import glopenai/config

pub fn main() -> Nil {
  // Ollama's default OpenAI-compatible endpoint
  let cfg =
    config.new(api_key: "ollama")
    |> config.with_api_base("http://localhost:11434/v1")

  let request =
    chat.new_create_request(model: "llama3.2:1b", messages: [
      chat.system_message("You are a helpful assistant."),
      chat.user_message("Who won the world series in 2020?"),
      chat.assistant_message(
        "The Los Angeles Dodgers won the World Series in 2020.",
      ),
      chat.user_message("Where was it played?"),
    ])
    |> chat.with_max_completion_tokens(512)

  let http_request = chat.create_request(cfg, request)

  io.println("Sending request to Ollama...")
  case httpc.send(http_request) {
    Ok(http_response) ->
      case chat.create_response(http_response) {
        Ok(response) -> {
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
        Error(err) -> {
          io.println("API error:")
          io.println(string.inspect(err))
          Nil
        }
      }
    Error(err) -> {
      io.println("HTTP error (is Ollama running?):")
      io.println(string.inspect(err))
      Nil
    }
  }
}
