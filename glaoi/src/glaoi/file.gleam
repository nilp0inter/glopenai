/// Files API: upload, list, retrieve, delete, and download files.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import glaoi/config.{type Config}
import glaoi/error.{type GlaoiError}
import glaoi/internal

// --- Types ---

/// The purpose of an uploaded file as reported by the API.
pub type OpenAiFilePurpose {
  Assistants
  AssistantsOutput
  Batch
  BatchOutput
  FineTune
  FineTuneResults
  Vision
  UserData
}

/// An OpenAI file object.
pub type OpenAiFile {
  OpenAiFile(
    id: String,
    object: String,
    bytes: Int,
    created_at: Int,
    expires_at: Option(Int),
    filename: String,
    purpose: OpenAiFilePurpose,
  )
}

/// Anchor timestamp for `FileExpirationAfter`. Currently only `created_at`.
pub type FileExpirationAfterAnchor {
  CreatedAt
}

pub fn file_expiration_after_anchor_to_json(
  anchor: FileExpirationAfterAnchor,
) -> json.Json {
  json.string(case anchor {
    CreatedAt -> "created_at"
  })
}

pub fn file_expiration_after_anchor_decoder() -> decode.Decoder(
  FileExpirationAfterAnchor,
) {
  use value <- decode.then(decode.string)
  case value {
    "created_at" -> decode.success(CreatedAt)
    _ -> decode.failure(CreatedAt, "FileExpirationAfterAnchor")
  }
}

/// Expiration policy for an uploaded file.
pub type FileExpirationAfter {
  FileExpirationAfter(anchor: FileExpirationAfterAnchor, seconds: Int)
}

pub fn file_expiration_after_to_json(
  expiration: FileExpirationAfter,
) -> json.Json {
  json.object([
    #("anchor", file_expiration_after_anchor_to_json(expiration.anchor)),
    #("seconds", json.int(expiration.seconds)),
  ])
}

pub fn file_expiration_after_decoder() -> decode.Decoder(FileExpirationAfter) {
  use anchor <- decode.field("anchor", file_expiration_after_anchor_decoder())
  use seconds <- decode.field("seconds", decode.int)
  decode.success(FileExpirationAfter(anchor: anchor, seconds: seconds))
}

/// Response from listing files.
pub type ListFilesResponse {
  ListFilesResponse(
    object: String,
    data: List(OpenAiFile),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

/// Response from deleting a file.
pub type DeleteFileResponse {
  DeleteFileResponse(id: String, object: String, deleted: Bool)
}

// --- Encoders ---

pub fn openai_file_purpose_to_json(
  purpose: OpenAiFilePurpose,
) -> json.Json {
  json.string(case purpose {
    Assistants -> "assistants"
    AssistantsOutput -> "assistants_output"
    Batch -> "batch"
    BatchOutput -> "batch_output"
    FineTune -> "fine-tune"
    FineTuneResults -> "fine-tune-results"
    Vision -> "vision"
    UserData -> "user_data"
  })
}

pub fn openai_file_to_json(file: OpenAiFile) -> json.Json {
  json.object([
    #("id", json.string(file.id)),
    #("object", json.string(file.object)),
    #("bytes", json.int(file.bytes)),
    #("created_at", json.int(file.created_at)),
    #("expires_at", json.nullable(file.expires_at, json.int)),
    #("filename", json.string(file.filename)),
    #("purpose", openai_file_purpose_to_json(file.purpose)),
  ])
}

// --- Decoders ---

pub fn openai_file_purpose_decoder() -> decode.Decoder(OpenAiFilePurpose) {
  use value <- decode.then(decode.string)
  case value {
    "assistants" -> decode.success(Assistants)
    "assistants_output" -> decode.success(AssistantsOutput)
    "batch" -> decode.success(Batch)
    "batch_output" -> decode.success(BatchOutput)
    "fine-tune" -> decode.success(FineTune)
    "fine-tune-results" -> decode.success(FineTuneResults)
    "vision" -> decode.success(Vision)
    "user_data" -> decode.success(UserData)
    _ -> decode.failure(FineTune, "OpenAiFilePurpose")
  }
}

pub fn openai_file_decoder() -> decode.Decoder(OpenAiFile) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use bytes <- decode.field("bytes", decode.int)
  use created_at <- decode.field("created_at", decode.int)
  use expires_at <- decode.optional_field(
    "expires_at",
    None,
    decode.optional(decode.int),
  )
  use filename <- decode.field("filename", decode.string)
  use purpose <- decode.field("purpose", openai_file_purpose_decoder())
  decode.success(OpenAiFile(
    id: id,
    object: object,
    bytes: bytes,
    created_at: created_at,
    expires_at: expires_at,
    filename: filename,
    purpose: purpose,
  ))
}

fn list_files_response_decoder() -> decode.Decoder(ListFilesResponse) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field("data", decode.list(openai_file_decoder()))
  use first_id <- decode.optional_field(
    "first_id",
    None,
    decode.optional(decode.string),
  )
  use last_id <- decode.optional_field(
    "last_id",
    None,
    decode.optional(decode.string),
  )
  use has_more <- decode.field("has_more", decode.bool)
  decode.success(ListFilesResponse(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

fn delete_file_response_decoder() -> decode.Decoder(DeleteFileResponse) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeleteFileResponse(
    id: id,
    object: object,
    deleted: deleted,
  ))
}

// --- File upload ---

/// Parameters for uploading a file. The body is sent as `multipart/form-data`.
pub type CreateFileRequest {
  CreateFileRequest(
    /// Name attached to the multipart `file` part. Usually the original
    /// filename (e.g. `"data.jsonl"`).
    filename: String,
    /// Raw file bytes.
    file_bytes: BitArray,
    /// What the file will be used for.
    purpose: OpenAiFilePurpose,
    expires_after: Option(FileExpirationAfter),
  )
}

pub fn new_create_request(
  filename: String,
  file_bytes: BitArray,
  purpose: OpenAiFilePurpose,
) -> CreateFileRequest {
  CreateFileRequest(
    filename: filename,
    file_bytes: file_bytes,
    purpose: purpose,
    expires_after: None,
  )
}

pub fn with_expires_after(
  request: CreateFileRequest,
  expires_after: FileExpirationAfter,
) -> CreateFileRequest {
  CreateFileRequest(..request, expires_after: Some(expires_after))
}

/// Build a `POST /files` multipart request. The caller chooses `boundary`;
/// it must not appear inside `request.file_bytes`.
pub fn create_request(
  config: Config,
  request: CreateFileRequest,
  boundary: String,
) -> Request(BitArray) {
  // The OpenAI files endpoint expects three parts: file, purpose, and
  // optionally expires_after as a serialized JSON-ish form (anchor + seconds
  // are flattened to two fields per the multipart convention).
  let base_parts = [
    internal.FilePart(
      name: "file",
      filename: request.filename,
      content_type: guess_content_type(request.filename),
      data: request.file_bytes,
    ),
    internal.FieldPart(
      name: "purpose",
      value: openai_file_purpose_to_string(request.purpose),
    ),
  ]
  let parts = case request.expires_after {
    None -> base_parts
    Some(expires) -> [
      internal.FieldPart(
        name: "expires_after[anchor]",
        value: case expires.anchor {
          CreatedAt -> "created_at"
        },
      ),
      internal.FieldPart(
        name: "expires_after[seconds]",
        value: int.to_string(expires.seconds),
      ),
      ..base_parts
    ]
  }
  internal.multipart_request(config, http.Post, "/files", parts, boundary)
}

pub fn create_response(
  response: Response(String),
) -> Result(OpenAiFile, GlaoiError) {
  internal.parse_response(response, openai_file_decoder())
}

/// Best-effort `Content-Type` guess from the filename extension. The OpenAI
/// API does not strictly enforce this for files, but a sensible value avoids
/// confusing logs and proxies.
fn guess_content_type(filename: String) -> String {
  case bit_array.from_string(filename) {
    _ ->
      case ends_with(filename, ".pdf") {
        True -> "application/pdf"
        False ->
          case ends_with(filename, ".jsonl") {
            True -> "application/jsonl"
            False ->
              case ends_with(filename, ".json") {
                True -> "application/json"
                False ->
                  case ends_with(filename, ".txt") {
                    True -> "text/plain"
                    False -> "application/octet-stream"
                  }
              }
          }
      }
  }
}

fn ends_with(haystack: String, needle: String) -> Bool {
  let h = bit_array.from_string(haystack)
  let n = bit_array.from_string(needle)
  let h_size = bit_array.byte_size(h)
  let n_size = bit_array.byte_size(n)
  case h_size >= n_size {
    False -> False
    True ->
      case bit_array.slice(h, h_size - n_size, n_size) {
        Ok(suffix) -> suffix == n
        Error(_) -> False
      }
  }
}

fn openai_file_purpose_to_string(purpose: OpenAiFilePurpose) -> String {
  case purpose {
    Assistants -> "assistants"
    AssistantsOutput -> "assistants_output"
    Batch -> "batch"
    BatchOutput -> "batch_output"
    FineTune -> "fine-tune"
    FineTuneResults -> "fine-tune-results"
    Vision -> "vision"
    UserData -> "user_data"
  }
}

// --- Request/Response pairs (sans-io) ---

/// Build a request to list files.
pub fn list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/files")
}

/// Parse the response from listing files.
pub fn list_response(
  response: Response(String),
) -> Result(ListFilesResponse, GlaoiError) {
  internal.parse_response(response, list_files_response_decoder())
}

/// Build a request to retrieve metadata for a specific file.
pub fn retrieve_request(
  config: Config,
  file_id: String,
) -> Request(String) {
  internal.get_request(config, "/files/" <> file_id)
}

/// Parse the response from retrieving a file.
pub fn retrieve_response(
  response: Response(String),
) -> Result(OpenAiFile, GlaoiError) {
  internal.parse_response(response, openai_file_decoder())
}

/// Build a request to delete a file.
pub fn delete_request(
  config: Config,
  file_id: String,
) -> Request(String) {
  internal.delete_request(config, "/files/" <> file_id)
}

/// Parse the response from deleting a file.
pub fn delete_response(
  response: Response(String),
) -> Result(DeleteFileResponse, GlaoiError) {
  internal.parse_response(response, delete_file_response_decoder())
}

/// Build a request to download the content of a file.
/// The response body contains the raw file content.
pub fn content_request(
  config: Config,
  file_id: String,
) -> Request(String) {
  internal.get_request(config, "/files/" <> file_id <> "/content")
}

/// Parse the response from downloading file content.
/// Returns the raw body string on success.
pub fn content_response(
  response: Response(String),
) -> Result(String, GlaoiError) {
  case response.status >= 200 && response.status < 300 {
    True -> Ok(response.body)
    False ->
      case json.parse(response.body, error.wrapped_error_decoder()) {
        Ok(api_error) ->
          Error(error.ApiResponseError(response.status, api_error))
        Error(_) ->
          Error(error.UnexpectedResponse(response.status, response.body))
      }
  }
}
