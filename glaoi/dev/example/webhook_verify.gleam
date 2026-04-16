// Inspired by: examples/webhooks/src/main.rs
//
// The Rust example runs an Axum HTTP server, configures ngrok, and waits
// for OpenAI to deliver real webhook events. That requires a public URL +
// dashboard configuration and is not runnable as a self-contained demo.
//
// This Gleam port instead exercises the **glaoi/webhook** API end-to-end
// without a server: it constructs a synthetic webhook payload, signs it
// with the same HMAC-SHA256 + base64 scheme that OpenAI uses, then
// verifies + decodes it. The pretty-printer that processes events is the
// part you would lift directly into a real handler behind your HTTP
// framework of choice (mist, wisp, ...).
//
// Run with: gleam run -m example/webhook_verify

import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import glaoi/webhook

pub fn main() -> Nil {
  io.println("=== glaoi webhook verify demo ===\n")

  // Pretend our deployment is registered with this secret. Real OpenAI
  // secrets ship as base64-encoded strings (optionally prefixed with
  // "whsec_"). We build the b64 form here so the round-trip exercises
  // both the secret-decoding and signature-verification paths.
  let raw_secret = "this_is_only_a_test"
  let secret_bytes = bit_array.from_string(raw_secret)
  let secret_b64 = base64_encode_to_string(secret_bytes)
  let secret_with_prefix = "whsec_" <> secret_b64

  // Three sample event bodies to exercise different decoder branches.
  let samples = [
    #(
      "response.completed",
      "{\"type\":\"response.completed\",\"created_at\":1700000000,\"id\":\"evt_response_1\",\"object\":\"event\",\"data\":{\"id\":\"resp_abc123\"}}",
    ),
    #(
      "batch.failed",
      "{\"type\":\"batch.failed\",\"created_at\":1700000005,\"id\":\"evt_batch_1\",\"object\":\"event\",\"data\":{\"id\":\"batch_def456\"}}",
    ),
    #(
      "realtime.call.incoming",
      "{\"type\":\"realtime.call.incoming\",\"created_at\":1700000010,\"id\":\"evt_call_1\",\"data\":{\"call_id\":\"call_xyz\",\"sip_headers\":[{\"name\":\"From\",\"value\":\"sip:alice@example.com\"}]}}",
    ),
  ]

  // Verifier and producer share the same clock. In production you'd use
  // `erlang:system_time(seconds)`.
  let now = 1_700_000_020
  let webhook_id = "evt_demo"

  list.each(samples, fn(sample) {
    let #(label, body) = sample
    io.println("--- " <> label <> " ---")

    // Sign the body the same way OpenAI does.
    let timestamp = "1700000000"
    let signature = sign_body(webhook_id, timestamp, body, secret_b64)
    // Standard Webhooks uses a versioned header value.
    let v1_signature = "v1," <> signature

    // 1. Verify (uses the prefixed form to also exercise stripping).
    case
      webhook.verify_signature(
        body: body,
        signature: v1_signature,
        timestamp: timestamp,
        webhook_id: webhook_id,
        secret: secret_with_prefix,
        now: now,
      )
    {
      Ok(Nil) -> io.println("  signature: OK")
      Error(err) -> io.println("  signature: FAIL — " <> verify_error(err))
    }

    // 2. Verify + decode in one step.
    case
      webhook.build_event(
        body: body,
        signature: v1_signature,
        timestamp: timestamp,
        webhook_id: webhook_id,
        secret: secret_with_prefix,
        now: now,
      )
    {
      Ok(event) -> describe_event(event)
      Error(err) -> io.println("  build_event failed: " <> verify_error(err))
    }
    io.println("")
  })

  // Show how negative paths look — bad signature and stale timestamp.
  io.println("--- negative cases ---")

  let any_body =
    "{\"type\":\"response.completed\",\"created_at\":1,\"id\":\"x\",\"data\":{\"id\":\"y\"}}"

  case
    webhook.verify_signature(
      body: any_body,
      signature: "definitely_not_valid",
      timestamp: "1700000000",
      webhook_id: webhook_id,
      secret: secret_with_prefix,
      now: now,
    )
  {
    Ok(Nil) -> io.println("  unexpected: bad signature accepted")
    Error(err) -> io.println("  bad signature → " <> verify_error(err))
  }

  case
    webhook.verify_signature(
      body: any_body,
      signature: "ignored",
      timestamp: "1000",
      webhook_id: webhook_id,
      secret: secret_with_prefix,
      now: now,
    )
  {
    Ok(Nil) -> io.println("  unexpected: stale timestamp accepted")
    Error(err) -> io.println("  stale timestamp → " <> verify_error(err))
  }
}

// --- Pretty-printers ---

fn describe_event(event: webhook.WebhookEvent) -> Nil {
  io.println(
    "  event_type: " <> webhook.event_type(event)
    <> ", created_at: " <> int.to_string(webhook.created_at(event)),
  )
  case event {
    webhook.BatchCancelled(_, _, _, d) -> io.println("  batch id: " <> d.id)
    webhook.BatchCompleted(_, _, _, d) -> io.println("  batch id: " <> d.id)
    webhook.BatchExpired(_, _, _, d) -> io.println("  batch id: " <> d.id)
    webhook.BatchFailed(_, _, _, d) -> io.println("  batch id: " <> d.id)
    webhook.EvalRunCanceled(_, _, _, d) -> io.println("  eval run id: " <> d.id)
    webhook.EvalRunFailed(_, _, _, d) -> io.println("  eval run id: " <> d.id)
    webhook.EvalRunSucceeded(_, _, _, d) ->
      io.println("  eval run id: " <> d.id)
    webhook.FineTuningJobCancelled(_, _, _, d) ->
      io.println("  ft job id: " <> d.id)
    webhook.FineTuningJobFailed(_, _, _, d) ->
      io.println("  ft job id: " <> d.id)
    webhook.FineTuningJobSucceeded(_, _, _, d) ->
      io.println("  ft job id: " <> d.id)
    webhook.RealtimeCallIncoming(_, _, _, d) -> {
      io.println("  call id: " <> d.call_id)
      list.each(d.sip_headers, fn(h) {
        io.println("    SIP " <> h.name <> ": " <> h.value)
      })
    }
    webhook.ResponseCancelled(_, _, _, d) ->
      io.println("  response id: " <> d.id)
    webhook.ResponseCompleted(_, _, _, d) ->
      io.println("  response id: " <> d.id)
    webhook.ResponseFailed(_, _, _, d) ->
      io.println("  response id: " <> d.id)
    webhook.ResponseIncomplete(_, _, _, d) ->
      io.println("  response id: " <> d.id)
  }
}

fn verify_error(err: webhook.WebhookError) -> String {
  case err {
    webhook.InvalidSignature -> "InvalidSignature"
    webhook.Invalid(message) -> "Invalid(" <> message <> ")"
    webhook.Deserialization(_, _) -> "Deserialization"
  }
}

// --- Local signing helper ---
//
// Mirrors the producer side of the Standard Webhooks scheme: the signing
// payload is `webhook_id "." timestamp "." body`, HMAC-SHA256-keyed by the
// raw secret bytes, base64-encoded.

fn sign_body(
  webhook_id: String,
  timestamp: String,
  body: String,
  secret_b64: String,
) -> String {
  let signed_payload =
    bit_array.from_string(webhook_id <> "." <> timestamp <> "." <> body)
  let secret_bytes = base64_decode_or_panic(secret_b64)
  let mac = hmac_sha256(secret_bytes, signed_payload)
  base64_encode_to_string(mac)
}

fn base64_encode_to_string(bytes: BitArray) -> String {
  case bit_array.to_string(base64_encode(bytes)) {
    Ok(s) -> s
    Error(_) -> ""
  }
}

fn base64_decode_or_panic(input: String) -> BitArray {
  let assert Ok(bytes) = base64_decode(bit_array.from_string(input))
  bytes
}

@external(erlang, "glaoi_webhook_ffi", "hmac_sha256")
fn hmac_sha256(key: BitArray, data: BitArray) -> BitArray

@external(erlang, "glaoi_webhook_ffi", "base64_encode")
fn base64_encode(bytes: BitArray) -> BitArray

@external(erlang, "glaoi_webhook_ffi", "base64_decode")
fn base64_decode(input: BitArray) -> Result(BitArray, Nil)
