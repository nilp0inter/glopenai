// Port of: examples/moderations/
//
// Classify text for potentially harmful content using the moderations API.
// Demonstrates both single-string and multi-string input.
//
// Run with: gleam run -m example/moderation

import example/env
import gleam/bool
import gleam/float
import gleam/io
import gleam/list
import gleam/httpc
import glopenai/config
import glopenai/moderation

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // Single input
  let request =
    moderation.new_create_request(
      input: moderation.StringInput("Lions want to kill"),
    )
    |> moderation.with_model("omni-moderation-latest")

  let http_request = moderation.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = moderation.create_response(http_response)

  io.println("--- Single input ---")
  print_results(response.results)

  // Multiple inputs
  let request =
    moderation.new_create_request(
      input: moderation.StringArrayInput([
        "Lions want to kill",
        "I hate them",
      ]),
    )
    |> moderation.with_model("omni-moderation-latest")

  let http_request = moderation.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = moderation.create_response(http_response)

  io.println("\n--- Multiple inputs ---")
  print_results(response.results)
}

fn print_results(results: List(moderation.ContentModerationResult)) -> Nil {
  list.each(results, fn(result) {
    io.println(
      "Flagged: " <> bool.to_string(result.flagged)
      <> " | Violence score: "
      <> float.to_string(result.category_scores.violence)
      <> " | Hate score: "
      <> float.to_string(result.category_scores.hate),
    )
  })
}
