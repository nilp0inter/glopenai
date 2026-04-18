/// Webhooks API: parse webhook event payloads and verify their signatures.
///
/// OpenAI uses the [Standard Webhooks](https://www.standardwebhooks.com/)
/// signing scheme. To verify a delivery, you need three headers and the raw
/// request body:
///
/// - `webhook-id`     — the unique ID of the webhook event
/// - `webhook-timestamp` — Unix seconds when the event was sent
/// - `webhook-signature` — base64 HMAC-SHA256 (optionally `v1,sig` formatted)
///
/// Plus the signing secret you registered (with or without the `whsec_` prefix).
///
/// `verify_signature` is sans-IO — it accepts a `now: Int` argument so you can
/// pass a clock you trust. The freshness window defaults to 300 seconds via
/// `verify_signature_with_tolerance`.
///
/// Once verified, decode the JSON body with `parse_event`.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string

// --- Errors ---

/// Errors returned by webhook verification or decoding.
pub type WebhookError {
  /// Signature did not match the computed HMAC.
  InvalidSignature
  /// Timestamp, secret, or other input was malformed.
  Invalid(message: String)
  /// Body could not be decoded as a `WebhookEvent`.
  Deserialization(body: String, error: json.DecodeError)
}

// --- Data payloads ---

/// Data payload for batch webhook events.
pub type WebhookBatchData {
  WebhookBatchData(id: String)
}

/// Data payload for eval run webhook events.
pub type WebhookEvalRunData {
  WebhookEvalRunData(id: String)
}

/// Data payload for fine-tuning job webhook events.
pub type WebhookFineTuningJobData {
  WebhookFineTuningJobData(id: String)
}

/// Data payload for response webhook events.
pub type WebhookResponseData {
  WebhookResponseData(id: String)
}

/// A header from a SIP Invite, included in realtime call events.
pub type SipHeader {
  SipHeader(name: String, value: String)
}

/// Data payload for realtime call webhook events.
pub type WebhookRealtimeCallData {
  WebhookRealtimeCallData(call_id: String, sip_headers: List(SipHeader))
}

// --- WebhookEvent ---

/// A webhook event delivered by OpenAI.
///
/// All variants share the common fields `created_at`, `id`, and `object`. The
/// `data` field carries the variant-specific payload.
pub type WebhookEvent {
  BatchCancelled(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookBatchData,
  )
  BatchCompleted(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookBatchData,
  )
  BatchExpired(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookBatchData,
  )
  BatchFailed(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookBatchData,
  )
  EvalRunCanceled(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookEvalRunData,
  )
  EvalRunFailed(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookEvalRunData,
  )
  EvalRunSucceeded(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookEvalRunData,
  )
  FineTuningJobCancelled(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookFineTuningJobData,
  )
  FineTuningJobFailed(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookFineTuningJobData,
  )
  FineTuningJobSucceeded(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookFineTuningJobData,
  )
  RealtimeCallIncoming(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookRealtimeCallData,
  )
  ResponseCancelled(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookResponseData,
  )
  ResponseCompleted(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookResponseData,
  )
  ResponseFailed(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookResponseData,
  )
  ResponseIncomplete(
    created_at: Int,
    id: String,
    object: Option(String),
    data: WebhookResponseData,
  )
}

// --- Decoders ---

fn batch_data_decoder() -> decode.Decoder(WebhookBatchData) {
  use id <- decode.field("id", decode.string)
  decode.success(WebhookBatchData(id: id))
}

fn eval_run_data_decoder() -> decode.Decoder(WebhookEvalRunData) {
  use id <- decode.field("id", decode.string)
  decode.success(WebhookEvalRunData(id: id))
}

fn fine_tuning_job_data_decoder() -> decode.Decoder(WebhookFineTuningJobData) {
  use id <- decode.field("id", decode.string)
  decode.success(WebhookFineTuningJobData(id: id))
}

fn response_data_decoder() -> decode.Decoder(WebhookResponseData) {
  use id <- decode.field("id", decode.string)
  decode.success(WebhookResponseData(id: id))
}

fn sip_header_decoder() -> decode.Decoder(SipHeader) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(SipHeader(name: name, value: value))
}

fn realtime_call_data_decoder() -> decode.Decoder(WebhookRealtimeCallData) {
  use call_id <- decode.field("call_id", decode.string)
  use sip_headers <- decode.field(
    "sip_headers",
    decode.list(sip_header_decoder()),
  )
  decode.success(WebhookRealtimeCallData(
    call_id: call_id,
    sip_headers: sip_headers,
  ))
}

/// Decode a `WebhookEvent` from JSON. The variant is chosen by the `type`
/// field on the envelope.
pub fn webhook_event_decoder() -> decode.Decoder(WebhookEvent) {
  use event_type <- decode.field("type", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use id <- decode.field("id", decode.string)
  use object <- decode.optional_field(
    "object",
    None,
    decode.optional(decode.string),
  )
  case event_type {
    "batch.cancelled" -> {
      use data <- decode.field("data", batch_data_decoder())
      decode.success(BatchCancelled(created_at, id, object, data))
    }
    "batch.completed" -> {
      use data <- decode.field("data", batch_data_decoder())
      decode.success(BatchCompleted(created_at, id, object, data))
    }
    "batch.expired" -> {
      use data <- decode.field("data", batch_data_decoder())
      decode.success(BatchExpired(created_at, id, object, data))
    }
    "batch.failed" -> {
      use data <- decode.field("data", batch_data_decoder())
      decode.success(BatchFailed(created_at, id, object, data))
    }
    "eval.run.canceled" -> {
      use data <- decode.field("data", eval_run_data_decoder())
      decode.success(EvalRunCanceled(created_at, id, object, data))
    }
    "eval.run.failed" -> {
      use data <- decode.field("data", eval_run_data_decoder())
      decode.success(EvalRunFailed(created_at, id, object, data))
    }
    "eval.run.succeeded" -> {
      use data <- decode.field("data", eval_run_data_decoder())
      decode.success(EvalRunSucceeded(created_at, id, object, data))
    }
    "fine_tuning.job.cancelled" -> {
      use data <- decode.field("data", fine_tuning_job_data_decoder())
      decode.success(FineTuningJobCancelled(created_at, id, object, data))
    }
    "fine_tuning.job.failed" -> {
      use data <- decode.field("data", fine_tuning_job_data_decoder())
      decode.success(FineTuningJobFailed(created_at, id, object, data))
    }
    "fine_tuning.job.succeeded" -> {
      use data <- decode.field("data", fine_tuning_job_data_decoder())
      decode.success(FineTuningJobSucceeded(created_at, id, object, data))
    }
    "realtime.call.incoming" -> {
      use data <- decode.field("data", realtime_call_data_decoder())
      decode.success(RealtimeCallIncoming(created_at, id, object, data))
    }
    "response.cancelled" -> {
      use data <- decode.field("data", response_data_decoder())
      decode.success(ResponseCancelled(created_at, id, object, data))
    }
    "response.completed" -> {
      use data <- decode.field("data", response_data_decoder())
      decode.success(ResponseCompleted(created_at, id, object, data))
    }
    "response.failed" -> {
      use data <- decode.field("data", response_data_decoder())
      decode.success(ResponseFailed(created_at, id, object, data))
    }
    "response.incomplete" -> {
      use data <- decode.field("data", response_data_decoder())
      decode.success(ResponseIncomplete(created_at, id, object, data))
    }
    other ->
      decode.failure(
        BatchCompleted(0, "", None, WebhookBatchData("")),
        "WebhookEvent: unknown type " <> other,
      )
  }
}

// --- Accessors ---

/// Return the `created_at` timestamp of any webhook event variant.
pub fn created_at(event: WebhookEvent) -> Int {
  case event {
    BatchCancelled(t, _, _, _) -> t
    BatchCompleted(t, _, _, _) -> t
    BatchExpired(t, _, _, _) -> t
    BatchFailed(t, _, _, _) -> t
    EvalRunCanceled(t, _, _, _) -> t
    EvalRunFailed(t, _, _, _) -> t
    EvalRunSucceeded(t, _, _, _) -> t
    FineTuningJobCancelled(t, _, _, _) -> t
    FineTuningJobFailed(t, _, _, _) -> t
    FineTuningJobSucceeded(t, _, _, _) -> t
    RealtimeCallIncoming(t, _, _, _) -> t
    ResponseCancelled(t, _, _, _) -> t
    ResponseCompleted(t, _, _, _) -> t
    ResponseFailed(t, _, _, _) -> t
    ResponseIncomplete(t, _, _, _) -> t
  }
}

/// Return the wire string for the event's `type` discriminator.
pub fn event_type(event: WebhookEvent) -> String {
  case event {
    BatchCancelled(_, _, _, _) -> "batch.cancelled"
    BatchCompleted(_, _, _, _) -> "batch.completed"
    BatchExpired(_, _, _, _) -> "batch.expired"
    BatchFailed(_, _, _, _) -> "batch.failed"
    EvalRunCanceled(_, _, _, _) -> "eval.run.canceled"
    EvalRunFailed(_, _, _, _) -> "eval.run.failed"
    EvalRunSucceeded(_, _, _, _) -> "eval.run.succeeded"
    FineTuningJobCancelled(_, _, _, _) -> "fine_tuning.job.cancelled"
    FineTuningJobFailed(_, _, _, _) -> "fine_tuning.job.failed"
    FineTuningJobSucceeded(_, _, _, _) -> "fine_tuning.job.succeeded"
    RealtimeCallIncoming(_, _, _, _) -> "realtime.call.incoming"
    ResponseCancelled(_, _, _, _) -> "response.cancelled"
    ResponseCompleted(_, _, _, _) -> "response.completed"
    ResponseFailed(_, _, _, _) -> "response.failed"
    ResponseIncomplete(_, _, _, _) -> "response.incomplete"
  }
}

// --- Parsing ---

/// Decode a webhook payload string into a `WebhookEvent`. Does NOT verify the
/// signature; use `verify_signature` first.
pub fn parse_event(body: String) -> Result(WebhookEvent, WebhookError) {
  case json.parse(body, webhook_event_decoder()) {
    Ok(event) -> Ok(event)
    Error(error) -> Error(Deserialization(body, error))
  }
}

// --- Signature verification ---

/// Default freshness tolerance window (seconds).
pub const default_tolerance_seconds: Int = 300

/// Verify a webhook signature using the default 300-second tolerance.
///
/// `now` is the current Unix timestamp in seconds. Pass a clock you trust;
/// this keeps verification sans-IO.
pub fn verify_signature(
  body body: String,
  signature signature: String,
  timestamp timestamp: String,
  webhook_id webhook_id: String,
  secret secret: String,
  now now: Int,
) -> Result(Nil, WebhookError) {
  verify_signature_with_tolerance(
    body,
    signature,
    timestamp,
    webhook_id,
    secret,
    now,
    default_tolerance_seconds,
  )
}

/// Verify a webhook signature with an explicit tolerance window in seconds.
pub fn verify_signature_with_tolerance(
  body body: String,
  signature signature: String,
  timestamp timestamp: String,
  webhook_id webhook_id: String,
  secret secret: String,
  now now: Int,
  tolerance_seconds tolerance_seconds: Int,
) -> Result(Nil, WebhookError) {
  use timestamp_seconds <- result.try(parse_timestamp(timestamp))

  case now - timestamp_seconds > tolerance_seconds {
    True -> Error(Invalid("webhook timestamp is too old"))
    False ->
      case timestamp_seconds > now + tolerance_seconds {
        True -> Error(Invalid("webhook timestamp is too new"))
        False -> {
          use secret_bytes <- result.try(decode_secret(secret))
          let signed_payload =
            webhook_id <> "." <> timestamp <> "." <> body
          let mac =
            hmac_sha256(secret_bytes, bit_array.from_string(signed_payload))
          let expected = base64_encode_binary(mac)
          let candidates = parse_signature_header(signature)
          case
            list.any(candidates, fn(sig) {
              constant_time_eq_string(sig, expected)
            })
          {
            True -> Ok(Nil)
            False -> Error(InvalidSignature)
          }
        }
      }
  }
}

/// Verify a signature and decode the body in one step.
pub fn build_event(
  body body: String,
  signature signature: String,
  timestamp timestamp: String,
  webhook_id webhook_id: String,
  secret secret: String,
  now now: Int,
) -> Result(WebhookEvent, WebhookError) {
  build_event_with_tolerance(
    body,
    signature,
    timestamp,
    webhook_id,
    secret,
    now,
    default_tolerance_seconds,
  )
}

/// Verify with explicit tolerance, then decode the body.
pub fn build_event_with_tolerance(
  body body: String,
  signature signature: String,
  timestamp timestamp: String,
  webhook_id webhook_id: String,
  secret secret: String,
  now now: Int,
  tolerance_seconds tolerance_seconds: Int,
) -> Result(WebhookEvent, WebhookError) {
  use _ <- result.try(verify_signature_with_tolerance(
    body,
    signature,
    timestamp,
    webhook_id,
    secret,
    now,
    tolerance_seconds,
  ))
  parse_event(body)
}

// --- Internal helpers ---

fn parse_timestamp(timestamp: String) -> Result(Int, WebhookError) {
  case int.parse(timestamp) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Invalid("invalid timestamp format"))
  }
}

fn decode_secret(secret: String) -> Result(BitArray, WebhookError) {
  // Standard Webhooks secrets may carry a "whsec_" prefix.
  let stripped = case string.starts_with(secret, "whsec_") {
    True -> string.drop_start(secret, 6)
    False -> secret
  }
  case base64_decode(bit_array.from_string(stripped)) {
    Ok(bytes) -> Ok(bytes)
    Error(_) -> Error(Invalid("failed to decode secret from base64"))
  }
}

/// Parse the value of the `webhook-signature` header. Two formats are
/// accepted:
///
/// - `"v1,base64sig v1,base64sig2"` — Standard Webhooks list of versioned
///   signatures separated by whitespace; we only honour `v1`.
/// - `"base64sig"` — a bare signature with no version tag.
fn parse_signature_header(signature: String) -> List(String) {
  case string.contains(signature, ",") {
    True ->
      signature
      |> string.split(" ")
      |> list.filter_map(fn(part) {
        case string.split(part, ",") {
          ["v1", sig] -> Ok(sig)
          _ -> Error(Nil)
        }
      })
    False -> [signature]
  }
}

/// Constant-time string comparison via byte-wise XOR. Avoids early exits that
/// could leak length information through timing.
fn constant_time_eq_string(a: String, b: String) -> Bool {
  let a_bits = bit_array.from_string(a)
  let b_bits = bit_array.from_string(b)
  case bit_array.byte_size(a_bits) == bit_array.byte_size(b_bits) {
    False -> False
    True -> constant_time_eq_bits(a_bits, b_bits, 0)
  }
}

fn constant_time_eq_bits(a: BitArray, b: BitArray, acc: Int) -> Bool {
  case a, b {
    <<x, rest_a:bits>>, <<y, rest_b:bits>> ->
      constant_time_eq_bits(
        rest_a,
        rest_b,
        int.bitwise_or(acc, int.bitwise_exclusive_or(x, y)),
      )
    _, _ -> acc == 0
  }
}

// --- FFI shims for HMAC + base64 ---

fn hmac_sha256(key: BitArray, data: BitArray) -> BitArray {
  hmac_sha256_ffi(key, data)
}

fn base64_encode_binary(bytes: BitArray) -> String {
  case bit_array.to_string(base64_encode_ffi(bytes)) {
    Ok(s) -> s
    // base64 output is always ASCII, so this branch is unreachable in practice.
    Error(_) -> ""
  }
}

fn base64_decode(input: BitArray) -> Result(BitArray, Nil) {
  base64_decode_ffi(input)
}

@external(erlang, "glopenai_webhook_ffi", "hmac_sha256")
fn hmac_sha256_ffi(key: BitArray, data: BitArray) -> BitArray

@external(erlang, "glopenai_webhook_ffi", "base64_encode")
fn base64_encode_ffi(bytes: BitArray) -> BitArray

@external(erlang, "glopenai_webhook_ffi", "base64_decode")
fn base64_decode_ffi(input: BitArray) -> Result(BitArray, Nil)
