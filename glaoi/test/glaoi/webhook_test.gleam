import gleam/bit_array
import gleam/option.{None, Some}
import glaoi/webhook

// --- HMAC signature helpers used to build test fixtures ---

@external(erlang, "glaoi_webhook_ffi", "hmac_sha256")
fn hmac_sha256(key: BitArray, data: BitArray) -> BitArray

@external(erlang, "glaoi_webhook_ffi", "base64_encode")
fn base64_encode(bytes: BitArray) -> BitArray

fn b64_encode_string(input: String) -> String {
  let assert Ok(s) =
    bit_array.to_string(base64_encode(bit_array.from_string(input)))
  s
}

fn compute_signature(
  webhook_id: String,
  timestamp: String,
  body: String,
  secret_b64: String,
) -> String {
  let signed = webhook_id <> "." <> timestamp <> "." <> body
  let assert Ok(secret_bytes) =
    bit_array.to_string(base64_encode(bit_array.from_string("")))
    |> fn(_) {
      // decode the b64 secret back to raw bytes for HMAC
      base64_decode_or_panic(secret_b64)
    }
    |> Ok
  let mac = hmac_sha256(secret_bytes, bit_array.from_string(signed))
  let assert Ok(s) = bit_array.to_string(base64_encode(mac))
  s
}

@external(erlang, "glaoi_webhook_ffi", "base64_decode")
fn base64_decode_ffi(bytes: BitArray) -> Result(BitArray, Nil)

fn base64_decode_or_panic(input: String) -> BitArray {
  let assert Ok(bytes) = base64_decode_ffi(bit_array.from_string(input))
  bytes
}

// --- Tests ---

pub fn parse_event_batch_completed_test() {
  let body =
    "{\"type\":\"batch.completed\",\"created_at\":1700000000,\"id\":\"evt_1\",\"object\":\"event\",\"data\":{\"id\":\"batch_abc\"}}"

  let assert Ok(event) = webhook.parse_event(body)
  let assert webhook.BatchCompleted(t, id, obj, data) = event
  assert t == 1_700_000_000
  assert id == "evt_1"
  assert obj == Some("event")
  let webhook.WebhookBatchData(batch_id) = data
  assert batch_id == "batch_abc"
}

pub fn parse_event_response_failed_test() {
  let body =
    "{\"type\":\"response.failed\",\"created_at\":1700000001,\"id\":\"evt_2\",\"data\":{\"id\":\"resp_xyz\"}}"

  let assert Ok(event) = webhook.parse_event(body)
  let assert webhook.ResponseFailed(_, _, obj, data) = event
  assert obj == None
  let webhook.WebhookResponseData(rid) = data
  assert rid == "resp_xyz"
}

pub fn parse_event_realtime_call_test() {
  let body =
    "{\"type\":\"realtime.call.incoming\",\"created_at\":1700000002,\"id\":\"evt_3\",\"data\":{\"call_id\":\"call_1\",\"sip_headers\":[{\"name\":\"From\",\"value\":\"sip:a@b\"}]}}"

  let assert Ok(webhook.RealtimeCallIncoming(_, _, _, data)) =
    webhook.parse_event(body)
  let webhook.WebhookRealtimeCallData(call_id, headers) = data
  assert call_id == "call_1"
  let assert [webhook.SipHeader(name, value)] = headers
  assert name == "From"
  assert value == "sip:a@b"
}

pub fn parse_event_unknown_type_test() {
  let body =
    "{\"type\":\"not.a.real.type\",\"created_at\":1,\"id\":\"x\",\"data\":{\"id\":\"y\"}}"
  let assert Error(_) = webhook.parse_event(body)
}

pub fn event_type_round_trips_test() {
  let body =
    "{\"type\":\"fine_tuning.job.succeeded\",\"created_at\":1,\"id\":\"x\",\"data\":{\"id\":\"ft_1\"}}"
  let assert Ok(event) = webhook.parse_event(body)
  assert webhook.event_type(event) == "fine_tuning.job.succeeded"
  assert webhook.created_at(event) == 1
}

// --- Signature verification tests ---

pub fn verify_signature_valid_test() {
  let body = "{\"test\":\"data\"}"
  let timestamp = "1700000000"
  let webhook_id = "wh_test"
  let secret = b64_encode_string("test_secret")

  let signature = compute_signature(webhook_id, timestamp, body, secret)

  let assert Ok(Nil) =
    webhook.verify_signature(
      body: body,
      signature: signature,
      timestamp: timestamp,
      webhook_id: webhook_id,
      secret: secret,
      now: 1_700_000_010,
    )
}

pub fn verify_signature_with_whsec_prefix_test() {
  let body = "hello"
  let timestamp = "1700000000"
  let webhook_id = "wh_test"
  let secret_raw = b64_encode_string("another_secret")
  let prefixed = "whsec_" <> secret_raw

  let signature = compute_signature(webhook_id, timestamp, body, secret_raw)

  let assert Ok(Nil) =
    webhook.verify_signature(
      body: body,
      signature: signature,
      timestamp: timestamp,
      webhook_id: webhook_id,
      secret: prefixed,
      now: 1_700_000_010,
    )
}

pub fn verify_signature_with_v1_prefix_test() {
  let body = "{\"x\":1}"
  let timestamp = "1700000000"
  let webhook_id = "wh_test"
  let secret = b64_encode_string("s3cret")
  let raw_sig = compute_signature(webhook_id, timestamp, body, secret)
  let signature = "v1," <> raw_sig

  let assert Ok(Nil) =
    webhook.verify_signature(
      body: body,
      signature: signature,
      timestamp: timestamp,
      webhook_id: webhook_id,
      secret: secret,
      now: 1_700_000_010,
    )
}

pub fn verify_signature_invalid_test() {
  let assert Error(webhook.InvalidSignature) =
    webhook.verify_signature(
      body: "{\"x\":1}",
      signature: "definitely_not_valid",
      timestamp: "1700000000",
      webhook_id: "wh_test",
      secret: b64_encode_string("secret"),
      now: 1_700_000_010,
    )
}

pub fn verify_signature_too_old_test() {
  let assert Error(webhook.Invalid(msg)) =
    webhook.verify_signature(
      body: "{}",
      signature: "ignored",
      timestamp: "1000",
      webhook_id: "wh",
      secret: b64_encode_string("s"),
      now: 1_700_000_000,
    )
  let assert True = msg == "webhook timestamp is too old"
}

pub fn verify_signature_too_new_test() {
  let assert Error(webhook.Invalid(msg)) =
    webhook.verify_signature(
      body: "{}",
      signature: "ignored",
      timestamp: "2000000000",
      webhook_id: "wh",
      secret: b64_encode_string("s"),
      now: 1_000_000_000,
    )
  let assert True = msg == "webhook timestamp is too new"
}

pub fn verify_signature_invalid_timestamp_format_test() {
  let assert Error(webhook.Invalid(_)) =
    webhook.verify_signature(
      body: "{}",
      signature: "ignored",
      timestamp: "not_a_number",
      webhook_id: "wh",
      secret: b64_encode_string("s"),
      now: 1_000_000_000,
    )
}

pub fn build_event_decodes_after_verifying_test() {
  let body =
    "{\"type\":\"batch.cancelled\",\"created_at\":1700000000,\"id\":\"evt_5\",\"data\":{\"id\":\"batch_z\"}}"
  let timestamp = "1700000000"
  let webhook_id = "wh_test"
  let secret = b64_encode_string("secret")
  let signature = compute_signature(webhook_id, timestamp, body, secret)

  let assert Ok(webhook.BatchCancelled(_, _, _, data)) =
    webhook.build_event(
      body: body,
      signature: signature,
      timestamp: timestamp,
      webhook_id: webhook_id,
      secret: secret,
      now: 1_700_000_005,
    )
  let webhook.WebhookBatchData(bid) = data
  assert bid == "batch_z"
}

pub fn build_event_invalid_json_test() {
  let body = "{\"invalid_json"
  let timestamp = "1700000000"
  let webhook_id = "wh_test"
  let secret = b64_encode_string("secret")
  let signature = compute_signature(webhook_id, timestamp, body, secret)

  let assert Error(webhook.Deserialization(received_body, _)) =
    webhook.build_event(
      body: body,
      signature: signature,
      timestamp: timestamp,
      webhook_id: webhook_id,
      secret: secret,
      now: 1_700_000_005,
    )
  assert received_body == body
}
