/// Shared types used across multiple API modules.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}
import glaoi/internal/codec

// --- ImageDetail ---

pub type ImageDetail {
  Auto
  Low
  High
  Original
}

pub fn image_detail_to_json(detail: ImageDetail) -> json.Json {
  json.string(case detail {
    Auto -> "auto"
    Low -> "low"
    High -> "high"
    Original -> "original"
  })
}

pub fn image_detail_decoder() -> decode.Decoder(ImageDetail) {
  use value <- decode.then(decode.string)
  case value {
    "auto" -> decode.success(Auto)
    "low" -> decode.success(Low)
    "high" -> decode.success(High)
    "original" -> decode.success(Original)
    _ -> decode.failure(Auto, "ImageDetail")
  }
}

// --- ImageUrl ---

pub type ImageUrl {
  ImageUrl(url: String, detail: Option(ImageDetail))
}

pub fn image_url_to_json(image_url: ImageUrl) -> json.Json {
  codec.object_with_optional(
    [#("url", json.string(image_url.url))],
    [codec.optional_field("detail", image_url.detail, image_detail_to_json)],
  )
}

pub fn image_url_decoder() -> decode.Decoder(ImageUrl) {
  use url <- decode.field("url", decode.string)
  use detail <- decode.optional_field(
    "detail",
    None,
    decode.optional(image_detail_decoder()),
  )
  decode.success(ImageUrl(url: url, detail: detail))
}

// --- FunctionObject ---

pub type FunctionObject {
  FunctionObject(
    name: String,
    description: Option(String),
    parameters: Option(dynamic.Dynamic),
    strict: Option(Bool),
  )
}

pub fn function_object_to_json(function: FunctionObject) -> json.Json {
  codec.object_with_optional(
    [#("name", json.string(function.name))],
    [
      codec.optional_field(
        "description",
        function.description,
        json.string,
      ),
      codec.optional_field(
        "parameters",
        function.parameters,
        codec.dynamic_to_json,
      ),
      codec.optional_field("strict", function.strict, json.bool),
    ],
  )
}

pub fn function_object_decoder() -> decode.Decoder(FunctionObject) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use parameters <- decode.optional_field(
    "parameters",
    None,
    decode.optional(decode.dynamic),
  )
  use strict <- decode.optional_field(
    "strict",
    None,
    decode.optional(decode.bool),
  )
  decode.success(FunctionObject(
    name: name,
    description: description,
    parameters: parameters,
    strict: strict,
  ))
}

// --- FunctionCall ---

pub type FunctionCall {
  FunctionCall(name: String, arguments: String)
}

pub fn function_call_to_json(call: FunctionCall) -> json.Json {
  json.object([
    #("name", json.string(call.name)),
    #("arguments", json.string(call.arguments)),
  ])
}

pub fn function_call_decoder() -> decode.Decoder(FunctionCall) {
  use name <- decode.field("name", decode.string)
  use arguments <- decode.field("arguments", decode.string)
  decode.success(FunctionCall(name: name, arguments: arguments))
}

// --- FunctionName ---

pub type FunctionName {
  FunctionName(name: String)
}

pub fn function_name_to_json(function_name: FunctionName) -> json.Json {
  json.object([#("name", json.string(function_name.name))])
}

pub fn function_name_decoder() -> decode.Decoder(FunctionName) {
  use name <- decode.field("name", decode.string)
  decode.success(FunctionName(name: name))
}

// --- ReasoningEffort ---

pub type ReasoningEffort {
  ReasoningNone
  ReasoningMinimal
  ReasoningLow
  ReasoningMedium
  ReasoningHigh
  ReasoningXhigh
}

pub fn reasoning_effort_to_json(effort: ReasoningEffort) -> json.Json {
  json.string(case effort {
    ReasoningNone -> "none"
    ReasoningMinimal -> "minimal"
    ReasoningLow -> "low"
    ReasoningMedium -> "medium"
    ReasoningHigh -> "high"
    ReasoningXhigh -> "xhigh"
  })
}

pub fn reasoning_effort_decoder() -> decode.Decoder(ReasoningEffort) {
  use value <- decode.then(decode.string)
  case value {
    "none" -> decode.success(ReasoningNone)
    "minimal" -> decode.success(ReasoningMinimal)
    "low" -> decode.success(ReasoningLow)
    "medium" -> decode.success(ReasoningMedium)
    "high" -> decode.success(ReasoningHigh)
    "xhigh" -> decode.success(ReasoningXhigh)
    _ -> decode.failure(ReasoningMedium, "ReasoningEffort")
  }
}

// --- ResponseFormat ---

pub type ResponseFormatJsonSchema {
  ResponseFormatJsonSchema(
    name: String,
    description: Option(String),
    schema: Option(dynamic.Dynamic),
    strict: Option(Bool),
  )
}

pub type ResponseFormat {
  ResponseFormatText
  ResponseFormatJsonObject
  ResponseFormatJsonSchemaVariant(json_schema: ResponseFormatJsonSchema)
}

pub fn response_format_to_json(format: ResponseFormat) -> json.Json {
  case format {
    ResponseFormatText -> json.object([#("type", json.string("text"))])
    ResponseFormatJsonObject ->
      json.object([#("type", json.string("json_object"))])
    ResponseFormatJsonSchemaVariant(schema) ->
      json.object([
        #("type", json.string("json_schema")),
        #("json_schema", response_format_json_schema_to_json(schema)),
      ])
  }
}

pub fn response_format_json_schema_to_json(
  schema: ResponseFormatJsonSchema,
) -> json.Json {
  codec.object_with_optional(
    [#("name", json.string(schema.name))],
    [
      codec.optional_field(
        "description",
        schema.description,
        json.string,
      ),
      codec.optional_field("strict", schema.strict, json.bool),
    ],
  )
}

pub fn response_format_decoder() -> decode.Decoder(ResponseFormat) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "text" -> decode.success(ResponseFormatText)
    "json_object" -> decode.success(ResponseFormatJsonObject)
    "json_schema" -> {
      use schema <- decode.field(
        "json_schema",
        response_format_json_schema_decoder(),
      )
      decode.success(ResponseFormatJsonSchemaVariant(json_schema: schema))
    }
    _ -> decode.failure(ResponseFormatText, "ResponseFormat")
  }
}

pub fn response_format_json_schema_decoder() -> decode.Decoder(
  ResponseFormatJsonSchema,
) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use schema <- decode.optional_field(
    "schema",
    None,
    decode.optional(decode.dynamic),
  )
  use strict <- decode.optional_field(
    "strict",
    None,
    decode.optional(decode.bool),
  )
  decode.success(ResponseFormatJsonSchema(
    name: name,
    description: description,
    schema: schema,
    strict: strict,
  ))
}

// --- CompletionUsage ---

pub type PromptTokensDetails {
  PromptTokensDetails(
    audio_tokens: Option(Int),
    cached_tokens: Option(Int),
  )
}

pub type CompletionTokensDetails {
  CompletionTokensDetails(
    accepted_prediction_tokens: Option(Int),
    audio_tokens: Option(Int),
    reasoning_tokens: Option(Int),
    rejected_prediction_tokens: Option(Int),
  )
}

pub type CompletionUsage {
  CompletionUsage(
    prompt_tokens: Int,
    completion_tokens: Int,
    total_tokens: Int,
    prompt_tokens_details: Option(PromptTokensDetails),
    completion_tokens_details: Option(CompletionTokensDetails),
  )
}

pub fn completion_usage_to_json(usage: CompletionUsage) -> json.Json {
  codec.object_with_optional(
    [
      #("prompt_tokens", json.int(usage.prompt_tokens)),
      #("completion_tokens", json.int(usage.completion_tokens)),
      #("total_tokens", json.int(usage.total_tokens)),
    ],
    [
      codec.optional_field(
        "prompt_tokens_details",
        usage.prompt_tokens_details,
        prompt_tokens_details_to_json,
      ),
      codec.optional_field(
        "completion_tokens_details",
        usage.completion_tokens_details,
        completion_tokens_details_to_json,
      ),
    ],
  )
}

pub fn prompt_tokens_details_to_json(
  details: PromptTokensDetails,
) -> json.Json {
  json.object([
    #("audio_tokens", json.nullable(details.audio_tokens, json.int)),
    #("cached_tokens", json.nullable(details.cached_tokens, json.int)),
  ])
}

pub fn completion_tokens_details_to_json(
  details: CompletionTokensDetails,
) -> json.Json {
  json.object([
    #(
      "accepted_prediction_tokens",
      json.nullable(details.accepted_prediction_tokens, json.int),
    ),
    #("audio_tokens", json.nullable(details.audio_tokens, json.int)),
    #(
      "reasoning_tokens",
      json.nullable(details.reasoning_tokens, json.int),
    ),
    #(
      "rejected_prediction_tokens",
      json.nullable(details.rejected_prediction_tokens, json.int),
    ),
  ])
}

pub fn completion_usage_decoder() -> decode.Decoder(CompletionUsage) {
  use prompt_tokens <- decode.field("prompt_tokens", decode.int)
  use completion_tokens <- decode.field("completion_tokens", decode.int)
  use total_tokens <- decode.field("total_tokens", decode.int)
  use prompt_tokens_details <- decode.optional_field(
    "prompt_tokens_details",
    None,
    decode.optional(prompt_tokens_details_decoder()),
  )
  use completion_tokens_details <- decode.optional_field(
    "completion_tokens_details",
    None,
    decode.optional(completion_tokens_details_decoder()),
  )
  decode.success(CompletionUsage(
    prompt_tokens: prompt_tokens,
    completion_tokens: completion_tokens,
    total_tokens: total_tokens,
    prompt_tokens_details: prompt_tokens_details,
    completion_tokens_details: completion_tokens_details,
  ))
}

pub fn prompt_tokens_details_decoder() -> decode.Decoder(PromptTokensDetails) {
  use audio_tokens <- decode.optional_field(
    "audio_tokens",
    None,
    decode.optional(decode.int),
  )
  use cached_tokens <- decode.optional_field(
    "cached_tokens",
    None,
    decode.optional(decode.int),
  )
  decode.success(PromptTokensDetails(
    audio_tokens: audio_tokens,
    cached_tokens: cached_tokens,
  ))
}

pub fn completion_tokens_details_decoder() -> decode.Decoder(
  CompletionTokensDetails,
) {
  use accepted_prediction_tokens <- decode.optional_field(
    "accepted_prediction_tokens",
    None,
    decode.optional(decode.int),
  )
  use audio_tokens <- decode.optional_field(
    "audio_tokens",
    None,
    decode.optional(decode.int),
  )
  use reasoning_tokens <- decode.optional_field(
    "reasoning_tokens",
    None,
    decode.optional(decode.int),
  )
  use rejected_prediction_tokens <- decode.optional_field(
    "rejected_prediction_tokens",
    None,
    decode.optional(decode.int),
  )
  decode.success(CompletionTokensDetails(
    accepted_prediction_tokens: accepted_prediction_tokens,
    audio_tokens: audio_tokens,
    reasoning_tokens: reasoning_tokens,
    rejected_prediction_tokens: rejected_prediction_tokens,
  ))
}

// --- ResponseUsage (used by Responses API) ---

pub type InputTokenDetails {
  InputTokenDetails(cached_tokens: Int)
}

pub type OutputTokenDetails {
  OutputTokenDetails(reasoning_tokens: Int)
}

pub type ResponseUsage {
  ResponseUsage(
    input_tokens: Int,
    input_tokens_details: InputTokenDetails,
    output_tokens: Int,
    output_tokens_details: OutputTokenDetails,
    total_tokens: Int,
  )
}

pub fn response_usage_to_json(usage: ResponseUsage) -> json.Json {
  json.object([
    #("input_tokens", json.int(usage.input_tokens)),
    #(
      "input_tokens_details",
      json.object([
        #("cached_tokens", json.int(usage.input_tokens_details.cached_tokens)),
      ]),
    ),
    #("output_tokens", json.int(usage.output_tokens)),
    #(
      "output_tokens_details",
      json.object([
        #(
          "reasoning_tokens",
          json.int(usage.output_tokens_details.reasoning_tokens),
        ),
      ]),
    ),
    #("total_tokens", json.int(usage.total_tokens)),
  ])
}

pub fn response_usage_decoder() -> decode.Decoder(ResponseUsage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use input_tokens_details <- decode.field(
    "input_tokens_details",
    input_token_details_decoder(),
  )
  use output_tokens <- decode.field("output_tokens", decode.int)
  use output_tokens_details <- decode.field(
    "output_tokens_details",
    output_token_details_decoder(),
  )
  use total_tokens <- decode.field("total_tokens", decode.int)
  decode.success(ResponseUsage(
    input_tokens: input_tokens,
    input_tokens_details: input_tokens_details,
    output_tokens: output_tokens,
    output_tokens_details: output_tokens_details,
    total_tokens: total_tokens,
  ))
}

fn input_token_details_decoder() -> decode.Decoder(InputTokenDetails) {
  use cached_tokens <- decode.field("cached_tokens", decode.int)
  decode.success(InputTokenDetails(cached_tokens: cached_tokens))
}

fn output_token_details_decoder() -> decode.Decoder(OutputTokenDetails) {
  use reasoning_tokens <- decode.field("reasoning_tokens", decode.int)
  decode.success(OutputTokenDetails(reasoning_tokens: reasoning_tokens))
}
