import gleam/http
import gleam/http/request
import gleam/json
import gleam/option.{None, Some}
import glopenai/config
import glopenai/internal

pub fn new_config_test() {
  let cfg = config.new(api_key: "sk-test-123")
  assert cfg.api_base == "https://api.openai.com/v1"
  assert cfg.api_key == "sk-test-123"
  assert cfg.org_id == None
  assert cfg.project_id == None
  assert cfg.custom_headers == []
}

pub fn config_builder_test() {
  let cfg =
    config.new(api_key: "sk-test")
    |> config.with_api_base("https://custom.api.com/v1")
    |> config.with_org_id("org-123")
    |> config.with_project_id("proj-456")
    |> config.with_header("X-Custom", "value")

  assert cfg.api_base == "https://custom.api.com/v1"
  assert cfg.org_id == Some("org-123")
  assert cfg.project_id == Some("proj-456")
  assert cfg.custom_headers == [#("X-Custom", "value")]
}

pub fn get_request_builds_correctly_test() {
  let cfg = config.new(api_key: "sk-test")
  let req = internal.get_request(cfg, "/models")

  assert req.method == http.Get
  assert req.path == "/v1/models"
  assert req.body == ""
  let assert Ok(auth) = request.get_header(req, "authorization")
  assert auth == "Bearer sk-test"
}

pub fn post_request_builds_correctly_test() {
  let cfg =
    config.new(api_key: "sk-test")
    |> config.with_org_id("org-abc")
  let body = json.object([#("test", json.string("value"))])
  let req = internal.post_request(cfg, "/chat/completions", body)

  assert req.method == http.Post
  assert req.path == "/v1/chat/completions"
  let assert Ok(ct) = request.get_header(req, "content-type")
  assert ct == "application/json"
  let assert Ok(org) = request.get_header(req, "openai-organization")
  assert org == "org-abc"
}

pub fn delete_request_builds_correctly_test() {
  let cfg = config.new(api_key: "sk-test")
  let req = internal.delete_request(cfg, "/models/ft-123")
  assert req.method == http.Delete
  assert req.path == "/v1/models/ft-123"
}
