/// Models API: list, retrieve, and delete models.

import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/internal

// --- Types ---

/// Describes an OpenAI model offering that can be used with the API.
pub type Model {
  Model(
    id: String,
    object: String,
    created: Int,
    owned_by: String,
  )
}

pub type ListModelResponse {
  ListModelResponse(object: String, data: List(Model))
}

pub type DeleteModelResponse {
  DeleteModelResponse(id: String, object: String, deleted: Bool)
}

// --- Encoders ---

pub fn model_to_json(model: Model) -> json.Json {
  json.object([
    #("id", json.string(model.id)),
    #("object", json.string(model.object)),
    #("created", json.int(model.created)),
    #("owned_by", json.string(model.owned_by)),
  ])
}

// --- Decoders ---

pub fn model_decoder() -> decode.Decoder(Model) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use created <- decode.field("created", decode.int)
  use owned_by <- decode.field("owned_by", decode.string)
  decode.success(Model(
    id: id,
    object: object,
    created: created,
    owned_by: owned_by,
  ))
}

fn list_model_response_decoder() -> decode.Decoder(ListModelResponse) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field("data", decode.list(model_decoder()))
  decode.success(ListModelResponse(object: object, data: data))
}

fn delete_model_response_decoder() -> decode.Decoder(DeleteModelResponse) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeleteModelResponse(
    id: id,
    object: object,
    deleted: deleted,
  ))
}

// --- Request/Response pairs (sans-io) ---

/// Build a request to list all available models.
pub fn list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/models")
}

/// Parse the response from listing models.
pub fn list_response(
  response: Response(String),
) -> Result(ListModelResponse, GlopenaiError) {
  internal.parse_response(response, list_model_response_decoder())
}

/// Build a request to retrieve a specific model.
pub fn retrieve_request(
  config: Config,
  model_id: String,
) -> Request(String) {
  internal.get_request(config, "/models/" <> model_id)
}

/// Parse the response from retrieving a model.
pub fn retrieve_response(
  response: Response(String),
) -> Result(Model, GlopenaiError) {
  internal.parse_response(response, model_decoder())
}

/// Build a request to delete a fine-tuned model.
pub fn delete_request(
  config: Config,
  model_id: String,
) -> Request(String) {
  internal.delete_request(config, "/models/" <> model_id)
}

/// Parse the response from deleting a model.
pub fn delete_response(
  response: Response(String),
) -> Result(DeleteModelResponse, GlopenaiError) {
  internal.parse_response(response, delete_model_response_decoder())
}
