// Port of: examples/embeddings/
//
// Create embeddings for multiple inputs and show their lengths.
//
// Run with: gleam run -m example/embedding

import example/env
import gleam/int
import gleam/io
import gleam/list
import gleam/httpc
import glaoi/config
import glaoi/embedding

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let request =
    embedding.new_create_request(
      model: "text-embedding-3-small",
      input: embedding.StringArrayInput([
        "Why do programmers hate nature? It has too many bugs.",
        "Why was the computer cold? It left its Windows open.",
      ]),
    )

  let http_request = embedding.create_request(cfg, request)

  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = embedding.create_response(http_response)

  list.each(response.data, fn(data) {
    io.println(
      "[" <> int.to_string(data.index) <> "]: has embedding of length "
      <> int.to_string(list.length(data.embedding)),
    )
  })
}
