import gleam/http
import gleam/http/response
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import glopenai/config
import glopenai/image

pub fn create_request_encodes_test() {
  let params =
    image.new_create_request(prompt: "A cute cat")
    |> image.with_model(image.DallE3)
    |> image.with_n(2)
    |> image.with_size(image.Size1024x1024)
    |> image.with_quality(image.QualityHd)
    |> image.with_style(image.Natural)

  let encoded =
    image.create_image_request_to_json(params)
    |> json.to_string

  let assert True = string.contains(encoded, "\"prompt\":\"A cute cat\"")
  let assert True = string.contains(encoded, "\"model\":\"dall-e-3\"")
  let assert True = string.contains(encoded, "\"n\":2")
  let assert True = string.contains(encoded, "\"size\":\"1024x1024\"")
  let assert True = string.contains(encoded, "\"quality\":\"hd\"")
  let assert True = string.contains(encoded, "\"style\":\"natural\"")
}

pub fn create_request_minimal_test() {
  let params = image.new_create_request(prompt: "A dog")

  let encoded =
    image.create_image_request_to_json(params)
    |> json.to_string

  let assert True = string.contains(encoded, "\"prompt\":\"A dog\"")
  // Optional fields should be omitted
  let assert False = string.contains(encoded, "\"model\"")
  let assert False = string.contains(encoded, "\"n\"")
  let assert False = string.contains(encoded, "\"size\"")
}

pub fn create_request_builds_http_request_test() {
  let cfg = config.new("test-key")
  let params = image.new_create_request(prompt: "A cat")
  let req = image.create_request(cfg, params)

  assert req.method == http.Post
  let assert True = string.contains(req.path, "/images/generations")
}

pub fn create_response_decodes_url_test() {
  let body =
    "{\"created\":1234567890,\"data\":[{\"url\":\"https://example.com/image.png\",\"revised_prompt\":\"A very cute cat\"}]}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = image.create_response(resp)
  assert result.created == 1_234_567_890
  let assert [img] = result.data
  let assert image.ImageUrl(url, revised_prompt) = img
  assert url == "https://example.com/image.png"
  assert revised_prompt == Some("A very cute cat")
}

pub fn create_response_decodes_b64_test() {
  let body =
    "{\"created\":1234567890,\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = image.create_response(resp)
  let assert [img] = result.data
  let assert image.ImageB64Json(b64_json, revised_prompt) = img
  assert b64_json == "aGVsbG8="
  assert revised_prompt == None
}

pub fn create_response_decodes_with_usage_test() {
  let body =
    "{\"created\":1234567890,\"data\":[{\"url\":\"https://example.com/img.png\"}],\"usage\":{\"input_tokens\":10,\"output_tokens\":20,\"total_tokens\":30,\"input_tokens_details\":{\"text_tokens\":8,\"image_tokens\":2}}}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = image.create_response(resp)
  let assert Some(usage) = result.usage
  assert usage.input_tokens == 10
  assert usage.output_tokens == 20
  assert usage.total_tokens == 30
  assert usage.input_tokens_details.text_tokens == 8
  assert usage.input_tokens_details.image_tokens == 2
  assert usage.output_token_details == None
}

pub fn create_response_api_error_test() {
  let body =
    "{\"error\":{\"message\":\"Bad request\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":null}}"
  let resp = response.new(400) |> response.set_body(body)

  let assert Error(_) = image.create_response(resp)
}
