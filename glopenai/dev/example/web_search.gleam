// Port of: examples/completions-web-search/
//
// Chat completion with web search enabled, using location context.
//
// Run with: gleam run -m example/web_search

import example/env
import gleam/io
import gleam/httpc
import gleam/option.{None, Some}
import glopenai/chat
import glopenai/config

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let request =
    chat.new_create_request(
      model: "gpt-4o-mini-search-preview",
      messages: [
        chat.user_message("What is the weather like today? Be concise."),
      ],
    )
    |> chat.with_max_completion_tokens(256)
    |> chat.with_web_search_options(chat.WebSearchOptions(
      search_context_size: Some(chat.WebSearchLow),
      user_location: Some(chat.WebSearchUserLocation(
        approximate: chat.WebSearchLocation(
          city: Some("Paris"),
          country: None,
          region: None,
          timezone: None,
        ),
      )),
    ))

  let http_request = chat.create_request(cfg, request)

  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = chat.create_response(http_response)

  case response.choices {
    [choice, ..] ->
      case choice.message.content {
        Some(content) -> io.println("Response: " <> content)
        _ -> io.println("(no content)")
      }
    [] -> io.println("(no choices)")
  }
}
