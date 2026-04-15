/// Embeddings API: create embeddings for text input.

import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glaoi/config.{type Config}
import glaoi/error.{type GlaoiError}
import glaoi/internal
import glaoi/internal/codec

// --- Types ---

/// Input for embedding requests. Mirrors the Rust `EmbeddingInput` untagged enum.
pub type EmbeddingInput {
  StringInput(String)
  StringArrayInput(List(String))
  IntegerArrayInput(List(Int))
  ArrayOfIntegerArrayInput(List(List(Int)))
}

pub type EncodingFormat {
  Float
  Base64
}

/// Request to create embeddings.
pub type CreateEmbeddingRequest {
  CreateEmbeddingRequest(
    model: String,
    input: EmbeddingInput,
    encoding_format: Option(EncodingFormat),
    user: Option(String),
    dimensions: Option(Int),
  )
}

/// A single embedding vector returned by the API.
pub type Embedding {
  Embedding(index: Int, object: String, embedding: List(Float))
}

/// Usage statistics for an embedding request.
pub type EmbeddingUsage {
  EmbeddingUsage(prompt_tokens: Int, total_tokens: Int)
}

/// Response from creating embeddings.
pub type CreateEmbeddingResponse {
  CreateEmbeddingResponse(
    object: String,
    model: String,
    data: List(Embedding),
    usage: EmbeddingUsage,
  )
}

// --- Builder ---

/// Create a new embedding request with required fields and defaults.
pub fn new_create_request(
  model model: String,
  input input: EmbeddingInput,
) -> CreateEmbeddingRequest {
  CreateEmbeddingRequest(
    model: model,
    input: input,
    encoding_format: None,
    user: None,
    dimensions: None,
  )
}

/// Set the encoding format for the request.
pub fn with_encoding_format(
  request: CreateEmbeddingRequest,
  format: EncodingFormat,
) -> CreateEmbeddingRequest {
  CreateEmbeddingRequest(..request, encoding_format: Some(format))
}

/// Set the user identifier.
pub fn with_user(
  request: CreateEmbeddingRequest,
  user: String,
) -> CreateEmbeddingRequest {
  CreateEmbeddingRequest(..request, user: Some(user))
}

/// Set the output dimensions.
pub fn with_dimensions(
  request: CreateEmbeddingRequest,
  dimensions: Int,
) -> CreateEmbeddingRequest {
  CreateEmbeddingRequest(..request, dimensions: Some(dimensions))
}

// --- Encoders ---

pub fn encoding_format_to_json(format: EncodingFormat) -> json.Json {
  json.string(case format {
    Float -> "float"
    Base64 -> "base64"
  })
}

pub fn embedding_input_to_json(input: EmbeddingInput) -> json.Json {
  case input {
    StringInput(s) -> json.string(s)
    StringArrayInput(arr) -> json.array(arr, json.string)
    IntegerArrayInput(arr) -> json.array(arr, json.int)
    ArrayOfIntegerArrayInput(arr) ->
      json.array(arr, fn(inner) { json.array(inner, json.int) })
  }
}

pub fn create_embedding_request_to_json(
  request: CreateEmbeddingRequest,
) -> json.Json {
  codec.object_with_optional(
    [
      #("model", json.string(request.model)),
      #("input", embedding_input_to_json(request.input)),
    ],
    [
      codec.optional_field(
        "encoding_format",
        request.encoding_format,
        encoding_format_to_json,
      ),
      codec.optional_field("user", request.user, json.string),
      codec.optional_field("dimensions", request.dimensions, json.int),
    ],
  )
}

// --- Decoders ---

pub fn encoding_format_decoder() -> decode.Decoder(EncodingFormat) {
  use value <- decode.then(decode.string)
  case value {
    "float" -> decode.success(Float)
    "base64" -> decode.success(Base64)
    _ -> decode.failure(Float, "EncodingFormat")
  }
}

pub fn embedding_input_decoder() -> decode.Decoder(EmbeddingInput) {
  decode.one_of(decode.string |> decode.map(StringInput), [
    decode.list(decode.string) |> decode.map(StringArrayInput),
    decode.list(decode.list(decode.int))
      |> decode.map(ArrayOfIntegerArrayInput),
    decode.list(decode.int) |> decode.map(IntegerArrayInput),
  ])
}

pub fn embedding_decoder() -> decode.Decoder(Embedding) {
  use index <- decode.field("index", decode.int)
  use object <- decode.field("object", decode.string)
  use embedding <- decode.field("embedding", decode.list(decode.float))
  decode.success(Embedding(
    index: index,
    object: object,
    embedding: embedding,
  ))
}

pub fn embedding_usage_decoder() -> decode.Decoder(EmbeddingUsage) {
  use prompt_tokens <- decode.field("prompt_tokens", decode.int)
  use total_tokens <- decode.field("total_tokens", decode.int)
  decode.success(EmbeddingUsage(
    prompt_tokens: prompt_tokens,
    total_tokens: total_tokens,
  ))
}

fn create_embedding_response_decoder() -> decode.Decoder(
  CreateEmbeddingResponse,
) {
  use object <- decode.field("object", decode.string)
  use model <- decode.field("model", decode.string)
  use data <- decode.field("data", decode.list(embedding_decoder()))
  use usage <- decode.field("usage", embedding_usage_decoder())
  decode.success(CreateEmbeddingResponse(
    object: object,
    model: model,
    data: data,
    usage: usage,
  ))
}

// --- Request/Response pairs (sans-io) ---

/// Build a request to create embeddings.
pub fn create_request(
  config: Config,
  params: CreateEmbeddingRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/embeddings",
    create_embedding_request_to_json(params),
  )
}

/// Parse the response from creating embeddings.
pub fn create_response(
  response: Response(String),
) -> Result(CreateEmbeddingResponse, GlaoiError) {
  internal.parse_response(response, create_embedding_response_decoder())
}
