import gleam/http
import gleam/http/response
import gleam/option.{None, Some}
import gleam/string
import glaoi/config
import glaoi/file

pub fn list_request_builds_test() {
  let cfg = config.new("test-key")
  let req = file.list_request(cfg)

  assert req.method == http.Get
  let assert True = string.contains(req.path, "/files")
}

pub fn list_response_decodes_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"id\":\"file-abc123\",\"object\":\"file\",\"bytes\":1024,\"created_at\":1700000000,\"filename\":\"data.jsonl\",\"purpose\":\"fine-tune\"}],\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = file.list_response(resp)
  assert result.object == "list"
  assert result.has_more == False
  assert result.first_id == None
  assert result.last_id == None
  let assert [f] = result.data
  assert f.id == "file-abc123"
  assert f.bytes == 1024
  assert f.filename == "data.jsonl"
  assert f.purpose == file.FineTune
  assert f.expires_at == None
}

pub fn list_response_with_pagination_test() {
  let body =
    "{\"object\":\"list\",\"data\":[],\"first_id\":\"file-first\",\"last_id\":\"file-last\",\"has_more\":true}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = file.list_response(resp)
  assert result.first_id == Some("file-first")
  assert result.last_id == Some("file-last")
  assert result.has_more == True
}

pub fn retrieve_request_builds_test() {
  let cfg = config.new("test-key")
  let req = file.retrieve_request(cfg, "file-abc123")

  assert req.method == http.Get
  let assert True = string.contains(req.path, "/files/file-abc123")
}

pub fn retrieve_response_decodes_test() {
  let body =
    "{\"id\":\"file-abc123\",\"object\":\"file\",\"bytes\":2048,\"created_at\":1700000000,\"expires_at\":1700100000,\"filename\":\"output.jsonl\",\"purpose\":\"batch_output\"}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(f) = file.retrieve_response(resp)
  assert f.id == "file-abc123"
  assert f.bytes == 2048
  assert f.expires_at == Some(1_700_100_000)
  assert f.purpose == file.BatchOutput
}

pub fn delete_request_builds_test() {
  let cfg = config.new("test-key")
  let req = file.delete_request(cfg, "file-abc123")

  assert req.method == http.Delete
  let assert True = string.contains(req.path, "/files/file-abc123")
}

pub fn delete_response_decodes_test() {
  let body =
    "{\"id\":\"file-abc123\",\"object\":\"file\",\"deleted\":true}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = file.delete_response(resp)
  assert result.id == "file-abc123"
  assert result.deleted == True
}

pub fn content_request_builds_test() {
  let cfg = config.new("test-key")
  let req = file.content_request(cfg, "file-abc123")

  assert req.method == http.Get
  let assert True =
    string.contains(req.path, "/files/file-abc123/content")
}

pub fn content_response_success_test() {
  let resp =
    response.new(200) |> response.set_body("line1\nline2\nline3")

  let assert Ok(body) = file.content_response(resp)
  assert body == "line1\nline2\nline3"
}

pub fn content_response_error_test() {
  let body =
    "{\"error\":{\"message\":\"File not found\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":null}}"
  let resp = response.new(404) |> response.set_body(body)

  let assert Error(_) = file.content_response(resp)
}
