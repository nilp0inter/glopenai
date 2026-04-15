import gleam/http/response
import gleam/json
import gleam/string
import glaoi/moderation

pub fn create_request_encodes_string_input_test() {
  let params =
    moderation.new_create_request(
      input: moderation.StringInput("I hate you"),
    )
    |> moderation.with_model("omni-moderation-latest")

  let encoded =
    moderation.create_moderation_request_to_json(params)
    |> json.to_string

  let assert True = string.contains(encoded, "\"input\":\"I hate you\"")
  let assert True =
    string.contains(encoded, "\"model\":\"omni-moderation-latest\"")
}

pub fn create_request_encodes_multimodal_input_test() {
  let params =
    moderation.new_create_request(
      input: moderation.MultiModalInput([
        moderation.TextPart(text: "Check this"),
        moderation.ImageUrlPart(image_url: "https://example.com/img.png"),
      ]),
    )

  let encoded =
    moderation.create_moderation_request_to_json(params)
    |> json.to_string

  let assert True = string.contains(encoded, "\"type\":\"text\"")
  let assert True = string.contains(encoded, "\"type\":\"image_url\"")
  // model should be omitted when None
  let assert False = string.contains(encoded, "\"model\"")
}

pub fn create_response_decodes_test() {
  let body =
    "{\"id\":\"modr-abc123\",\"model\":\"omni-moderation-latest\",\"results\":[{\"flagged\":true,\"categories\":{\"hate\":true,\"hate/threatening\":false,\"harassment\":false,\"harassment/threatening\":false,\"illicit\":false,\"illicit/violent\":false,\"self-harm\":false,\"self-harm/intent\":false,\"self-harm/instructions\":false,\"sexual\":false,\"sexual/minors\":false,\"violence\":false,\"violence/graphic\":false},\"category_scores\":{\"hate\":0.9,\"hate/threatening\":0.1,\"harassment\":0.2,\"harassment/threatening\":0.0,\"illicit\":0.0,\"illicit/violent\":0.0,\"self-harm\":0.0,\"self-harm/intent\":0.0,\"self-harm/instructions\":0.0,\"sexual\":0.0,\"sexual/minors\":0.0,\"violence\":0.0,\"violence/graphic\":0.0},\"category_applied_input_types\":{\"hate\":[\"text\"],\"hate/threatening\":[],\"harassment\":[\"text\"],\"harassment/threatening\":[],\"illicit\":[],\"illicit/violent\":[],\"self-harm\":[],\"self-harm/intent\":[],\"self-harm/instructions\":[],\"sexual\":[],\"sexual/minors\":[],\"violence\":[],\"violence/graphic\":[]}}]}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = moderation.create_response(resp)
  assert result.id == "modr-abc123"
  assert result.model == "omni-moderation-latest"
  let assert [moderation_result] = result.results
  assert moderation_result.flagged == True
  assert moderation_result.categories.hate == True
  assert moderation_result.categories.harassment == False
  assert moderation_result.category_scores.hate == 0.9
  let assert [moderation.TextInput] =
    moderation_result.category_applied_input_types.hate
}

pub fn create_response_api_error_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid model\",\"type\":\"invalid_request_error\",\"param\":\"model\",\"code\":\"invalid_model\"}}"
  let resp = response.new(400) |> response.set_body(body)

  let assert Error(_) = moderation.create_response(resp)
}

pub fn string_array_input_encodes_test() {
  let input = moderation.StringArrayInput(["Hello", "World"])
  let encoded = moderation.moderation_input_to_json(input) |> json.to_string
  assert encoded == "[\"Hello\",\"World\"]"
}
