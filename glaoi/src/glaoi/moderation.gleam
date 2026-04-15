/// Moderations API: classify text and images for potentially harmful content.

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

/// Input for moderation requests. Mirrors the Rust `ModerationInput` untagged enum.
pub type ModerationInput {
  StringInput(String)
  StringArrayInput(List(String))
  MultiModalInput(List(ModerationContentPart))
}

/// A content part for multi-modal moderation input, tagged by "type".
pub type ModerationContentPart {
  TextPart(text: String)
  ImageUrlPart(image_url: String)
}

/// The type of input that was moderated.
pub type ModInputType {
  TextInput
  ImageInput
}

/// Request to create a moderation.
pub type CreateModerationRequest {
  CreateModerationRequest(
    input: ModerationInput,
    model: Option(String),
  )
}

/// Whether each category was flagged.
/// Field names use slashes in JSON (e.g. "hate/threatening"), mapped to
/// underscore-separated names in Gleam.
pub type Categories {
  Categories(
    hate: Bool,
    hate_threatening: Bool,
    harassment: Bool,
    harassment_threatening: Bool,
    illicit: Bool,
    illicit_violent: Bool,
    self_harm: Bool,
    self_harm_intent: Bool,
    self_harm_instructions: Bool,
    sexual: Bool,
    sexual_minors: Bool,
    violence: Bool,
    violence_graphic: Bool,
  )
}

/// Confidence scores for each category.
pub type CategoryScore {
  CategoryScore(
    hate: Float,
    hate_threatening: Float,
    harassment: Float,
    harassment_threatening: Float,
    illicit: Float,
    illicit_violent: Float,
    self_harm: Float,
    self_harm_intent: Float,
    self_harm_instructions: Float,
    sexual: Float,
    sexual_minors: Float,
    violence: Float,
    violence_graphic: Float,
  )
}

/// Which input types were applied to each category.
pub type CategoryAppliedInputTypes {
  CategoryAppliedInputTypes(
    hate: List(ModInputType),
    hate_threatening: List(ModInputType),
    harassment: List(ModInputType),
    harassment_threatening: List(ModInputType),
    illicit: List(ModInputType),
    illicit_violent: List(ModInputType),
    self_harm: List(ModInputType),
    self_harm_intent: List(ModInputType),
    self_harm_instructions: List(ModInputType),
    sexual: List(ModInputType),
    sexual_minors: List(ModInputType),
    violence: List(ModInputType),
    violence_graphic: List(ModInputType),
  )
}

/// A single moderation result for one input.
pub type ContentModerationResult {
  ContentModerationResult(
    flagged: Bool,
    categories: Categories,
    category_scores: CategoryScore,
    category_applied_input_types: CategoryAppliedInputTypes,
  )
}

/// Response from creating a moderation.
pub type CreateModerationResponse {
  CreateModerationResponse(
    id: String,
    model: String,
    results: List(ContentModerationResult),
  )
}

// --- Builder ---

/// Create a new moderation request with the required input.
pub fn new_create_request(
  input input: ModerationInput,
) -> CreateModerationRequest {
  CreateModerationRequest(input: input, model: None)
}

/// Set the moderation model.
pub fn with_model(
  request: CreateModerationRequest,
  model: String,
) -> CreateModerationRequest {
  CreateModerationRequest(..request, model: Some(model))
}

// --- Encoders ---

pub fn mod_input_type_to_json(input_type: ModInputType) -> json.Json {
  json.string(case input_type {
    TextInput -> "text"
    ImageInput -> "image"
  })
}

pub fn moderation_content_part_to_json(
  part: ModerationContentPart,
) -> json.Json {
  case part {
    TextPart(text) ->
      json.object([
        #("type", json.string("text")),
        #("text", json.string(text)),
      ])
    ImageUrlPart(url) ->
      json.object([
        #("type", json.string("image_url")),
        #("image_url", json.string(url)),
      ])
  }
}

pub fn moderation_input_to_json(input: ModerationInput) -> json.Json {
  case input {
    StringInput(s) -> json.string(s)
    StringArrayInput(arr) -> json.array(arr, json.string)
    MultiModalInput(parts) ->
      json.array(parts, moderation_content_part_to_json)
  }
}

pub fn create_moderation_request_to_json(
  request: CreateModerationRequest,
) -> json.Json {
  codec.object_with_optional(
    [#("input", moderation_input_to_json(request.input))],
    [codec.optional_field("model", request.model, json.string)],
  )
}

pub fn categories_to_json(categories: Categories) -> json.Json {
  json.object([
    #("hate", json.bool(categories.hate)),
    #("hate/threatening", json.bool(categories.hate_threatening)),
    #("harassment", json.bool(categories.harassment)),
    #("harassment/threatening", json.bool(categories.harassment_threatening)),
    #("illicit", json.bool(categories.illicit)),
    #("illicit/violent", json.bool(categories.illicit_violent)),
    #("self-harm", json.bool(categories.self_harm)),
    #("self-harm/intent", json.bool(categories.self_harm_intent)),
    #("self-harm/instructions", json.bool(categories.self_harm_instructions)),
    #("sexual", json.bool(categories.sexual)),
    #("sexual/minors", json.bool(categories.sexual_minors)),
    #("violence", json.bool(categories.violence)),
    #("violence/graphic", json.bool(categories.violence_graphic)),
  ])
}

pub fn category_score_to_json(scores: CategoryScore) -> json.Json {
  json.object([
    #("hate", json.float(scores.hate)),
    #("hate/threatening", json.float(scores.hate_threatening)),
    #("harassment", json.float(scores.harassment)),
    #("harassment/threatening", json.float(scores.harassment_threatening)),
    #("illicit", json.float(scores.illicit)),
    #("illicit/violent", json.float(scores.illicit_violent)),
    #("self-harm", json.float(scores.self_harm)),
    #("self-harm/intent", json.float(scores.self_harm_intent)),
    #("self-harm/instructions", json.float(scores.self_harm_instructions)),
    #("sexual", json.float(scores.sexual)),
    #("sexual/minors", json.float(scores.sexual_minors)),
    #("violence", json.float(scores.violence)),
    #("violence/graphic", json.float(scores.violence_graphic)),
  ])
}

pub fn category_applied_input_types_to_json(
  types: CategoryAppliedInputTypes,
) -> json.Json {
  json.object([
    #("hate", json.array(types.hate, mod_input_type_to_json)),
    #(
      "hate/threatening",
      json.array(types.hate_threatening, mod_input_type_to_json),
    ),
    #("harassment", json.array(types.harassment, mod_input_type_to_json)),
    #(
      "harassment/threatening",
      json.array(types.harassment_threatening, mod_input_type_to_json),
    ),
    #("illicit", json.array(types.illicit, mod_input_type_to_json)),
    #(
      "illicit/violent",
      json.array(types.illicit_violent, mod_input_type_to_json),
    ),
    #("self-harm", json.array(types.self_harm, mod_input_type_to_json)),
    #(
      "self-harm/intent",
      json.array(types.self_harm_intent, mod_input_type_to_json),
    ),
    #(
      "self-harm/instructions",
      json.array(types.self_harm_instructions, mod_input_type_to_json),
    ),
    #("sexual", json.array(types.sexual, mod_input_type_to_json)),
    #(
      "sexual/minors",
      json.array(types.sexual_minors, mod_input_type_to_json),
    ),
    #("violence", json.array(types.violence, mod_input_type_to_json)),
    #(
      "violence/graphic",
      json.array(types.violence_graphic, mod_input_type_to_json),
    ),
  ])
}

// --- Decoders ---

pub fn mod_input_type_decoder() -> decode.Decoder(ModInputType) {
  use value <- decode.then(decode.string)
  case value {
    "text" -> decode.success(TextInput)
    "image" -> decode.success(ImageInput)
    _ -> decode.failure(TextInput, "ModInputType")
  }
}

pub fn moderation_content_part_decoder() -> decode.Decoder(
  ModerationContentPart,
) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "text" -> {
      use text <- decode.field("text", decode.string)
      decode.success(TextPart(text: text))
    }
    "image_url" -> {
      use url <- decode.field("image_url", decode.string)
      decode.success(ImageUrlPart(image_url: url))
    }
    _ -> decode.failure(TextPart(text: ""), "ModerationContentPart")
  }
}

pub fn moderation_input_decoder() -> decode.Decoder(ModerationInput) {
  decode.one_of(decode.string |> decode.map(StringInput), [
    decode.list(moderation_content_part_decoder())
      |> decode.map(MultiModalInput),
    decode.list(decode.string) |> decode.map(StringArrayInput),
  ])
}

pub fn categories_decoder() -> decode.Decoder(Categories) {
  use hate <- decode.field("hate", decode.bool)
  use hate_threatening <- decode.field("hate/threatening", decode.bool)
  use harassment <- decode.field("harassment", decode.bool)
  use harassment_threatening <- decode.field(
    "harassment/threatening",
    decode.bool,
  )
  use illicit <- decode.field("illicit", decode.bool)
  use illicit_violent <- decode.field("illicit/violent", decode.bool)
  use self_harm <- decode.field("self-harm", decode.bool)
  use self_harm_intent <- decode.field("self-harm/intent", decode.bool)
  use self_harm_instructions <- decode.field(
    "self-harm/instructions",
    decode.bool,
  )
  use sexual <- decode.field("sexual", decode.bool)
  use sexual_minors <- decode.field("sexual/minors", decode.bool)
  use violence <- decode.field("violence", decode.bool)
  use violence_graphic <- decode.field("violence/graphic", decode.bool)
  decode.success(Categories(
    hate: hate,
    hate_threatening: hate_threatening,
    harassment: harassment,
    harassment_threatening: harassment_threatening,
    illicit: illicit,
    illicit_violent: illicit_violent,
    self_harm: self_harm,
    self_harm_intent: self_harm_intent,
    self_harm_instructions: self_harm_instructions,
    sexual: sexual,
    sexual_minors: sexual_minors,
    violence: violence,
    violence_graphic: violence_graphic,
  ))
}

pub fn category_score_decoder() -> decode.Decoder(CategoryScore) {
  use hate <- decode.field("hate", decode.float)
  use hate_threatening <- decode.field("hate/threatening", decode.float)
  use harassment <- decode.field("harassment", decode.float)
  use harassment_threatening <- decode.field(
    "harassment/threatening",
    decode.float,
  )
  use illicit <- decode.field("illicit", decode.float)
  use illicit_violent <- decode.field("illicit/violent", decode.float)
  use self_harm <- decode.field("self-harm", decode.float)
  use self_harm_intent <- decode.field("self-harm/intent", decode.float)
  use self_harm_instructions <- decode.field(
    "self-harm/instructions",
    decode.float,
  )
  use sexual <- decode.field("sexual", decode.float)
  use sexual_minors <- decode.field("sexual/minors", decode.float)
  use violence <- decode.field("violence", decode.float)
  use violence_graphic <- decode.field("violence/graphic", decode.float)
  decode.success(CategoryScore(
    hate: hate,
    hate_threatening: hate_threatening,
    harassment: harassment,
    harassment_threatening: harassment_threatening,
    illicit: illicit,
    illicit_violent: illicit_violent,
    self_harm: self_harm,
    self_harm_intent: self_harm_intent,
    self_harm_instructions: self_harm_instructions,
    sexual: sexual,
    sexual_minors: sexual_minors,
    violence: violence,
    violence_graphic: violence_graphic,
  ))
}

pub fn category_applied_input_types_decoder() -> decode.Decoder(
  CategoryAppliedInputTypes,
) {
  use hate <- decode.field("hate", decode.list(mod_input_type_decoder()))
  use hate_threatening <- decode.field(
    "hate/threatening",
    decode.list(mod_input_type_decoder()),
  )
  use harassment <- decode.field(
    "harassment",
    decode.list(mod_input_type_decoder()),
  )
  use harassment_threatening <- decode.field(
    "harassment/threatening",
    decode.list(mod_input_type_decoder()),
  )
  use illicit <- decode.field("illicit", decode.list(mod_input_type_decoder()))
  use illicit_violent <- decode.field(
    "illicit/violent",
    decode.list(mod_input_type_decoder()),
  )
  use self_harm <- decode.field(
    "self-harm",
    decode.list(mod_input_type_decoder()),
  )
  use self_harm_intent <- decode.field(
    "self-harm/intent",
    decode.list(mod_input_type_decoder()),
  )
  use self_harm_instructions <- decode.field(
    "self-harm/instructions",
    decode.list(mod_input_type_decoder()),
  )
  use sexual <- decode.field("sexual", decode.list(mod_input_type_decoder()))
  use sexual_minors <- decode.field(
    "sexual/minors",
    decode.list(mod_input_type_decoder()),
  )
  use violence <- decode.field(
    "violence",
    decode.list(mod_input_type_decoder()),
  )
  use violence_graphic <- decode.field(
    "violence/graphic",
    decode.list(mod_input_type_decoder()),
  )
  decode.success(CategoryAppliedInputTypes(
    hate: hate,
    hate_threatening: hate_threatening,
    harassment: harassment,
    harassment_threatening: harassment_threatening,
    illicit: illicit,
    illicit_violent: illicit_violent,
    self_harm: self_harm,
    self_harm_intent: self_harm_intent,
    self_harm_instructions: self_harm_instructions,
    sexual: sexual,
    sexual_minors: sexual_minors,
    violence: violence,
    violence_graphic: violence_graphic,
  ))
}

pub fn content_moderation_result_decoder() -> decode.Decoder(
  ContentModerationResult,
) {
  use flagged <- decode.field("flagged", decode.bool)
  use categories <- decode.field("categories", categories_decoder())
  use category_scores <- decode.field(
    "category_scores",
    category_score_decoder(),
  )
  use category_applied_input_types <- decode.field(
    "category_applied_input_types",
    category_applied_input_types_decoder(),
  )
  decode.success(ContentModerationResult(
    flagged: flagged,
    categories: categories,
    category_scores: category_scores,
    category_applied_input_types: category_applied_input_types,
  ))
}

fn create_moderation_response_decoder() -> decode.Decoder(
  CreateModerationResponse,
) {
  use id <- decode.field("id", decode.string)
  use model <- decode.field("model", decode.string)
  use results <- decode.field(
    "results",
    decode.list(content_moderation_result_decoder()),
  )
  decode.success(CreateModerationResponse(
    id: id,
    model: model,
    results: results,
  ))
}

// --- Request/Response pairs (sans-io) ---

/// Build a request to create a moderation.
pub fn create_request(
  config: Config,
  params: CreateModerationRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/moderations",
    create_moderation_request_to_json(params),
  )
}

/// Parse the response from creating a moderation.
pub fn create_response(
  response: Response(String),
) -> Result(CreateModerationResponse, GlaoiError) {
  internal.parse_response(response, create_moderation_response_decoder())
}
