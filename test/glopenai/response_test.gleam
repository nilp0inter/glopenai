import gleam/http
import gleam/http/response
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import glopenai/config
import glopenai/error
import glopenai/response as resp

pub fn simple_request_encodes_test() {
  let request =
    resp.new_create_response(input: resp.InputText("Hello!"))
    |> resp.with_model("gpt-4o")
    |> resp.with_temperature(0.7)
    |> resp.with_max_output_tokens(1000)

  let encoded = resp.create_response_to_json(request) |> json.to_string

  let assert True = string.contains(encoded, "\"input\":\"Hello!\"")
  let assert True = string.contains(encoded, "\"model\":\"gpt-4o\"")
  let assert True = string.contains(encoded, "\"max_output_tokens\":1000")
}

pub fn request_with_instructions_test() {
  let request =
    resp.new_create_response(input: resp.InputText("What is 2+2?"))
    |> resp.with_model("gpt-4o")
    |> resp.with_instructions("You are a math tutor.")
    |> resp.with_store(True)

  let encoded = resp.create_response_to_json(request) |> json.to_string

  let assert True =
    string.contains(encoded, "\"instructions\":\"You are a math tutor.\"")
  let assert True = string.contains(encoded, "\"store\":true")
}

pub fn request_building_test() {
  let cfg = config.new("test-key")
  let request =
    resp.new_create_response(input: resp.InputText("test"))
    |> resp.with_model("gpt-4o")
  let http_req = resp.create_request(cfg, request)

  assert http_req.method == http.Post
  let assert True = string.contains(http_req.path, "/responses")
}

pub fn retrieve_request_building_test() {
  let cfg = config.new("test-key")
  let http_req = resp.retrieve_request(cfg, "resp_abc")

  assert http_req.method == http.Get
  let assert True = string.contains(http_req.path, "/responses/resp_abc")
}

pub fn delete_request_building_test() {
  let cfg = config.new("test-key")
  let http_req = resp.delete_request(cfg, "resp_abc")

  assert http_req.method == http.Delete
  let assert True = string.contains(http_req.path, "/responses/resp_abc")
}

pub fn cancel_request_building_test() {
  let cfg = config.new("test-key")
  let http_req = resp.cancel_request(cfg, "resp_abc")

  assert http_req.method == http.Post
  let assert True = string.contains(http_req.path, "/responses/resp_abc/cancel")
}

pub fn response_decoding_test() {
  let body =
    "{\"id\":\"resp_abc\",\"object\":\"response\",\"created_at\":1700000000,\"model\":\"gpt-4o\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"id\":\"msg_abc\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello! How can I help?\",\"annotations\":[]}],\"status\":\"completed\"}]}"
  let http_resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = resp.create_response_response(http_resp)
  assert result.id == "resp_abc"
  assert result.model == "gpt-4o"
  assert result.status == resp.StatusCompleted
  let assert [resp.OutputItemMessage(msg)] = result.output
  assert msg.id == "msg_abc"
  assert msg.status == resp.OutputCompleted
  let assert [resp.OutputMessageOutputText(text_content)] = msg.content
  assert text_content.text == "Hello! How can I help?"
}

pub fn response_with_function_call_test() {
  let body =
    "{\"id\":\"resp_fc\",\"object\":\"response\",\"created_at\":1700000000,\"model\":\"gpt-4o\",\"status\":\"completed\",\"output\":[{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_abc\",\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"SF\\\"}\",\"status\":\"completed\"}]}"
  let http_resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = resp.create_response_response(http_resp)
  let assert [resp.OutputItemFunctionCall(fc)] = result.output
  assert fc.name == "get_weather"
  assert fc.call_id == "call_abc"
  assert fc.arguments == "{\"city\":\"SF\"}"
}

pub fn response_with_reasoning_test() {
  let body =
    "{\"id\":\"resp_r\",\"object\":\"response\",\"created_at\":1700000000,\"model\":\"o3\",\"status\":\"completed\",\"output\":[{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"Thinking about the problem...\"}],\"status\":\"completed\"}]}"
  let http_resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = resp.create_response_response(http_resp)
  let assert [resp.OutputItemReasoning(reasoning)] = result.output
  assert reasoning.id == "rs_1"
  let assert [resp.SummaryPartSummaryText(summary)] = reasoning.summary
  assert summary.text == "Thinking about the problem..."
}

pub fn delete_response_decoding_test() {
  let body = "{\"object\":\"response\",\"deleted\":true,\"id\":\"resp_abc\"}"
  let http_resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = resp.delete_response(http_resp)
  assert result.id == "resp_abc"
  assert result.deleted == True
}

pub fn api_error_response_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid API key\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":\"invalid_api_key\"}}"
  let http_resp = response.new(401) |> response.set_body(body)

  let assert Error(error.ApiResponseError(status, api_error)) =
    resp.create_response_response(http_resp)
  assert status == 401
  assert api_error.message == "Invalid API key"
}

pub fn stream_event_text_delta_test() {
  let data =
    "{\"type\":\"response.output_text.delta\",\"sequence_number\":5,\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello\"}"

  let assert Ok(Some(event)) = resp.parse_stream_event(data)
  let assert resp.EventResponseOutputTextDelta(
    sequence_number: 5,
    item_id: "msg_1",
    output_index: 0,
    content_index: 0,
    delta: "Hello",
    logprobs: None,
  ) = event
}

pub fn stream_event_done_sentinel_test() {
  let assert Ok(None) = resp.parse_stream_event("[DONE]")
}

pub fn stream_event_response_created_test() {
  let data =
    "{\"type\":\"response.created\",\"sequence_number\":0,\"response\":{\"id\":\"resp_1\",\"object\":\"response\",\"created_at\":1700000000,\"model\":\"gpt-4o\",\"status\":\"in_progress\",\"output\":[]}}"

  let assert Ok(Some(event)) = resp.parse_stream_event(data)
  let assert resp.EventResponseCreated(sequence_number: 0, response: r) = event
  assert r.id == "resp_1"
  assert r.status == resp.StatusInProgress
}

pub fn stream_event_function_call_args_delta_test() {
  let data =
    "{\"type\":\"response.function_call_arguments.delta\",\"sequence_number\":3,\"item_id\":\"fc_1\",\"output_index\":0,\"delta\":\"{\\\"ci\"}"

  let assert Ok(Some(event)) = resp.parse_stream_event(data)
  let assert resp.EventResponseFunctionCallArgumentsDelta(
    sequence_number: 3,
    item_id: "fc_1",
    output_index: 0,
    delta: _,
  ) = event
}

pub fn stream_event_error_test() {
  let data =
    "{\"type\":\"error\",\"sequence_number\":1,\"code\":\"rate_limit\",\"message\":\"Rate limit exceeded\",\"param\":null}"

  let assert Ok(Some(event)) = resp.parse_stream_event(data)
  let assert resp.EventResponseError(
    sequence_number: 1,
    code: Some("rate_limit"),
    message: "Rate limit exceeded",
    param: None,
  ) = event
}

pub fn tool_encoding_test() {
  let tool =
    resp.ToolFunction(resp.FunctionTool(
      name: "get_weather",
      description: Some("Get weather for a city"),
      parameters: None,
      strict: Some(True),
      defer_loading: None,
    ))

  let encoded = resp.tool_to_json(tool) |> json.to_string

  let assert True = string.contains(encoded, "\"type\":\"function\"")
  let assert True = string.contains(encoded, "\"name\":\"get_weather\"")
}

pub fn include_enum_encoding_test() {
  let request =
    resp.new_create_response(input: resp.InputText("test"))
    |> resp.with_include([
      resp.IncludeWebSearchCallActionSources,
      resp.IncludeReasoningEncryptedContent,
    ])

  let encoded = resp.create_response_to_json(request) |> json.to_string

  let assert True = string.contains(encoded, "web_search_call.action.sources")
  let assert True = string.contains(encoded, "reasoning.encrypted_content")
}

pub fn response_with_usage_test() {
  let body =
    "{\"id\":\"resp_u\",\"object\":\"response\",\"created_at\":1700000000,\"model\":\"gpt-4o\",\"status\":\"completed\",\"output\":[],\"usage\":{\"input_tokens\":10,\"input_tokens_details\":{\"cached_tokens\":0},\"output_tokens\":20,\"output_tokens_details\":{\"reasoning_tokens\":5},\"total_tokens\":30}}"
  let http_resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = resp.create_response_response(http_resp)
  let assert Some(usage) = result.usage
  assert usage.input_tokens == 10
  assert usage.output_tokens == 20
  assert usage.total_tokens == 30
}
