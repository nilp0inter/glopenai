import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

/// Error returned by the OpenAI API in the response body.
pub type ApiError {
  ApiError(
    message: String,
    error_type: Option(String),
    param: Option(String),
    code: Option(String),
  )
}

/// Errors that can occur when using glaoi.
pub type GlaoiError {
  /// The API returned an error response (4xx/5xx with error body).
  ApiResponseError(status: Int, error: ApiError)
  /// The response body could not be decoded as JSON.
  JsonDecodeError(body: String, error: json.DecodeError)
  /// The response had an unexpected status code but no parseable error body.
  UnexpectedResponse(status: Int, body: String)
}

/// Decode an ApiError from JSON.
/// The OpenAI API wraps errors as `{"error": {...}}`.
pub fn api_error_decoder() -> decode.Decoder(ApiError) {
  use message <- decode.field("message", decode.string)
  use error_type <- decode.field("type", decode.optional(decode.string))
  use param <- decode.field("param", decode.optional(decode.string))
  use code <- decode.field("code", decode.optional(decode.string))
  decode.success(ApiError(
    message: message,
    error_type: error_type,
    param: param,
    code: code,
  ))
}

/// Decode the wrapped error envelope `{"error": ApiError}`.
pub fn wrapped_error_decoder() -> decode.Decoder(ApiError) {
  use error <- decode.field("error", api_error_decoder())
  decode.success(error)
}

/// Encode an ApiError to JSON.
pub fn api_error_to_json(error: ApiError) -> json.Json {
  json.object([
    #("message", json.string(error.message)),
    #("type", json.nullable(error.error_type, json.string)),
    #("param", json.nullable(error.param, json.string)),
    #("code", json.nullable(error.code, json.string)),
  ])
}
