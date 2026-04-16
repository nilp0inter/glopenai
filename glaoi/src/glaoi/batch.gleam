/// Batch API: create, retrieve, cancel, and list batch processing jobs.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glaoi/config.{type Config}
import glaoi/error.{type GlaoiError}
import glaoi/internal
import glaoi/internal/codec
import glaoi/shared.{type ResponseUsage}

// ============================================================================
// Enums
// ============================================================================

/// The API endpoint to use for all requests in the batch.
pub type BatchEndpoint {
  V1Responses
  V1ChatCompletions
  V1Embeddings
  V1Completions
  V1Moderations
}

/// The time frame within which the batch should be processed.
pub type BatchCompletionWindow {
  W24H
}

/// Anchor for file expiration timing.
pub type BatchFileExpirationAnchor {
  CreatedAt
}

/// Current processing status of a batch.
pub type BatchStatus {
  Validating
  Failed
  InProgress
  Finalizing
  Completed
  Expired
  Cancelling
  Cancelled
}

/// HTTP method for batch request inputs.
pub type BatchRequestInputMethod {
  Post
}

// ============================================================================
// Types
// ============================================================================

/// Configures when output files expire after creation.
pub type BatchFileExpirationAfter {
  BatchFileExpirationAfter(
    anchor: BatchFileExpirationAnchor,
    seconds: Int,
  )
}

/// Request to create a new batch.
pub type BatchRequest {
  BatchRequest(
    input_file_id: String,
    endpoint: BatchEndpoint,
    completion_window: BatchCompletionWindow,
    metadata: Option(dynamic.Dynamic),
    output_expires_after: Option(BatchFileExpirationAfter),
  )
}

/// Error information for individual batch items.
pub type BatchError {
  BatchError(
    code: String,
    message: String,
    param: Option(String),
    line: Option(Int),
  )
}

/// Container for batch errors.
pub type BatchErrors {
  BatchErrors(object: String, data: List(BatchError))
}

/// Counts of requests in different states within a batch.
pub type BatchRequestCounts {
  BatchRequestCounts(total: Int, completed: Int, failed: Int)
}

/// A batch processing job.
pub type Batch {
  Batch(
    id: String,
    object: String,
    endpoint: String,
    model: Option(String),
    errors: Option(BatchErrors),
    input_file_id: String,
    completion_window: String,
    status: BatchStatus,
    output_file_id: Option(String),
    error_file_id: Option(String),
    created_at: Int,
    in_progress_at: Option(Int),
    expires_at: Option(Int),
    finalizing_at: Option(Int),
    completed_at: Option(Int),
    failed_at: Option(Int),
    expired_at: Option(Int),
    cancelling_at: Option(Int),
    cancelled_at: Option(Int),
    request_counts: Option(BatchRequestCounts),
    usage: Option(ResponseUsage),
    metadata: Option(dynamic.Dynamic),
  )
}

/// Response from listing batches.
pub type ListBatchesResponse {
  ListBatchesResponse(
    data: List(Batch),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
    object: String,
  )
}

/// A single request line in a batch input file (JSONL).
pub type BatchRequestInput {
  BatchRequestInput(
    custom_id: String,
    method: BatchRequestInputMethod,
    url: BatchEndpoint,
    body: Option(dynamic.Dynamic),
  )
}

/// Response body within a batch output line.
pub type BatchRequestOutputResponse {
  BatchRequestOutputResponse(
    status_code: Int,
    request_id: String,
    body: dynamic.Dynamic,
  )
}

/// Error within a batch output line.
pub type BatchRequestOutputError {
  BatchRequestOutputError(code: String, message: String)
}

/// A single output line from a completed batch (JSONL).
pub type BatchRequestOutput {
  BatchRequestOutput(
    id: String,
    custom_id: String,
    response: Option(BatchRequestOutputResponse),
    error: Option(BatchRequestOutputError),
  )
}

// ============================================================================
// Request builder
// ============================================================================

/// Create a new batch request with required fields.
pub fn new_batch_request(
  input_file_id input_file_id: String,
  endpoint endpoint: BatchEndpoint,
  completion_window completion_window: BatchCompletionWindow,
) -> BatchRequest {
  BatchRequest(
    input_file_id: input_file_id,
    endpoint: endpoint,
    completion_window: completion_window,
    metadata: None,
    output_expires_after: None,
  )
}

pub fn with_metadata(
  request: BatchRequest,
  metadata: dynamic.Dynamic,
) -> BatchRequest {
  BatchRequest(..request, metadata: Some(metadata))
}

pub fn with_output_expires_after(
  request: BatchRequest,
  expiration: BatchFileExpirationAfter,
) -> BatchRequest {
  BatchRequest(..request, output_expires_after: Some(expiration))
}

// ============================================================================
// Encoders
// ============================================================================

pub fn batch_endpoint_to_json(endpoint: BatchEndpoint) -> json.Json {
  json.string(case endpoint {
    V1Responses -> "/v1/responses"
    V1ChatCompletions -> "/v1/chat/completions"
    V1Embeddings -> "/v1/embeddings"
    V1Completions -> "/v1/completions"
    V1Moderations -> "/v1/moderations"
  })
}

pub fn batch_completion_window_to_json(
  window: BatchCompletionWindow,
) -> json.Json {
  json.string(case window {
    W24H -> "24h"
  })
}

pub fn batch_status_to_json(status: BatchStatus) -> json.Json {
  json.string(case status {
    Validating -> "validating"
    Failed -> "failed"
    InProgress -> "in_progress"
    Finalizing -> "finalizing"
    Completed -> "completed"
    Expired -> "expired"
    Cancelling -> "cancelling"
    Cancelled -> "cancelled"
  })
}

pub fn batch_file_expiration_anchor_to_json(
  anchor: BatchFileExpirationAnchor,
) -> json.Json {
  json.string(case anchor {
    CreatedAt -> "created_at"
  })
}

pub fn batch_file_expiration_after_to_json(
  expiration: BatchFileExpirationAfter,
) -> json.Json {
  json.object([
    #("anchor", batch_file_expiration_anchor_to_json(expiration.anchor)),
    #("seconds", json.int(expiration.seconds)),
  ])
}

pub fn batch_request_input_method_to_json(
  method: BatchRequestInputMethod,
) -> json.Json {
  json.string(case method {
    Post -> "POST"
  })
}

pub fn batch_request_to_json(request: BatchRequest) -> json.Json {
  codec.object_with_optional(
    [
      #("input_file_id", json.string(request.input_file_id)),
      #("endpoint", batch_endpoint_to_json(request.endpoint)),
      #(
        "completion_window",
        batch_completion_window_to_json(request.completion_window),
      ),
    ],
    [
      codec.optional_field(
        "metadata",
        request.metadata,
        codec.dynamic_to_json,
      ),
      codec.optional_field(
        "output_expires_after",
        request.output_expires_after,
        batch_file_expiration_after_to_json,
      ),
    ],
  )
}

pub fn batch_request_input_to_json(input: BatchRequestInput) -> json.Json {
  codec.object_with_optional(
    [
      #("custom_id", json.string(input.custom_id)),
      #("method", batch_request_input_method_to_json(input.method)),
      #("url", batch_endpoint_to_json(input.url)),
    ],
    [codec.optional_field("body", input.body, codec.dynamic_to_json)],
  )
}

// ============================================================================
// Decoders
// ============================================================================

pub fn batch_endpoint_decoder() -> decode.Decoder(BatchEndpoint) {
  use value <- decode.then(decode.string)
  case value {
    "/v1/responses" -> decode.success(V1Responses)
    "/v1/chat/completions" -> decode.success(V1ChatCompletions)
    "/v1/embeddings" -> decode.success(V1Embeddings)
    "/v1/completions" -> decode.success(V1Completions)
    "/v1/moderations" -> decode.success(V1Moderations)
    _ -> decode.failure(V1Responses, "BatchEndpoint")
  }
}

pub fn batch_completion_window_decoder() -> decode.Decoder(
  BatchCompletionWindow,
) {
  use value <- decode.then(decode.string)
  case value {
    "24h" -> decode.success(W24H)
    _ -> decode.failure(W24H, "BatchCompletionWindow")
  }
}

pub fn batch_status_decoder() -> decode.Decoder(BatchStatus) {
  use value <- decode.then(decode.string)
  case value {
    "validating" -> decode.success(Validating)
    "failed" -> decode.success(Failed)
    "in_progress" -> decode.success(InProgress)
    "finalizing" -> decode.success(Finalizing)
    "completed" -> decode.success(Completed)
    "expired" -> decode.success(Expired)
    "cancelling" -> decode.success(Cancelling)
    "cancelled" -> decode.success(Cancelled)
    _ -> decode.failure(Validating, "BatchStatus")
  }
}

pub fn batch_file_expiration_anchor_decoder() -> decode.Decoder(
  BatchFileExpirationAnchor,
) {
  use value <- decode.then(decode.string)
  case value {
    "created_at" -> decode.success(CreatedAt)
    _ -> decode.failure(CreatedAt, "BatchFileExpirationAnchor")
  }
}

pub fn batch_error_decoder() -> decode.Decoder(BatchError) {
  use code <- decode.field("code", decode.string)
  use message <- decode.field("message", decode.string)
  use param <- decode.optional_field(
    "param",
    None,
    decode.optional(decode.string),
  )
  use line <- decode.optional_field(
    "line",
    None,
    decode.optional(decode.int),
  )
  decode.success(BatchError(
    code: code,
    message: message,
    param: param,
    line: line,
  ))
}

pub fn batch_errors_decoder() -> decode.Decoder(BatchErrors) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field("data", decode.list(batch_error_decoder()))
  decode.success(BatchErrors(object: object, data: data))
}

pub fn batch_request_counts_decoder() -> decode.Decoder(BatchRequestCounts) {
  use total <- decode.field("total", decode.int)
  use completed <- decode.field("completed", decode.int)
  use failed <- decode.field("failed", decode.int)
  decode.success(BatchRequestCounts(
    total: total,
    completed: completed,
    failed: failed,
  ))
}

pub fn batch_decoder() -> decode.Decoder(Batch) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use endpoint <- decode.field("endpoint", decode.string)
  use model <- decode.optional_field(
    "model",
    None,
    decode.optional(decode.string),
  )
  use errors <- decode.optional_field(
    "errors",
    None,
    decode.optional(batch_errors_decoder()),
  )
  use input_file_id <- decode.field("input_file_id", decode.string)
  use completion_window <- decode.field("completion_window", decode.string)
  use status <- decode.field("status", batch_status_decoder())
  use output_file_id <- decode.optional_field(
    "output_file_id",
    None,
    decode.optional(decode.string),
  )
  use error_file_id <- decode.optional_field(
    "error_file_id",
    None,
    decode.optional(decode.string),
  )
  use created_at <- decode.field("created_at", decode.int)
  use in_progress_at <- decode.optional_field(
    "in_progress_at",
    None,
    decode.optional(decode.int),
  )
  use expires_at <- decode.optional_field(
    "expires_at",
    None,
    decode.optional(decode.int),
  )
  use finalizing_at <- decode.optional_field(
    "finalizing_at",
    None,
    decode.optional(decode.int),
  )
  use completed_at <- decode.optional_field(
    "completed_at",
    None,
    decode.optional(decode.int),
  )
  use failed_at <- decode.optional_field(
    "failed_at",
    None,
    decode.optional(decode.int),
  )
  use expired_at <- decode.optional_field(
    "expired_at",
    None,
    decode.optional(decode.int),
  )
  use cancelling_at <- decode.optional_field(
    "cancelling_at",
    None,
    decode.optional(decode.int),
  )
  use cancelled_at <- decode.optional_field(
    "cancelled_at",
    None,
    decode.optional(decode.int),
  )
  use request_counts <- decode.optional_field(
    "request_counts",
    None,
    decode.optional(batch_request_counts_decoder()),
  )
  use usage <- decode.optional_field(
    "usage",
    None,
    decode.optional(shared.response_usage_decoder()),
  )
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(decode.dynamic),
  )
  decode.success(Batch(
    id: id,
    object: object,
    endpoint: endpoint,
    model: model,
    errors: errors,
    input_file_id: input_file_id,
    completion_window: completion_window,
    status: status,
    output_file_id: output_file_id,
    error_file_id: error_file_id,
    created_at: created_at,
    in_progress_at: in_progress_at,
    expires_at: expires_at,
    finalizing_at: finalizing_at,
    completed_at: completed_at,
    failed_at: failed_at,
    expired_at: expired_at,
    cancelling_at: cancelling_at,
    cancelled_at: cancelled_at,
    request_counts: request_counts,
    usage: usage,
    metadata: metadata,
  ))
}

fn list_batches_response_decoder() -> decode.Decoder(ListBatchesResponse) {
  use data <- decode.field("data", decode.list(batch_decoder()))
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
  use object <- decode.field("object", decode.string)
  decode.success(ListBatchesResponse(
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
    object: object,
  ))
}

pub fn batch_request_input_method_decoder() -> decode.Decoder(
  BatchRequestInputMethod,
) {
  use value <- decode.then(decode.string)
  case value {
    "POST" -> decode.success(Post)
    _ -> decode.failure(Post, "BatchRequestInputMethod")
  }
}

pub fn batch_request_input_decoder() -> decode.Decoder(BatchRequestInput) {
  use custom_id <- decode.field("custom_id", decode.string)
  use method <- decode.field("method", batch_request_input_method_decoder())
  use url <- decode.field("url", batch_endpoint_decoder())
  use body <- decode.optional_field(
    "body",
    None,
    decode.optional(decode.dynamic),
  )
  decode.success(BatchRequestInput(
    custom_id: custom_id,
    method: method,
    url: url,
    body: body,
  ))
}

pub fn batch_request_output_response_decoder() -> decode.Decoder(
  BatchRequestOutputResponse,
) {
  use status_code <- decode.field("status_code", decode.int)
  use request_id <- decode.field("request_id", decode.string)
  use body <- decode.field("body", decode.dynamic)
  decode.success(BatchRequestOutputResponse(
    status_code: status_code,
    request_id: request_id,
    body: body,
  ))
}

pub fn batch_request_output_error_decoder() -> decode.Decoder(
  BatchRequestOutputError,
) {
  use code <- decode.field("code", decode.string)
  use message <- decode.field("message", decode.string)
  decode.success(BatchRequestOutputError(code: code, message: message))
}

pub fn batch_request_output_decoder() -> decode.Decoder(BatchRequestOutput) {
  use id <- decode.field("id", decode.string)
  use custom_id <- decode.field("custom_id", decode.string)
  use response <- decode.optional_field(
    "response",
    None,
    decode.optional(batch_request_output_response_decoder()),
  )
  use error <- decode.optional_field(
    "error",
    None,
    decode.optional(batch_request_output_error_decoder()),
  )
  decode.success(BatchRequestOutput(
    id: id,
    custom_id: custom_id,
    response: response,
    error: error,
  ))
}

// ============================================================================
// Request/Response pairs (sans-io)
// ============================================================================

/// Build a request to create a new batch.
pub fn create_request(
  config: Config,
  params: BatchRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/batches",
    batch_request_to_json(params),
  )
}

/// Parse the response from creating a batch.
pub fn create_response(
  response: Response(String),
) -> Result(Batch, GlaoiError) {
  internal.parse_response(response, batch_decoder())
}

/// Build a request to list batches.
pub fn list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/batches")
}

/// Parse the response from listing batches.
pub fn list_response(
  response: Response(String),
) -> Result(ListBatchesResponse, GlaoiError) {
  internal.parse_response(response, list_batches_response_decoder())
}

/// Build a request to retrieve a specific batch.
pub fn retrieve_request(
  config: Config,
  batch_id: String,
) -> Request(String) {
  internal.get_request(config, "/batches/" <> batch_id)
}

/// Parse the response from retrieving a batch.
pub fn retrieve_response(
  response: Response(String),
) -> Result(Batch, GlaoiError) {
  internal.parse_response(response, batch_decoder())
}

/// Build a request to cancel a batch.
pub fn cancel_request(
  config: Config,
  batch_id: String,
) -> Request(String) {
  // Cancel is POST with empty body
  internal.post_request(
    config,
    "/batches/" <> batch_id <> "/cancel",
    json.object([]),
  )
}

/// Parse the response from cancelling a batch.
pub fn cancel_response(
  response: Response(String),
) -> Result(Batch, GlaoiError) {
  internal.parse_response(response, batch_decoder())
}
