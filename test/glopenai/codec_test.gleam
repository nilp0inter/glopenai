import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import glopenai/chat
import glopenai/internal/codec
import glopenai/shared

// --- dynamic_to_json ---

pub fn dynamic_to_json_object_test() {
  let assert Ok(value) =
    json.parse(
      "{\"type\": \"object\", \"properties\": {\"name\": {\"type\": \"string\"}}}",
      decode.dynamic,
    )
  let result = codec.dynamic_to_json(value) |> json.to_string
  let assert True = string.contains(result, "\"type\":\"object\"")
  let assert True = string.contains(result, "\"properties\"")
  let assert True = string.contains(result, "\"name\"")
}

pub fn dynamic_to_json_string_test() {
  let assert Ok(value) = json.parse("\"hello\"", decode.dynamic)
  let result = codec.dynamic_to_json(value) |> json.to_string
  assert result == "\"hello\""
}

pub fn dynamic_to_json_number_test() {
  let assert Ok(value) = json.parse("42", decode.dynamic)
  let result = codec.dynamic_to_json(value) |> json.to_string
  assert result == "42"
}

pub fn dynamic_to_json_array_test() {
  let assert Ok(value) = json.parse("[1, 2, 3]", decode.dynamic)
  let result = codec.dynamic_to_json(value) |> json.to_string
  assert result == "[1,2,3]"
}

pub fn dynamic_to_json_bool_test() {
  let assert Ok(value) = json.parse("true", decode.dynamic)
  let result = codec.dynamic_to_json(value) |> json.to_string
  assert result == "true"
}

pub fn dynamic_to_json_null_test() {
  let assert Ok(value) = json.parse("null", decode.dynamic)
  let result = codec.dynamic_to_json(value) |> json.to_string
  assert result == "null"
}

pub fn dynamic_to_json_nested_test() {
  let input =
    "{\"a\": {\"b\": [1, \"two\", null, true]}, \"c\": 3.14}"
  let assert Ok(value) = json.parse(input, decode.dynamic)
  let result = codec.dynamic_to_json(value) |> json.to_string
  // Verify all values survived the round-trip
  let assert True = string.contains(result, "\"b\":[1,\"two\",null,true]")
  let assert True = string.contains(result, "\"c\":3.14") || string.contains(result, "\"c\":3.14")
}

// --- FunctionObject with parameters round-trip ---

pub fn function_object_with_parameters_encodes_test() {
  let assert Ok(params) =
    json.parse(
      "{\"type\": \"object\", \"properties\": {\"location\": {\"type\": \"string\"}}, \"required\": [\"location\"], \"additionalProperties\": false}",
      decode.dynamic,
    )

  let function =
    shared.FunctionObject(
      name: "get_weather",
      description: Some("Get weather"),
      parameters: Some(params),
      strict: Some(True),
    )

  let encoded = shared.function_object_to_json(function) |> json.to_string
  let assert True = string.contains(encoded, "\"name\":\"get_weather\"")
  let assert True = string.contains(encoded, "\"description\":\"Get weather\"")
  let assert True = string.contains(encoded, "\"strict\":true")
  // The parameters schema must be present and contain the original values
  let assert True = string.contains(encoded, "\"parameters\":")
  let assert True = string.contains(encoded, "\"type\":\"object\"")
  let assert True = string.contains(encoded, "\"additionalProperties\":false")
  let assert True = string.contains(encoded, "\"required\":[\"location\"]")
}

pub fn function_object_without_parameters_encodes_test() {
  let function =
    shared.FunctionObject(
      name: "no_params",
      description: None,
      parameters: None,
      strict: None,
    )

  let encoded = shared.function_object_to_json(function) |> json.to_string
  assert encoded == "{\"name\":\"no_params\"}"
}

pub fn function_object_parameters_round_trip_test() {
  // Encode a FunctionObject with parameters, then parse the output
  // and verify the parameters field can be decoded back
  let schema =
    "{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"},\"unit\":{\"type\":\"string\",\"enum\":[\"celsius\",\"fahrenheit\"]}},\"required\":[\"city\"],\"additionalProperties\":false}"
  let assert Ok(params) = json.parse(schema, decode.dynamic)

  let function =
    shared.FunctionObject(
      name: "get_temp",
      description: Some("Get temperature"),
      parameters: Some(params),
      strict: Some(True),
    )

  // Encode to JSON string
  let encoded = shared.function_object_to_json(function) |> json.to_string

  // Decode back
  let assert Ok(decoded) =
    json.parse(encoded, shared.function_object_decoder())

  assert decoded.name == "get_temp"
  assert decoded.description == Some("Get temperature")
  assert decoded.strict == Some(True)
  // Parameters should be Some (not lost in round-trip)
  let assert Some(_) = decoded.parameters
}

// --- Tool encoding in chat request ---

pub fn chat_tool_with_parameters_encodes_test() {
  let assert Ok(params) =
    json.parse(
      "{\"type\":\"object\",\"properties\":{\"q\":{\"type\":\"string\"}},\"required\":[\"q\"],\"additionalProperties\":false}",
      decode.dynamic,
    )

  let tool =
    chat.FunctionTool(
      function: shared.FunctionObject(
        name: "search",
        description: Some("Search the web"),
        parameters: Some(params),
        strict: Some(True),
      ),
    )

  let encoded = chat.chat_completion_tool_to_json(tool) |> json.to_string
  let assert True = string.contains(encoded, "\"type\":\"function\"")
  let assert True = string.contains(encoded, "\"name\":\"search\"")
  let assert True = string.contains(encoded, "\"additionalProperties\":false")
  let assert True = string.contains(encoded, "\"required\":[\"q\"]")
}
