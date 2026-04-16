import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/uri
import glaoi/config.{type AzureConfig, type Config}
import glaoi/error.{
  type GlaoiError, ApiResponseError, JsonDecodeError, UnexpectedResponse,
}

/// Build a POST request with a JSON body.
pub fn post_request(config: Config, path: String, body: json.Json) -> Request(String) {
  build_request(config, http.Post, path)
  |> request.set_body(json.to_string(body))
  |> request.prepend_header("content-type", "application/json")
}

/// Build a GET request.
pub fn get_request(config: Config, path: String) -> Request(String) {
  build_request(config, http.Get, path)
  |> request.set_body("")
}

/// Build a DELETE request.
pub fn delete_request(config: Config, path: String) -> Request(String) {
  build_request(config, http.Delete, path)
  |> request.set_body("")
}

/// Build a POST request for Azure OpenAI Service.
pub fn azure_post_request(
  config: AzureConfig,
  path: String,
  body: json.Json,
) -> Request(String) {
  build_azure_request(config, http.Post, path)
  |> request.set_body(json.to_string(body))
  |> request.prepend_header("content-type", "application/json")
}

/// Build a GET request for Azure OpenAI Service.
pub fn azure_get_request(config: AzureConfig, path: String) -> Request(String) {
  build_azure_request(config, http.Get, path)
  |> request.set_body("")
}

/// Build a DELETE request for Azure OpenAI Service.
pub fn azure_delete_request(
  config: AzureConfig,
  path: String,
) -> Request(String) {
  build_azure_request(config, http.Delete, path)
  |> request.set_body("")
}

// --- Multipart helpers ---

/// One part of a `multipart/form-data` body.
pub type MultipartPart {
  /// A regular form field. Encoded as text without an explicit content type.
  FieldPart(name: String, value: String)
  /// A file upload. `data` carries the raw bytes; `content_type` becomes the
  /// part's `Content-Type` header.
  FilePart(
    name: String,
    filename: String,
    content_type: String,
    data: BitArray,
  )
}

/// Build a `multipart/form-data` request. Returns `Request(BitArray)` because
/// file parts may carry arbitrary binary content.
///
/// `boundary` must not appear inside any part's body. Pick a long random string
/// or a deterministic hash. Sans-IO clients pass it explicitly so the request
/// is reproducible.
pub fn multipart_request(
  config: Config,
  method: http.Method,
  path: String,
  parts: List(MultipartPart),
  boundary: String,
) -> Request(BitArray) {
  let body = build_multipart_body(parts, boundary)
  build_request(config, method, path)
  |> request.set_body(body)
  |> request.prepend_header(
    "content-type",
    "multipart/form-data; boundary=" <> boundary,
  )
}

/// Encode a list of `MultipartPart`s into a single `BitArray` body using the
/// given boundary. Public for tests and for callers that need to handle the
/// body separately from the request envelope.
pub fn build_multipart_body(
  parts: List(MultipartPart),
  boundary: String,
) -> BitArray {
  let dash_boundary = bit_array.from_string("--" <> boundary <> "\r\n")
  let crlf = bit_array.from_string("\r\n")
  let parts_bytes =
    list.fold(parts, <<>>, fn(acc, part) {
      let header = bit_array.from_string(part_header(part))
      let payload = part_body(part)
      bit_array.concat([acc, dash_boundary, header, payload, crlf])
    })
  let closing =
    bit_array.from_string("--" <> boundary <> "--\r\n")
  bit_array.concat([parts_bytes, closing])
}

fn part_header(part: MultipartPart) -> String {
  case part {
    FieldPart(name, _) ->
      "Content-Disposition: form-data; name=\""
      <> name
      <> "\"\r\n\r\n"
    FilePart(name, filename, content_type, _) ->
      "Content-Disposition: form-data; name=\""
      <> name
      <> "\"; filename=\""
      <> filename
      <> "\"\r\nContent-Type: "
      <> content_type
      <> "\r\n\r\n"
  }
}

fn part_body(part: MultipartPart) -> BitArray {
  case part {
    FieldPart(_, value) -> bit_array.from_string(value)
    FilePart(_, _, _, data) -> data
  }
}

/// Parse an HTTP response, decoding the body as JSON on success (2xx)
/// or returning a GlaoiError on failure.
pub fn parse_response(
  response: Response(String),
  decoder: decode.Decoder(a),
) -> Result(a, GlaoiError) {
  case response.status >= 200 && response.status < 300 {
    True ->
      case json.parse(response.body, decoder) {
        Ok(value) -> Ok(value)
        Error(decode_error) ->
          Error(JsonDecodeError(response.body, decode_error))
      }
    False ->
      case json.parse(response.body, error.wrapped_error_decoder()) {
        Ok(api_error) ->
          Error(ApiResponseError(response.status, api_error))
        Error(_) ->
          Error(UnexpectedResponse(response.status, response.body))
      }
  }
}

// --- Private helpers ---

fn build_request(
  config: Config,
  method: http.Method,
  path: String,
) -> Request(String) {
  let full_url = config.api_base <> path
  let req = case uri.parse(full_url) {
    Ok(parsed) ->
      request.new()
      |> request.set_method(method)
      |> request.set_host(parsed.host |> option_unwrap("api.openai.com"))
      |> request.set_path(parsed.path)
      |> set_scheme(parsed.scheme)
      |> set_port(parsed)
    Error(Nil) ->
      request.new()
      |> request.set_method(method)
      |> request.set_host("api.openai.com")
      |> request.set_path("/v1" <> path)
  }
  apply_config(req, config)
}

fn build_azure_request(
  config: AzureConfig,
  method: http.Method,
  path: String,
) -> Request(String) {
  let full_url =
    config.api_base
    <> "/openai/deployments/"
    <> config.deployment_id
    <> path
  let req = case uri.parse(full_url) {
    Ok(parsed) ->
      request.new()
      |> request.set_method(method)
      |> request.set_host(parsed.host |> option_unwrap(""))
      |> request.set_path(parsed.path)
      |> set_scheme(parsed.scheme)
      |> set_port(parsed)
    Error(Nil) ->
      request.new()
      |> request.set_method(method)
      |> request.set_path(path)
  }
  req
  |> request.set_query([#("api-version", config.api_version)])
  |> request.prepend_header("api-key", config.api_key)
}

fn apply_config(req: Request(String), config: Config) -> Request(String) {
  let req =
    req
    |> request.prepend_header(
      "authorization",
      "Bearer " <> config.api_key,
    )
  let req = case config.org_id {
    Some(org_id) ->
      req |> request.prepend_header("openai-organization", org_id)
    None -> req
  }
  let req = case config.project_id {
    Some(project_id) ->
      req |> request.prepend_header("openai-project", project_id)
    None -> req
  }
  apply_custom_headers(req, config.custom_headers)
}

fn apply_custom_headers(
  req: Request(String),
  headers: List(#(String, String)),
) -> Request(String) {
  case headers {
    [] -> req
    [#(key, value), ..rest] ->
      apply_custom_headers(
        req |> request.prepend_header(key, value),
        rest,
      )
  }
}

fn set_scheme(
  req: Request(String),
  scheme: Option(String),
) -> Request(String) {
  case scheme {
    Some("https") -> request.set_scheme(req, http.Https)
    Some("http") -> request.set_scheme(req, http.Http)
    _ -> request.set_scheme(req, http.Https)
  }
}

fn set_port(req: Request(String), parsed: uri.Uri) -> Request(String) {
  case parsed.port {
    Some(port) -> request.set_port(req, port)
    None -> req
  }
}

fn option_unwrap(opt: Option(a), default: a) -> a {
  case opt {
    Some(v) -> v
    None -> default
  }
}
