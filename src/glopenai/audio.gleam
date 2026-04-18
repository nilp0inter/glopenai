/// Audio API: text-to-speech generation.
/// Transcription and translation endpoints require multipart uploads and are
/// deferred until multipart support is added.

import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/internal
import glopenai/internal/codec

// --- Types ---

/// Voice options for text-to-speech. Includes built-in voices and custom voice
/// references.
pub type Voice {
  Alloy
  Ash
  Ballad
  Coral
  Echo
  Fable
  Onyx
  Nova
  Sage
  Shimmer
  Verse
  Marin
  Cedar
  /// A custom voice referenced by its ID (e.g. "voice_1234").
  CustomVoice(id: String)
  OtherVoice(String)
}

/// Audio output format for speech synthesis.
pub type SpeechResponseFormat {
  Mp3
  Opus
  Aac
  Flac
  Pcm
  Wav
}

/// TTS model selection.
pub type SpeechModel {
  Tts1
  Tts1Hd
  Gpt4oMiniTts
  OtherSpeechModel(String)
}

/// Format for streaming audio output.
pub type StreamFormat {
  Sse
  Audio
}

/// Request to generate speech from text.
pub type CreateSpeechRequest {
  CreateSpeechRequest(
    input: String,
    model: SpeechModel,
    voice: Voice,
    instructions: Option(String),
    response_format: Option(SpeechResponseFormat),
    speed: Option(Float),
    stream_format: Option(StreamFormat),
  )
}

// --- Builder ---

/// Create a new speech request with the required fields.
pub fn new_create_speech_request(
  input input: String,
  model model: SpeechModel,
  voice voice: Voice,
) -> CreateSpeechRequest {
  CreateSpeechRequest(
    input: input,
    model: model,
    voice: voice,
    instructions: None,
    response_format: None,
    speed: None,
    stream_format: None,
  )
}

pub fn with_instructions(
  request: CreateSpeechRequest,
  instructions: String,
) -> CreateSpeechRequest {
  CreateSpeechRequest(..request, instructions: Some(instructions))
}

pub fn with_response_format(
  request: CreateSpeechRequest,
  format: SpeechResponseFormat,
) -> CreateSpeechRequest {
  CreateSpeechRequest(..request, response_format: Some(format))
}

pub fn with_speed(
  request: CreateSpeechRequest,
  speed: Float,
) -> CreateSpeechRequest {
  CreateSpeechRequest(..request, speed: Some(speed))
}

pub fn with_stream_format(
  request: CreateSpeechRequest,
  format: StreamFormat,
) -> CreateSpeechRequest {
  CreateSpeechRequest(..request, stream_format: Some(format))
}

// --- Encoders ---

pub fn voice_to_json(voice: Voice) -> json.Json {
  case voice {
    CustomVoice(id) -> json.object([#("id", json.string(id))])
    _ ->
      json.string(case voice {
        Alloy -> "alloy"
        Ash -> "ash"
        Ballad -> "ballad"
        Coral -> "coral"
        Echo -> "echo"
        Fable -> "fable"
        Onyx -> "onyx"
        Nova -> "nova"
        Sage -> "sage"
        Shimmer -> "shimmer"
        Verse -> "verse"
        Marin -> "marin"
        Cedar -> "cedar"
        OtherVoice(name) -> name
        // CustomVoice is handled above, this branch is unreachable
        CustomVoice(_) -> ""
      })
  }
}

pub fn speech_response_format_to_json(
  format: SpeechResponseFormat,
) -> json.Json {
  json.string(case format {
    Mp3 -> "mp3"
    Opus -> "opus"
    Aac -> "aac"
    Flac -> "flac"
    Pcm -> "pcm"
    Wav -> "wav"
  })
}

pub fn speech_model_to_json(model: SpeechModel) -> json.Json {
  json.string(case model {
    Tts1 -> "tts-1"
    Tts1Hd -> "tts-1-hd"
    Gpt4oMiniTts -> "gpt-4o-mini-tts"
    OtherSpeechModel(name) -> name
  })
}

pub fn stream_format_to_json(format: StreamFormat) -> json.Json {
  json.string(case format {
    Sse -> "sse"
    Audio -> "audio"
  })
}

pub fn create_speech_request_to_json(
  request: CreateSpeechRequest,
) -> json.Json {
  codec.object_with_optional(
    [
      #("input", json.string(request.input)),
      #("model", speech_model_to_json(request.model)),
      #("voice", voice_to_json(request.voice)),
    ],
    [
      codec.optional_field(
        "instructions",
        request.instructions,
        json.string,
      ),
      codec.optional_field(
        "response_format",
        request.response_format,
        speech_response_format_to_json,
      ),
      codec.optional_field("speed", request.speed, json.float),
      codec.optional_field(
        "stream_format",
        request.stream_format,
        stream_format_to_json,
      ),
    ],
  )
}

// --- Decoders ---

pub fn voice_decoder() -> decode.Decoder(Voice) {
  // A voice is either a string (built-in) or an object with an "id" field (custom)
  decode.one_of(
    {
      use value <- decode.then(decode.string)
      case value {
        "alloy" -> decode.success(Alloy)
        "ash" -> decode.success(Ash)
        "ballad" -> decode.success(Ballad)
        "coral" -> decode.success(Coral)
        "echo" -> decode.success(Echo)
        "fable" -> decode.success(Fable)
        "onyx" -> decode.success(Onyx)
        "nova" -> decode.success(Nova)
        "sage" -> decode.success(Sage)
        "shimmer" -> decode.success(Shimmer)
        "verse" -> decode.success(Verse)
        "marin" -> decode.success(Marin)
        "cedar" -> decode.success(Cedar)
        other -> decode.success(OtherVoice(other))
      }
    },
    [
      {
        use id <- decode.field("id", decode.string)
        decode.success(CustomVoice(id: id))
      },
    ],
  )
}

pub fn speech_response_format_decoder() -> decode.Decoder(
  SpeechResponseFormat,
) {
  use value <- decode.then(decode.string)
  case value {
    "mp3" -> decode.success(Mp3)
    "opus" -> decode.success(Opus)
    "aac" -> decode.success(Aac)
    "flac" -> decode.success(Flac)
    "pcm" -> decode.success(Pcm)
    "wav" -> decode.success(Wav)
    _ -> decode.failure(Mp3, "SpeechResponseFormat")
  }
}

pub fn speech_model_decoder() -> decode.Decoder(SpeechModel) {
  use value <- decode.then(decode.string)
  case value {
    "tts-1" -> decode.success(Tts1)
    "tts-1-hd" -> decode.success(Tts1Hd)
    "gpt-4o-mini-tts" -> decode.success(Gpt4oMiniTts)
    other -> decode.success(OtherSpeechModel(other))
  }
}

pub fn stream_format_decoder() -> decode.Decoder(StreamFormat) {
  use value <- decode.then(decode.string)
  case value {
    "sse" -> decode.success(Sse)
    "audio" -> decode.success(Audio)
    _ -> decode.failure(Sse, "StreamFormat")
  }
}

// --- Request/Response pairs (sans-io) ---

/// Build a request to generate speech audio from text.
/// The response body is raw audio bytes — the user's HTTP client should
/// return the body as a BitArray (not String) for binary audio data.
pub fn create_speech_request(
  config: Config,
  params: CreateSpeechRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/audio/speech",
    create_speech_request_to_json(params),
  )
}

/// The speech endpoint returns raw audio bytes, not JSON. The user should
/// read the response body directly from their HTTP client. This function
/// is provided only for checking error responses (non-2xx status codes).
pub fn create_speech_response(
  response: Response(String),
) -> Result(String, GlopenaiError) {
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
