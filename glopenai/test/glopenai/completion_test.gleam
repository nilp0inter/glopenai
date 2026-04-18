import gleam/http
import gleam/http/response
import gleam/json
import gleam/option.{Some}
import gleam/string
import glopenai/completion
import glopenai/config
import glopenai/error

pub fn request_encoding_test() {
  let request =
    completion.new_create_request(
      model: "gpt-3.5-turbo-instruct",
      prompt: completion.PromptString("Say hello"),
    )
    |> completion.with_max_tokens(100)
    |> completion.with_temperature(0.7)

  let encoded =
    completion.create_completion_request_to_json(request) |> json.to_string

  let assert True = string.contains(encoded, "\"model\":\"gpt-3.5-turbo-instruct\"")
  let assert True = string.contains(encoded, "\"prompt\":\"Say hello\"")
  let assert True = string.contains(encoded, "\"max_tokens\":100")
}

pub fn array_prompt_encoding_test() {
  let request =
    completion.new_create_request(
      model: "gpt-3.5-turbo-instruct",
      prompt: completion.PromptStringArray(["Hello", "World"]),
    )

  let encoded =
    completion.create_completion_request_to_json(request) |> json.to_string

  let assert True = string.contains(encoded, "[\"Hello\",\"World\"]")
}

pub fn request_building_test() {
  let cfg = config.new("test-key")
  let request =
    completion.new_create_request(
      model: "gpt-3.5-turbo-instruct",
      prompt: completion.PromptString("test"),
    )
  let http_req = completion.create_request(cfg, request)

  assert http_req.method == http.Post
  let assert True = string.contains(http_req.path, "/completions")
}

pub fn response_decoding_test() {
  let body =
    "{\"id\":\"cmpl-abc\",\"choices\":[{\"text\":\"Hello!\",\"index\":0,\"logprobs\":null,\"finish_reason\":\"stop\"}],\"created\":1234567890,\"model\":\"gpt-3.5-turbo-instruct\",\"object\":\"text_completion\",\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = completion.create_response(resp)
  assert result.id == "cmpl-abc"
  assert result.object == "text_completion"
  assert result.model == "gpt-3.5-turbo-instruct"
  let assert [choice] = result.choices
  assert choice.text == "Hello!"
  assert choice.index == 0
  assert choice.finish_reason == Some(completion.FinishReasonStop)
  let assert Some(usage) = result.usage
  assert usage.prompt_tokens == 5
  assert usage.total_tokens == 7
}

pub fn api_error_response_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid API key\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":\"invalid_api_key\"}}"
  let resp = response.new(401) |> response.set_body(body)

  let assert Error(error.ApiResponseError(status, api_error)) =
    completion.create_response(resp)
  assert status == 401
  assert api_error.message == "Invalid API key"
}

pub fn stop_configuration_encoding_test() {
  let request =
    completion.new_create_request(
      model: "gpt-3.5-turbo-instruct",
      prompt: completion.PromptString("test"),
    )
    |> completion.with_stop(completion.StopStringArray([".", "!"]))

  let encoded =
    completion.create_completion_request_to_json(request) |> json.to_string

  let assert True = string.contains(encoded, "[\".\",\"!\"]")
}
