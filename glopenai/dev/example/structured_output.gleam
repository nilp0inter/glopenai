// Port of: examples/structured-outputs/
//
// Chat completion with structured JSON output using a JSON schema.
//
// Run with: gleam run -m example/structured_output

import example/env
import gleam/dynamic
import gleam/io
import gleam/httpc
import gleam/option.{None, Some}
import glopenai/chat
import glopenai/config
import glopenai/shared

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // Define the JSON schema for math reasoning steps.
  // In Gleam we pass the schema as a raw Dynamic value via json.parse.
  let assert Ok(schema) =
    gleam_json_parse_dynamic(
      "{
      \"type\": \"object\",
      \"properties\": {
        \"steps\": {
          \"type\": \"array\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"explanation\": { \"type\": \"string\" },
              \"output\": { \"type\": \"string\" }
            },
            \"required\": [\"explanation\", \"output\"],
            \"additionalProperties\": false
          }
        },
        \"final_answer\": { \"type\": \"string\" }
      },
      \"required\": [\"steps\", \"final_answer\"],
      \"additionalProperties\": false
    }",
    )

  let response_format =
    shared.ResponseFormatJsonSchemaVariant(
      json_schema: shared.ResponseFormatJsonSchema(
        name: "math_reasoning",
        description: None,
        schema: Some(schema),
        strict: Some(True),
      ),
    )

  let request =
    chat.new_create_request(model: "gpt-4o-mini", messages: [
      chat.system_message(
        "You are a helpful math tutor. Guide the user through the solution step by step.",
      ),
      chat.user_message("how can I solve 8x + 7 = -23"),
    ])
    |> chat.with_max_completion_tokens(512)
    |> chat.with_response_format(response_format)

  let http_request = chat.create_request(cfg, request)

  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = chat.create_response(http_response)

  case response.choices {
    [choice, ..] ->
      case choice.message.content {
        Some(content) -> io.println(content)
        _ -> io.println("(no content)")
      }
    [] -> io.println("(no choices)")
  }
}

// Helper: parse a JSON string into a Dynamic value for use as a schema.
import gleam/dynamic/decode
import gleam/json

fn gleam_json_parse_dynamic(
  input: String,
) -> Result(dynamic.Dynamic, json.DecodeError) {
  json.parse(input, decode.dynamic)
}
