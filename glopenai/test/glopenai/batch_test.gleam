import gleam/http
import gleam/http/response
import gleam/json
import gleam/option.{Some}
import gleam/string
import glopenai/batch
import glopenai/config
import glopenai/error

pub fn request_encoding_test() {
  let request =
    batch.new_batch_request(
      input_file_id: "file-abc",
      endpoint: batch.V1ChatCompletions,
      completion_window: batch.W24H,
    )

  let encoded = batch.batch_request_to_json(request) |> json.to_string

  let assert True = string.contains(encoded, "\"input_file_id\":\"file-abc\"")
  let assert True = string.contains(encoded, "\"/v1/chat/completions\"")
  let assert True = string.contains(encoded, "\"24h\"")
}

pub fn request_building_test() {
  let cfg = config.new("test-key")
  let request =
    batch.new_batch_request(
      input_file_id: "file-abc",
      endpoint: batch.V1ChatCompletions,
      completion_window: batch.W24H,
    )
  let http_req = batch.create_request(cfg, request)

  assert http_req.method == http.Post
  let assert True = string.contains(http_req.path, "/batches")
}

pub fn retrieve_request_building_test() {
  let cfg = config.new("test-key")
  let http_req = batch.retrieve_request(cfg, "batch_abc")

  assert http_req.method == http.Get
  let assert True = string.contains(http_req.path, "/batches/batch_abc")
}

pub fn cancel_request_building_test() {
  let cfg = config.new("test-key")
  let http_req = batch.cancel_request(cfg, "batch_abc")

  assert http_req.method == http.Post
  let assert True = string.contains(http_req.path, "/batches/batch_abc/cancel")
}

pub fn batch_response_decoding_test() {
  let body =
    "{\"id\":\"batch_abc\",\"object\":\"batch\",\"endpoint\":\"/v1/chat/completions\",\"input_file_id\":\"file-abc\",\"completion_window\":\"24h\",\"status\":\"completed\",\"created_at\":1700000000}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = batch.create_response(resp)
  assert result.id == "batch_abc"
  assert result.object == "batch"
  assert result.status == batch.Completed
  assert result.created_at == 1_700_000_000
}

pub fn list_response_decoding_test() {
  let body =
    "{\"data\":[{\"id\":\"batch_1\",\"object\":\"batch\",\"endpoint\":\"/v1/chat/completions\",\"input_file_id\":\"file-1\",\"completion_window\":\"24h\",\"status\":\"in_progress\",\"created_at\":1700000000}],\"first_id\":\"batch_1\",\"last_id\":\"batch_1\",\"has_more\":false,\"object\":\"list\"}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = batch.list_response(resp)
  assert result.object == "list"
  assert result.has_more == False
  let assert [b] = result.data
  assert b.id == "batch_1"
  assert b.status == batch.InProgress
}

pub fn batch_with_errors_decoding_test() {
  let body =
    "{\"id\":\"batch_err\",\"object\":\"batch\",\"endpoint\":\"/v1/chat/completions\",\"input_file_id\":\"file-1\",\"completion_window\":\"24h\",\"status\":\"failed\",\"created_at\":1700000000,\"errors\":{\"object\":\"list\",\"data\":[{\"code\":\"invalid_request\",\"message\":\"Bad format\",\"param\":null,\"line\":5}]}}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = batch.create_response(resp)
  assert result.status == batch.Failed
  let assert Some(errors) = result.errors
  let assert [err] = errors.data
  assert err.code == "invalid_request"
  assert err.line == Some(5)
}

pub fn api_error_response_test() {
  let body =
    "{\"error\":{\"message\":\"Not found\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":\"not_found\"}}"
  let resp = response.new(404) |> response.set_body(body)

  let assert Error(error.ApiResponseError(status, _)) =
    batch.create_response(resp)
  assert status == 404
}

pub fn batch_request_input_decoding_test() {
  let body =
    "{\"custom_id\":\"req-1\",\"method\":\"POST\",\"url\":\"/v1/chat/completions\",\"body\":null}"
  let assert Ok(result) =
    json.parse(body, batch.batch_request_input_decoder())
  assert result.custom_id == "req-1"
  assert result.method == batch.Post
  assert result.url == batch.V1ChatCompletions
}

pub fn batch_request_output_decoding_test() {
  let body =
    "{\"id\":\"resp-1\",\"custom_id\":\"req-1\",\"response\":{\"status_code\":200,\"request_id\":\"req-abc\",\"body\":{\"choices\":[]}},\"error\":null}"
  let assert Ok(result) =
    json.parse(body, batch.batch_request_output_decoder())
  assert result.id == "resp-1"
  assert result.custom_id == "req-1"
  let assert Some(resp) = result.response
  assert resp.status_code == 200
}
