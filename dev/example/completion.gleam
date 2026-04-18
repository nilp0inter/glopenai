// Port of: examples/completions/
//
// Legacy text completion with single and multiple prompts.
//
// Run with: gleam run -m example/completion

import example/env
import gleam/httpc
import gleam/io
import gleam/list
import glopenai/completion
import glopenai/config

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // single prompt
  let request =
    completion.new_create_request(
      model: "gpt-3.5-turbo-instruct",
      prompt: completion.PromptString("Tell me a joke about the universe"),
    )
    |> completion.with_max_tokens(40)

  let http_request = completion.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = completion.create_response(http_response)

  io.println("\nResponse (single):\n")
  list.each(response.choices, fn(choice) { io.println(choice.text) })

  // multiple prompts
  let request =
    completion.new_create_request(
      model: "gpt-3.5-turbo-instruct",
      prompt: completion.PromptStringArray([
        "How old is the human civilization?",
        "How old is the Earth?",
      ]),
    )
    |> completion.with_max_tokens(40)

  let http_request = completion.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = completion.create_response(http_response)

  io.println("\nResponse (multiple):\n")
  list.each(response.choices, fn(choice) { io.println(choice.text) })
}
