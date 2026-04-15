import gleam/http/response
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import glaoi/chat
import glaoi/error
import glaoi/shared

pub fn simple_request_encodes_test() {
  let params =
    chat.new_create_request(model: "gpt-4o", messages: [
      chat.system_message("You are a helpful assistant."),
      chat.user_message("Hello!"),
    ])
    |> chat.with_temperature(0.7)
    |> chat.with_max_completion_tokens(100)

  let encoded =
    chat.create_chat_completion_request_to_json(params) |> json.to_string

  let assert True = string.contains(encoded, "\"model\":\"gpt-4o\"")
  let assert True = string.contains(encoded, "\"role\":\"system\"")
  let assert True = string.contains(encoded, "\"role\":\"user\"")
  let assert True = string.contains(encoded, "\"temperature\":")
  let assert True = string.contains(encoded, "\"max_completion_tokens\":100")
}

pub fn tool_message_encodes_test() {
  let msg = chat.tool_message("{\"temp\": 72}", "call_abc123")
  let encoded = chat.chat_message_to_json(msg) |> json.to_string

  let assert True = string.contains(encoded, "\"role\":\"tool\"")
  let assert True = string.contains(encoded, "\"tool_call_id\":\"call_abc123\"")
}

pub fn tool_choice_function_encodes_test() {
  let choice =
    chat.ToolChoiceFunctionChoice(
      function: shared.FunctionName(name: "get_weather"),
    )
  let encoded = chat.tool_choice_to_json(choice) |> json.to_string

  let assert True = string.contains(encoded, "\"type\":\"function\"")
  let assert True = string.contains(encoded, "\"name\":\"get_weather\"")
}

pub fn create_response_decodes_test() {
  let body =
    "{\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello! How can I help?\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":8,\"total_tokens\":18}}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = chat.create_response(resp)
  assert result.id == "chatcmpl-abc"
  assert result.model == "gpt-4o"
  assert result.created == 1_700_000_000
  let assert [choice] = result.choices
  assert choice.index == 0
  assert choice.message.content == Some("Hello! How can I help?")
  assert choice.message.role == chat.RoleAssistant
  assert choice.finish_reason == Some(chat.Stop)
  let assert Some(usage) = result.usage
  assert usage.prompt_tokens == 10
  assert usage.completion_tokens == 8
  assert usage.total_tokens == 18
}

pub fn response_with_tool_calls_decodes_test() {
  let body =
    "{\"id\":\"chatcmpl-xyz\",\"object\":\"chat.completion\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"type\":\"function\",\"id\":\"call_123\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"SF\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = chat.create_response(resp)
  let assert [choice] = result.choices
  assert choice.message.content == None
  assert choice.finish_reason == Some(chat.ToolCalls)
  let assert Some([chat.FunctionToolCall(id, function)]) =
    choice.message.tool_calls
  assert id == "call_123"
  assert function.name == "get_weather"
  assert function.arguments == "{\"city\":\"SF\"}"
}

pub fn stream_chunk_parses_test() {
  let data =
    "{\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}"

  let assert Ok(Some(chunk)) = chat.parse_stream_chunk(data)
  assert chunk.id == "chatcmpl-abc"
  let assert [choice] = chunk.choices
  assert choice.delta.content == Some("Hello")
  assert choice.finish_reason == None
}

pub fn stream_done_sentinel_test() {
  let assert Ok(None) = chat.parse_stream_chunk("[DONE]")
}

pub fn list_response_decodes_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[],\"usage\":null}],\"first_id\":\"chatcmpl-1\",\"last_id\":\"chatcmpl-1\",\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = chat.list_response(resp)
  assert result.object == "list"
  assert result.has_more == False
  let assert [completion] = result.data
  assert completion.id == "chatcmpl-1"
}

pub fn delete_response_decodes_test() {
  let body =
    "{\"object\":\"chat.completion.deleted\",\"id\":\"chatcmpl-1\",\"deleted\":true}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = chat.delete_response(resp)
  assert result.deleted == True
  assert result.id == "chatcmpl-1"
}

pub fn api_error_response_test() {
  let body =
    "{\"error\":{\"message\":\"Rate limit exceeded\",\"type\":\"rate_limit_error\",\"param\":null,\"code\":null}}"
  let resp = response.new(429) |> response.set_body(body)

  let assert Error(error.ApiResponseError(429, api_error)) =
    chat.create_response(resp)
  assert api_error.message == "Rate limit exceeded"
}
