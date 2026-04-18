/// Uploads API: stage a large file as an `Upload`, attach `Part` chunks to
/// it, then `complete` (or `cancel`) it. The completed upload yields an
/// `OpenAiFile` you can use with the rest of the platform.
///
/// Endpoints:
///
/// - `create_request`   — `POST /uploads`
/// - `add_part_request` — `POST /uploads/{id}/parts` (multipart)
/// - `complete_request` — `POST /uploads/{id}/complete`
/// - `cancel_request`   — `POST /uploads/{id}/cancel`
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/file.{
  type FileExpirationAfter, type OpenAiFile, file_expiration_after_to_json,
  openai_file_decoder,
}
import glopenai/internal
import glopenai/internal/codec

// =============================================================================
// Types
// =============================================================================

pub type UploadPurpose {
  UploadAssistants
  UploadVision
  UploadBatch
  UploadFineTune
}

pub fn upload_purpose_to_json(purpose: UploadPurpose) -> json.Json {
  json.string(case purpose {
    UploadAssistants -> "assistants"
    UploadVision -> "vision"
    UploadBatch -> "batch"
    UploadFineTune -> "fine-tune"
  })
}

pub fn upload_purpose_decoder() -> decode.Decoder(UploadPurpose) {
  use value <- decode.then(decode.string)
  case value {
    "assistants" -> decode.success(UploadAssistants)
    "vision" -> decode.success(UploadVision)
    "batch" -> decode.success(UploadBatch)
    "fine-tune" -> decode.success(UploadFineTune)
    _ -> decode.failure(UploadFineTune, "UploadPurpose")
  }
}

pub type UploadStatus {
  UploadPending
  UploadCompleted
  UploadCancelled
  UploadExpired
}

pub fn upload_status_decoder() -> decode.Decoder(UploadStatus) {
  use value <- decode.then(decode.string)
  case value {
    "pending" -> decode.success(UploadPending)
    "completed" -> decode.success(UploadCompleted)
    "cancelled" -> decode.success(UploadCancelled)
    "expired" -> decode.success(UploadExpired)
    _ -> decode.failure(UploadPending, "UploadStatus")
  }
}

pub type Upload {
  Upload(
    id: String,
    created_at: Int,
    filename: String,
    bytes: Int,
    purpose: UploadPurpose,
    status: UploadStatus,
    expires_at: Int,
    object: String,
    /// Set once the upload is completed and the underlying file is ready.
    file: Option(OpenAiFile),
  )
}

pub fn upload_decoder() -> decode.Decoder(Upload) {
  use id <- decode.field("id", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use filename <- decode.field("filename", decode.string)
  use bytes <- decode.field("bytes", decode.int)
  use purpose <- decode.field("purpose", upload_purpose_decoder())
  use status <- decode.field("status", upload_status_decoder())
  use expires_at <- decode.field("expires_at", decode.int)
  use object <- decode.field("object", decode.string)
  use file <- decode.optional_field(
    "file",
    None,
    decode.optional(openai_file_decoder()),
  )
  decode.success(Upload(
    id: id,
    created_at: created_at,
    filename: filename,
    bytes: bytes,
    purpose: purpose,
    status: status,
    expires_at: expires_at,
    object: object,
    file: file,
  ))
}

pub type UploadPart {
  UploadPart(id: String, created_at: Int, upload_id: String, object: String)
}

pub fn upload_part_decoder() -> decode.Decoder(UploadPart) {
  use id <- decode.field("id", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use upload_id <- decode.field("upload_id", decode.string)
  use object <- decode.field("object", decode.string)
  decode.success(UploadPart(
    id: id,
    created_at: created_at,
    upload_id: upload_id,
    object: object,
  ))
}

// --- CreateUploadRequest ---

pub type CreateUploadRequest {
  CreateUploadRequest(
    filename: String,
    purpose: UploadPurpose,
    bytes: Int,
    mime_type: String,
    expires_after: Option(FileExpirationAfter),
  )
}

pub fn new_create_request(
  filename: String,
  purpose: UploadPurpose,
  bytes: Int,
  mime_type: String,
) -> CreateUploadRequest {
  CreateUploadRequest(
    filename: filename,
    purpose: purpose,
    bytes: bytes,
    mime_type: mime_type,
    expires_after: None,
  )
}

pub fn with_expires_after(
  request: CreateUploadRequest,
  expires_after: FileExpirationAfter,
) -> CreateUploadRequest {
  CreateUploadRequest(..request, expires_after: Some(expires_after))
}

pub fn create_upload_request_to_json(request: CreateUploadRequest) -> json.Json {
  codec.object_with_optional(
    [
      #("filename", json.string(request.filename)),
      #("purpose", upload_purpose_to_json(request.purpose)),
      #("bytes", json.int(request.bytes)),
      #("mime_type", json.string(request.mime_type)),
    ],
    [
      codec.optional_field(
        "expires_after",
        request.expires_after,
        file_expiration_after_to_json,
      ),
    ],
  )
}

// --- CompleteUploadRequest ---

pub type CompleteUploadRequest {
  CompleteUploadRequest(part_ids: List(String), md5: Option(String))
}

pub fn new_complete_request(part_ids: List(String)) -> CompleteUploadRequest {
  CompleteUploadRequest(part_ids: part_ids, md5: None)
}

pub fn with_md5(
  request: CompleteUploadRequest,
  md5: String,
) -> CompleteUploadRequest {
  CompleteUploadRequest(..request, md5: Some(md5))
}

pub fn complete_upload_request_to_json(
  request: CompleteUploadRequest,
) -> json.Json {
  codec.object_with_optional(
    [#("part_ids", json.array(request.part_ids, json.string))],
    [codec.optional_field("md5", request.md5, json.string)],
  )
}

// =============================================================================
// Endpoints
// =============================================================================

pub fn create_request(
  config: Config,
  request: CreateUploadRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/uploads",
    create_upload_request_to_json(request),
  )
}

pub fn create_response(
  response: Response(String),
) -> Result(Upload, GlopenaiError) {
  internal.parse_response(response, upload_decoder())
}

/// Build the multipart `add part` request. `data` is the raw chunk bytes;
/// `boundary` must not appear in `data` (pick a long random string or hash).
pub fn add_part_request(
  config: Config,
  upload_id: String,
  data: BitArray,
  boundary: String,
) -> Request(BitArray) {
  internal.multipart_request(
    config,
    http.Post,
    "/uploads/" <> upload_id <> "/parts",
    [
      internal.FilePart(
        name: "data",
        filename: "part",
        content_type: "application/octet-stream",
        data: data,
      ),
    ],
    boundary,
  )
}

pub fn add_part_response(
  response: Response(String),
) -> Result(UploadPart, GlopenaiError) {
  internal.parse_response(response, upload_part_decoder())
}

pub fn complete_request(
  config: Config,
  upload_id: String,
  request: CompleteUploadRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/uploads/" <> upload_id <> "/complete",
    complete_upload_request_to_json(request),
  )
}

pub fn complete_response(
  response: Response(String),
) -> Result(Upload, GlopenaiError) {
  internal.parse_response(response, upload_decoder())
}

pub fn cancel_request(config: Config, upload_id: String) -> Request(String) {
  internal.post_request(
    config,
    "/uploads/" <> upload_id <> "/cancel",
    json.object([]),
  )
}

pub fn cancel_response(
  response: Response(String),
) -> Result(Upload, GlopenaiError) {
  internal.parse_response(response, upload_decoder())
}
