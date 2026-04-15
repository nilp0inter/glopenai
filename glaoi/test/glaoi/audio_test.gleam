import gleam/http
import gleam/http/response
import gleam/json
import gleam/string
import glaoi/audio
import glaoi/config

pub fn create_speech_request_encodes_test() {
  let params =
    audio.new_create_speech_request(
      input: "Hello world",
      model: audio.Tts1,
      voice: audio.Alloy,
    )
    |> audio.with_response_format(audio.Mp3)
    |> audio.with_speed(1.5)

  let encoded =
    audio.create_speech_request_to_json(params)
    |> json.to_string

  let assert True = string.contains(encoded, "\"input\":\"Hello world\"")
  let assert True = string.contains(encoded, "\"model\":\"tts-1\"")
  let assert True = string.contains(encoded, "\"voice\":\"alloy\"")
  let assert True = string.contains(encoded, "\"response_format\":\"mp3\"")
  let assert True = string.contains(encoded, "\"speed\":1.5")
}

pub fn create_speech_request_minimal_test() {
  let params =
    audio.new_create_speech_request(
      input: "Test",
      model: audio.Gpt4oMiniTts,
      voice: audio.Nova,
    )

  let encoded =
    audio.create_speech_request_to_json(params)
    |> json.to_string

  let assert True = string.contains(encoded, "\"model\":\"gpt-4o-mini-tts\"")
  let assert True = string.contains(encoded, "\"voice\":\"nova\"")
  // Optional fields should be omitted
  let assert False = string.contains(encoded, "\"response_format\"")
  let assert False = string.contains(encoded, "\"speed\"")
}

pub fn create_speech_request_custom_voice_test() {
  let params =
    audio.new_create_speech_request(
      input: "Hello",
      model: audio.Tts1Hd,
      voice: audio.CustomVoice(id: "voice_abc123"),
    )

  let encoded =
    audio.create_speech_request_to_json(params)
    |> json.to_string

  let assert True = string.contains(encoded, "\"model\":\"tts-1-hd\"")
  // Custom voice should encode as an object with id field
  let assert True = string.contains(encoded, "\"id\":\"voice_abc123\"")
}

pub fn create_speech_request_builds_http_request_test() {
  let cfg = config.new("test-key")
  let params =
    audio.new_create_speech_request(
      input: "Hello",
      model: audio.Tts1,
      voice: audio.Alloy,
    )
  let req = audio.create_speech_request(cfg, params)

  assert req.method == http.Post
  let assert True = string.contains(req.path, "/audio/speech")
}

pub fn create_speech_response_success_test() {
  // Speech responses return raw audio bytes, not JSON
  let resp = response.new(200) |> response.set_body("raw-audio-bytes")

  let assert Ok(body) = audio.create_speech_response(resp)
  assert body == "raw-audio-bytes"
}

pub fn create_speech_response_error_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid voice\",\"type\":\"invalid_request_error\",\"param\":\"voice\",\"code\":null}}"
  let resp = response.new(400) |> response.set_body(body)

  let assert Error(_) = audio.create_speech_response(resp)
}
