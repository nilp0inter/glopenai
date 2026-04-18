// Port of: examples/audio-speech/
//
// Convert text to speech using the TTS API.
// The response body contains raw audio bytes which can be saved to a file.
//
// Run with: gleam run -m example/audio_speech

import example/env
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/httpc
import gleam/http/request
import glopenai/audio
import glopenai/config

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let params =
    audio.new_create_speech_request(
      input: "Today is a wonderful day to build something people love!",
      model: audio.Tts1,
      voice: audio.Alloy,
    )

  // Build the HTTP request (body is JSON String)
  let http_request = audio.create_speech_request(cfg, params)

  // The speech endpoint returns raw audio bytes, not JSON.
  // We need to use send_bits to avoid UTF-8 decoding errors.
  let bits_request =
    http_request
    |> request.map(bit_array.from_string)

  let assert Ok(http_response) = httpc.send_bits(bits_request)

  // Save the audio bytes to a file
  let path = "./data/audio.mp3"
  let assert Ok(Nil) = ensure_directory("./data/")
  let assert Ok(Nil) = write_file(path, http_response.body)

  io.println(
    "Audio saved to " <> path <> " ("
    <> int.to_string(bit_array.byte_size(http_response.body))
    <> " bytes)",
  )
}

@external(erlang, "example_file_ffi", "write_file")
fn write_file(path: String, content: BitArray) -> Result(Nil, err)

@external(erlang, "example_file_ffi", "ensure_directory")
fn ensure_directory(path: String) -> Result(Nil, err)
