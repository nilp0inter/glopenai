// Port of: examples/responses-structured-outputs/ (chain-of-thought variant)
//
// Structured output via JSON schema with the Responses API. The model walks
// through a math problem step by step and returns the reasoning + final
// answer as JSON matching the supplied schema.
//
// Run with: gleam run -m example/response_structured_outputs

import example/env
import gleam/dynamic/decode
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import glopenai/config
import glopenai/response as resp
import glopenai/shared

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // JSON schema describing the expected structured output.
  let assert Ok(schema) =
    json.parse(
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
      decode.dynamic,
    )

  let text_param =
    resp.ResponseTextParam(
      format: resp.TextFormatJsonSchema(shared.ResponseFormatJsonSchema(
        name: "math_reasoning",
        description: Some(
          "A step-by-step reasoning process for solving math problems",
        ),
        schema: Some(schema),
        strict: Some(True),
      )),
      verbosity: None,
    )

  let input_items = [
    resp.InputItemItem(resp.ItemMessage(resp.MessageItemInput(
      resp.InputMessage(
        role: resp.InputRoleSystem,
        content: [
          resp.ContentInputText(resp.InputTextContent(
            text: "You are a helpful math tutor. Guide the user through the solution step by step.",
          )),
        ],
        status: None,
      ),
    ))),
    resp.InputItemItem(resp.ItemMessage(resp.MessageItemInput(
      resp.InputMessage(
        role: resp.InputRoleUser,
        content: [
          resp.ContentInputText(resp.InputTextContent(
            text: "How can I solve 8x + 7 = -23?",
          )),
        ],
        status: None,
      ),
    ))),
  ]

  let request =
    resp.new_create_response(input: resp.InputItems(input_items))
    |> resp.with_model("gpt-4o-2024-08-06")
    |> resp.with_max_output_tokens(512)
    |> resp.with_text(text_param)

  let http_request = resp.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = resp.create_response_response(http_response)

  io.println("\nStructured response:\n")
  list.each(response.output, fn(item) {
    case item {
      resp.OutputItemMessage(msg) ->
        list.each(msg.content, fn(content) {
          case content {
            resp.OutputMessageOutputText(text) -> io.println(text.text)
            _ -> Nil
          }
        })
      _ -> Nil
    }
  })
}
