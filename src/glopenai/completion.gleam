/// Legacy completions API: create text completions.
import gleam/dynamic
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/internal
import glopenai/internal/codec
import glopenai/shared.{type CompletionUsage}

// ============================================================================
// Enums
// ============================================================================

/// How the model stopped generating tokens.
pub type CompletionFinishReason {
  FinishReasonStop
  FinishReasonLength
  FinishReasonContentFilter
}

// ============================================================================
// Types
// ============================================================================

/// Prompt input: a single string, array of strings, array of token IDs, or
/// array of token ID arrays. Encoded as an untagged union.
pub type Prompt {
  PromptString(String)
  PromptStringArray(List(String))
  PromptIntegerArray(List(Int))
  PromptArrayOfIntegerArray(List(List(Int)))
}

/// Stop sequences: a single string or an array of up to 4 strings.
pub type StopConfiguration {
  StopString(String)
  StopStringArray(List(String))
}

/// Log probability information for generated tokens.
pub type Logprobs {
  Logprobs(
    tokens: List(String),
    token_logprobs: List(Option(Float)),
    top_logprobs: List(dynamic.Dynamic),
    text_offset: List(Int),
  )
}

/// A single completion choice returned by the API.
pub type CompletionChoice {
  CompletionChoice(
    text: String,
    index: Int,
    logprobs: Option(Logprobs),
    finish_reason: Option(CompletionFinishReason),
  )
}

/// Request to create a legacy text completion.
pub type CreateCompletionRequest {
  CreateCompletionRequest(
    model: String,
    prompt: Prompt,
    suffix: Option(String),
    max_tokens: Option(Int),
    temperature: Option(Float),
    top_p: Option(Float),
    n: Option(Int),
    stream: Option(Bool),
    logprobs: Option(Int),
    echo_prompt: Option(Bool),
    stop: Option(StopConfiguration),
    presence_penalty: Option(Float),
    frequency_penalty: Option(Float),
    best_of: Option(Int),
    logit_bias: Option(dynamic.Dynamic),
    user: Option(String),
    seed: Option(Int),
  )
}

/// Response from creating a legacy text completion.
pub type CreateCompletionResponse {
  CreateCompletionResponse(
    id: String,
    choices: List(CompletionChoice),
    created: Int,
    model: String,
    system_fingerprint: Option(String),
    object: String,
    usage: Option(CompletionUsage),
  )
}

// ============================================================================
// Request builder
// ============================================================================

/// Create a new completion request with required fields.
pub fn new_create_request(
  model model: String,
  prompt prompt: Prompt,
) -> CreateCompletionRequest {
  CreateCompletionRequest(
    model: model,
    prompt: prompt,
    suffix: None,
    max_tokens: None,
    temperature: None,
    top_p: None,
    n: None,
    stream: None,
    logprobs: None,
    echo_prompt: None,
    stop: None,
    presence_penalty: None,
    frequency_penalty: None,
    best_of: None,
    logit_bias: None,
    user: None,
    seed: None,
  )
}

pub fn with_suffix(
  request: CreateCompletionRequest,
  suffix: String,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, suffix: Some(suffix))
}

pub fn with_max_tokens(
  request: CreateCompletionRequest,
  max_tokens: Int,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, max_tokens: Some(max_tokens))
}

pub fn with_temperature(
  request: CreateCompletionRequest,
  temperature: Float,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, temperature: Some(temperature))
}

pub fn with_top_p(
  request: CreateCompletionRequest,
  top_p: Float,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, top_p: Some(top_p))
}

pub fn with_n(
  request: CreateCompletionRequest,
  n: Int,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, n: Some(n))
}

pub fn with_stream(
  request: CreateCompletionRequest,
  stream: Bool,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, stream: Some(stream))
}

pub fn with_logprobs(
  request: CreateCompletionRequest,
  logprobs: Int,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, logprobs: Some(logprobs))
}

pub fn with_echo_prompt(
  request: CreateCompletionRequest,
  echo_prompt: Bool,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, echo_prompt: Some(echo_prompt))
}

pub fn with_stop(
  request: CreateCompletionRequest,
  stop: StopConfiguration,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, stop: Some(stop))
}

pub fn with_presence_penalty(
  request: CreateCompletionRequest,
  presence_penalty: Float,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, presence_penalty: Some(presence_penalty))
}

pub fn with_frequency_penalty(
  request: CreateCompletionRequest,
  frequency_penalty: Float,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, frequency_penalty: Some(frequency_penalty))
}

pub fn with_best_of(
  request: CreateCompletionRequest,
  best_of: Int,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, best_of: Some(best_of))
}

pub fn with_user(
  request: CreateCompletionRequest,
  user: String,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, user: Some(user))
}

pub fn with_seed(
  request: CreateCompletionRequest,
  seed: Int,
) -> CreateCompletionRequest {
  CreateCompletionRequest(..request, seed: Some(seed))
}

// ============================================================================
// Encoders
// ============================================================================

pub fn completion_finish_reason_to_json(
  reason: CompletionFinishReason,
) -> json.Json {
  json.string(case reason {
    FinishReasonStop -> "stop"
    FinishReasonLength -> "length"
    FinishReasonContentFilter -> "content_filter"
  })
}

pub fn prompt_to_json(prompt: Prompt) -> json.Json {
  case prompt {
    PromptString(s) -> json.string(s)
    PromptStringArray(arr) -> json.array(arr, json.string)
    PromptIntegerArray(arr) -> json.array(arr, json.int)
    PromptArrayOfIntegerArray(arr) ->
      json.array(arr, fn(inner) { json.array(inner, json.int) })
  }
}

pub fn stop_configuration_to_json(stop: StopConfiguration) -> json.Json {
  case stop {
    StopString(s) -> json.string(s)
    StopStringArray(arr) -> json.array(arr, json.string)
  }
}

pub fn create_completion_request_to_json(
  request: CreateCompletionRequest,
) -> json.Json {
  codec.object_with_optional(
    [
      #("model", json.string(request.model)),
      #("prompt", prompt_to_json(request.prompt)),
    ],
    [
      codec.optional_field("suffix", request.suffix, json.string),
      codec.optional_field("max_tokens", request.max_tokens, json.int),
      codec.optional_field("temperature", request.temperature, json.float),
      codec.optional_field("top_p", request.top_p, json.float),
      codec.optional_field("n", request.n, json.int),
      codec.optional_field("stream", request.stream, json.bool),
      codec.optional_field("logprobs", request.logprobs, json.int),
      // Serialized as "echo" to match OpenAI API; field is named echo_prompt
      // because `echo` is a reserved keyword in Gleam.
      codec.optional_field("echo", request.echo_prompt, json.bool),
      codec.optional_field("stop", request.stop, stop_configuration_to_json),
      codec.optional_field(
        "presence_penalty",
        request.presence_penalty,
        json.float,
      ),
      codec.optional_field(
        "frequency_penalty",
        request.frequency_penalty,
        json.float,
      ),
      codec.optional_field("best_of", request.best_of, json.int),
      codec.optional_field(
        "logit_bias",
        request.logit_bias,
        codec.dynamic_to_json,
      ),
      codec.optional_field("user", request.user, json.string),
      codec.optional_field("seed", request.seed, json.int),
    ],
  )
}

// ============================================================================
// Decoders
// ============================================================================

pub fn completion_finish_reason_decoder() -> decode.Decoder(
  CompletionFinishReason,
) {
  use value <- decode.then(decode.string)
  case value {
    "stop" -> decode.success(FinishReasonStop)
    "length" -> decode.success(FinishReasonLength)
    "content_filter" -> decode.success(FinishReasonContentFilter)
    _ -> decode.failure(FinishReasonStop, "CompletionFinishReason")
  }
}

pub fn logprobs_decoder() -> decode.Decoder(Logprobs) {
  use tokens <- decode.field("tokens", decode.list(decode.string))
  use token_logprobs <- decode.field(
    "token_logprobs",
    decode.list(decode.optional(decode.float)),
  )
  use top_logprobs <- decode.field("top_logprobs", decode.list(decode.dynamic))
  use text_offset <- decode.field("text_offset", decode.list(decode.int))
  decode.success(Logprobs(
    tokens: tokens,
    token_logprobs: token_logprobs,
    top_logprobs: top_logprobs,
    text_offset: text_offset,
  ))
}

pub fn completion_choice_decoder() -> decode.Decoder(CompletionChoice) {
  use text <- decode.field("text", decode.string)
  use index <- decode.field("index", decode.int)
  use logprobs <- decode.optional_field(
    "logprobs",
    None,
    decode.optional(logprobs_decoder()),
  )
  use finish_reason <- decode.optional_field(
    "finish_reason",
    None,
    decode.optional(completion_finish_reason_decoder()),
  )
  decode.success(CompletionChoice(
    text: text,
    index: index,
    logprobs: logprobs,
    finish_reason: finish_reason,
  ))
}

fn create_completion_response_decoder() -> decode.Decoder(
  CreateCompletionResponse,
) {
  use id <- decode.field("id", decode.string)
  use choices <- decode.field(
    "choices",
    decode.list(completion_choice_decoder()),
  )
  use created <- decode.field("created", decode.int)
  use model <- decode.field("model", decode.string)
  use system_fingerprint <- decode.optional_field(
    "system_fingerprint",
    None,
    decode.optional(decode.string),
  )
  use object <- decode.field("object", decode.string)
  use usage <- decode.optional_field(
    "usage",
    None,
    decode.optional(shared.completion_usage_decoder()),
  )
  decode.success(CreateCompletionResponse(
    id: id,
    choices: choices,
    created: created,
    model: model,
    system_fingerprint: system_fingerprint,
    object: object,
    usage: usage,
  ))
}

// ============================================================================
// Request/Response pairs (sans-io)
// ============================================================================

/// Build a request to create a legacy text completion.
pub fn create_request(
  config: Config,
  params: CreateCompletionRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/completions",
    create_completion_request_to_json(params),
  )
}

/// Parse the response from creating a legacy text completion.
pub fn create_response(
  response: Response(String),
) -> Result(CreateCompletionResponse, GlopenaiError) {
  internal.parse_response(response, create_completion_response_decoder())
}
