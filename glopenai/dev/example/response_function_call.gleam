// Port of: examples/responses-function-call/ (non-streaming variant)
//
// Function calling with the Responses API: model requests a tool call,
// we execute it locally, then send the result back for a final answer.
//
// Run with: gleam run -m example/response_function_call

import example/env
import gleam/dynamic/decode
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import glopenai/config
import glopenai/response as resp

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let user_prompt = "What's the weather like in Paris today?"

  // Define the weather tool
  let assert Ok(params) =
    json.parse(
      "{
        \"type\": \"object\",
        \"properties\": {
          \"location\": {
            \"type\": \"string\",
            \"description\": \"City and country e.g. Bogotá, Colombia\"
          },
          \"units\": {
            \"type\": \"string\",
            \"enum\": [\"celsius\", \"fahrenheit\"],
            \"description\": \"Units the temperature will be returned in.\"
          }
        },
        \"required\": [\"location\", \"units\"],
        \"additionalProperties\": false
      }",
      decode.dynamic,
    )

  let weather_tool =
    resp.ToolFunction(resp.FunctionTool(
      name: "get_weather",
      description: Some("Retrieves current weather for the given location"),
      parameters: Some(params),
      strict: None,
      defer_loading: None,
    ))

  // First request: user asks for weather, model decides to call the tool
  let initial_items = [
    resp.InputItemEasyMessage(resp.EasyInputMessage(
      role: resp.RoleUser,
      content: resp.EasyContentText(user_prompt),
      phase: None,
    )),
  ]

  let request =
    resp.new_create_response(input: resp.InputItems(initial_items))
    |> resp.with_model("gpt-4.1")
    |> resp.with_max_output_tokens(512)
    |> resp.with_tools([weather_tool])

  io.println("Sending initial request...")
  let http_request = resp.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = resp.create_response_response(http_response)

  // Find the function call request in the output
  let function_call_opt =
    list.find_map(response.output, fn(item) {
      case item {
        resp.OutputItemFunctionCall(fc) -> Ok(fc)
        _ -> Error(Nil)
      }
    })

  case function_call_opt {
    Error(Nil) -> io.println("No function_call request found")
    Ok(fc) -> {
      io.println(
        "Function call requested: "
        <> fc.name
        <> " with arguments: "
        <> fc.arguments,
      )

      let function_result = case fc.name {
        "get_weather" -> check_weather_from_args(fc.arguments)
        _ -> "Unknown function: " <> fc.name
      }

      io.println("Function result: " <> function_result)

      // Build the follow-up input: original user message, then the function
      // call, then the function output.
      let followup_items =
        list.flatten([
          initial_items,
          [
            resp.InputItemItem(resp.ItemFunctionCall(fc)),
            resp.InputItemItem(resp.ItemFunctionCallOutput(
              resp.FunctionCallOutputItemParam(
                call_id: fc.call_id,
                output: resp.FunctionCallOutputText(function_result),
                id: None,
                status: None,
              ),
            )),
          ],
        ])

      let followup_request =
        resp.new_create_response(input: resp.InputItems(followup_items))
        |> resp.with_model("gpt-4.1")
        |> resp.with_max_output_tokens(512)
        |> resp.with_tools([weather_tool])

      io.println("\nSending follow-up request with function result...")
      let followup_http = resp.create_request(cfg, followup_request)
      let assert Ok(followup_response) = httpc.send(followup_http)
      let assert Ok(final_response) =
        resp.create_response_response(followup_response)

      io.println("\nFinal response:")
      list.each(final_response.output, fn(item) {
        case item {
          resp.OutputItemMessage(msg) ->
            list.each(msg.content, fn(c) {
              case c {
                resp.OutputMessageOutputText(text) -> io.println(text.text)
                _ -> Nil
              }
            })
          _ -> Nil
        }
      })
    }
  }
}

/// Decode the JSON arguments from the function call and return a fake
/// weather result as a string.
fn check_weather_from_args(args_json: String) -> String {
  let location_decoder = {
    use loc <- decode.field("location", decode.string)
    decode.success(loc)
  }
  let units_decoder = {
    use u <- decode.field("units", decode.string)
    decode.success(u)
  }

  let location = case json.parse(args_json, location_decoder) {
    Ok(loc) -> loc
    Error(_) -> "unknown"
  }
  let units = case json.parse(args_json, units_decoder) {
    Ok(u) -> u
    Error(_) -> "celsius"
  }

  "The weather in " <> location <> " is " <> int.to_string(25) <> " " <> units
}
