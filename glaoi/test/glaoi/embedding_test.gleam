import gleam/http/response
import gleam/json
import glaoi/embedding

pub fn create_request_encodes_test() {
  let params =
    embedding.new_create_request(
      model: "text-embedding-3-small",
      input: embedding.StringInput("Hello world"),
    )
    |> embedding.with_dimensions(256)

  let encoded =
    embedding.create_embedding_request_to_json(params)
    |> json.to_string

  // Verify key fields are present in the JSON
  let assert True = contains(encoded, "\"model\":\"text-embedding-3-small\"")
  let assert True = contains(encoded, "\"input\":\"Hello world\"")
  let assert True = contains(encoded, "\"dimensions\":256")
}

pub fn create_response_decodes_test() {
  let body =
    "{\"object\":\"list\",\"model\":\"text-embedding-3-small\",\"data\":[{\"index\":0,\"object\":\"embedding\",\"embedding\":[0.1,0.2,0.3]}],\"usage\":{\"prompt_tokens\":2,\"total_tokens\":2}}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = embedding.create_response(resp)
  assert result.object == "list"
  assert result.model == "text-embedding-3-small"
  let assert [emb] = result.data
  assert emb.index == 0
  assert emb.embedding == [0.1, 0.2, 0.3]
  assert result.usage.prompt_tokens == 2
  assert result.usage.total_tokens == 2
}

pub fn string_array_input_encodes_test() {
  let input = embedding.StringArrayInput(["Hello", "World"])
  let encoded = embedding.embedding_input_to_json(input) |> json.to_string
  assert encoded == "[\"Hello\",\"World\"]"
}

import gleam/string

fn contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
