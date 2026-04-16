import gleam/bit_array
import gleam/http
import gleam/http/response
import gleam/option.{None, Some}
import gleam/string
import glaoi/config
import glaoi/file
import glaoi/internal
import glaoi/upload

// --- Multipart helper ---

pub fn multipart_body_field_only_test() {
  let body =
    internal.build_multipart_body(
      [internal.FieldPart(name: "purpose", value: "fine-tune")],
      "BNDRY",
    )
  let assert Ok(text) = bit_array.to_string(body)
  let assert True = string.contains(text, "--BNDRY\r\n")
  let assert True = string.contains(text, "name=\"purpose\"")
  let assert True = string.contains(text, "\r\n\r\nfine-tune\r\n")
  // Trailing boundary marker.
  let assert True = string.contains(text, "--BNDRY--\r\n")
}

pub fn multipart_body_file_part_test() {
  let body =
    internal.build_multipart_body(
      [
        internal.FilePart(
          name: "data",
          filename: "chunk.bin",
          content_type: "application/octet-stream",
          data: <<1, 2, 3, 4>>,
        ),
      ],
      "BNDRY",
    )
  // Body is mostly text headers + binary payload.
  let prefix_text =
    "--BNDRY\r\nContent-Disposition: form-data; name=\"data\"; filename=\"chunk.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n"
  let prefix = bit_array.from_string(prefix_text)
  let payload = <<1, 2, 3, 4>>
  let suffix = bit_array.from_string("\r\n--BNDRY--\r\n")
  let expected = bit_array.concat([prefix, payload, suffix])
  assert body == expected
}

pub fn multipart_request_sets_headers_test() {
  let cfg = config.new("test-key")
  let req =
    internal.multipart_request(
      cfg,
      http.Post,
      "/test",
      [internal.FieldPart(name: "x", value: "1")],
      "BNDRY",
    )
  assert req.method == http.Post
  let assert True = string.contains(req.path, "/test")
  // content-type carries boundary
  let content_type = case
    req.headers
    |> contains_header("content-type")
  {
    Some(v) -> v
    None -> ""
  }
  assert content_type == "multipart/form-data; boundary=BNDRY"
  // authorization header is preserved from config
  let assert Some(_) =
    req.headers
    |> contains_header("authorization")
}

fn contains_header(
  headers: List(#(String, String)),
  name: String,
) -> option.Option(String) {
  case headers {
    [] -> None
    [#(k, v), ..rest] ->
      case k == name {
        True -> Some(v)
        False -> contains_header(rest, name)
      }
  }
}

// --- Upload endpoints ---

pub fn create_request_minimal_test() {
  let cfg = config.new("test-key")
  let req =
    upload.create_request(
      cfg,
      upload.new_create_request(
        "data.jsonl",
        upload.UploadFineTune,
        4096,
        "application/jsonl",
      ),
    )
  assert req.method == http.Post
  let assert True = string.contains(req.path, "/uploads")
  let assert True = string.contains(req.body, "\"filename\":\"data.jsonl\"")
  let assert True = string.contains(req.body, "\"purpose\":\"fine-tune\"")
  let assert True = string.contains(req.body, "\"bytes\":4096")
  let assert True =
    string.contains(req.body, "\"mime_type\":\"application/jsonl\"")
}

pub fn create_request_with_expires_after_test() {
  let cfg = config.new("test-key")
  let req =
    upload.create_request(
      cfg,
      upload.new_create_request(
        "data.bin",
        upload.UploadBatch,
        100,
        "application/octet-stream",
      )
        |> upload.with_expires_after(file.FileExpirationAfter(
          anchor: file.CreatedAt,
          seconds: 3600,
        )),
    )
  let assert True =
    string.contains(req.body, "\"expires_after\":")
  let assert True = string.contains(req.body, "\"anchor\":\"created_at\"")
  let assert True = string.contains(req.body, "\"seconds\":3600")
}

pub fn create_response_decodes_test() {
  let body =
    "{\"id\":\"upload_1\",\"created_at\":1700000000,\"filename\":\"data.bin\",\"bytes\":4096,\"purpose\":\"fine-tune\",\"status\":\"pending\",\"expires_at\":1700003600,\"object\":\"upload\"}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(up) = upload.create_response(resp)
  assert up.id == "upload_1"
  assert up.purpose == upload.UploadFineTune
  assert up.status == upload.UploadPending
  assert up.file == None
}

pub fn create_response_with_completed_file_test() {
  let body =
    "{\"id\":\"upload_1\",\"created_at\":1700000000,\"filename\":\"data.bin\",\"bytes\":4096,\"purpose\":\"fine-tune\",\"status\":\"completed\",\"expires_at\":1700003600,\"object\":\"upload\",\"file\":{\"id\":\"file_1\",\"object\":\"file\",\"bytes\":4096,\"created_at\":1700000010,\"filename\":\"data.bin\",\"purpose\":\"fine-tune\"}}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(up) = upload.create_response(resp)
  assert up.status == upload.UploadCompleted
  let assert Some(f) = up.file
  assert f.id == "file_1"
  assert f.purpose == file.FineTune
}

pub fn add_part_request_uses_multipart_test() {
  let cfg = config.new("test-key")
  let req =
    upload.add_part_request(cfg, "upload_1", <<99, 100>>, "BOUND123")
  assert req.method == http.Post
  let assert True =
    string.contains(req.path, "/uploads/upload_1/parts")
  // Body should include the boundary and our raw bytes.
  let assert Ok(text_prefix) =
    bit_array.to_string(
      bit_array.from_string(
        "--BOUND123\r\nContent-Disposition: form-data; name=\"data\"; filename=\"part\"\r\nContent-Type: application/octet-stream\r\n\r\n",
      ),
    )
  let assert Ok(body_text) = safe_to_string(req.body)
  let assert True = string.contains(body_text, text_prefix)
  let assert True = string.contains(body_text, "--BOUND123--\r\n")
}

fn safe_to_string(bits: BitArray) -> Result(String, Nil) {
  // Replace the binary payload bytes with text-safe placeholders so we can
  // check the surrounding multipart envelope. The two non-ASCII bytes 99, 100
  // are actually 'c' and 'd' so this works directly.
  bit_array.to_string(bits)
}

pub fn add_part_response_decodes_test() {
  let body =
    "{\"id\":\"part_1\",\"created_at\":1700000010,\"upload_id\":\"upload_1\",\"object\":\"upload.part\"}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(part) = upload.add_part_response(resp)
  assert part.id == "part_1"
  assert part.upload_id == "upload_1"
}

pub fn complete_request_builds_test() {
  let cfg = config.new("test-key")
  let req =
    upload.complete_request(
      cfg,
      "upload_1",
      upload.new_complete_request(["part_1", "part_2"])
        |> upload.with_md5("abc123"),
    )
  assert req.method == http.Post
  let assert True =
    string.contains(req.path, "/uploads/upload_1/complete")
  let assert True =
    string.contains(req.body, "\"part_ids\":[\"part_1\",\"part_2\"]")
  let assert True = string.contains(req.body, "\"md5\":\"abc123\"")
}

pub fn cancel_request_builds_test() {
  let cfg = config.new("test-key")
  let req = upload.cancel_request(cfg, "upload_1")
  assert req.method == http.Post
  let assert True =
    string.contains(req.path, "/uploads/upload_1/cancel")
  // Cancel POSTs an empty JSON object body.
  assert req.body == "{}"
}

pub fn cancel_response_decodes_test() {
  let body =
    "{\"id\":\"upload_1\",\"created_at\":1,\"filename\":\"x\",\"bytes\":1,\"purpose\":\"vision\",\"status\":\"cancelled\",\"expires_at\":2,\"object\":\"upload\"}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(up) = upload.cancel_response(resp)
  assert up.status == upload.UploadCancelled
}

pub fn create_response_api_error_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid mime\",\"type\":\"invalid_request_error\",\"param\":\"mime_type\",\"code\":null}}"
  let resp = response.new(400) |> response.set_body(body)
  let assert Error(_) = upload.create_response(resp)
}
