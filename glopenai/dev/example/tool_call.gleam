// Port of: examples/tool-call/
//
// Function calling: the model decides to call a function, we execute it
// locally, then send the result back for a final answer.
//
// Run with: gleam run -m example/tool_call

import example/env
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/httpc
import gleam/option.{None, Some}
import glopenai/chat
import glopenai/config
import glopenai/shared

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let user_prompt = "What's the weather like in Boston and Atlanta?"

  // Define the weather tool
  let assert Ok(params) =
    json.parse(
      "{
      \"type\": \"object\",
      \"properties\": {
        \"location\": {
          \"type\": \"string\",
          \"description\": \"The city and state, e.g. San Francisco, CA\"
        },
        \"unit\": { \"type\": \"string\", \"enum\": [\"celsius\", \"fahrenheit\"] }
      },
      \"required\": [\"location\", \"unit\"],
      \"additionalProperties\": false
    }",
      decode.dynamic,
    )

  let weather_tool =
    chat.FunctionTool(
      function: shared.FunctionObject(
        name: "get_current_weather",
        description: Some("Get the current weather in a given location"),
        parameters: Some(params),
        strict: Some(True),
      ),
    )

  // Step 1: Send initial request with tools
  let request =
    chat.new_create_request(model: "gpt-4o-mini", messages: [
      chat.user_message(user_prompt),
    ])
    |> chat.with_max_completion_tokens(512)
    |> chat.with_tools([weather_tool])

  let http_request = chat.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = chat.create_response(http_response)

  let assert [choice, ..] = response.choices

  // Step 2: Check if the model wants to call tools
  case choice.message.tool_calls {
    Some(tool_calls) -> {
      io.println("Model requested tool calls:")

      // Execute each tool call and collect results
      let tool_messages =
        tool_calls
        |> list_map(fn(tc) {
          let chat.FunctionToolCall(id, function) = tc
          io.println(
            "  Calling " <> function.name <> "(" <> function.arguments <> ")",
          )
          let result = get_current_weather(function.arguments)
          chat.tool_message(result, id)
        })

      // Step 3: Send results back to the model
      let tool_call_messages =
        list_flatten([
          [chat.user_message(user_prompt)],
          [
            chat.AssistantMessage(
              content: None,
              refusal: None,
              name: None,
              tool_calls: Some(tool_calls),
            ),
          ],
          tool_messages,
        ])

      let followup =
        chat.new_create_request(model: "gpt-4o-mini", messages: tool_call_messages)
        |> chat.with_max_completion_tokens(512)

      let http_request = chat.create_request(cfg, followup)
      let assert Ok(http_response) = httpc.send(http_request)
      let assert Ok(final_response) = chat.create_response(http_response)

      io.println("\nFinal response:")
      case final_response.choices {
        [c, ..] ->
          case c.message.content {
            Some(content) -> io.println(content)
            _ -> io.println("(no content)")
          }
        [] -> io.println("(no choices)")
      }
    }
    None -> {
      // Model responded directly without tool calls
      case choice.message.content {
        Some(content) -> io.println(content)
        _ -> io.println("(no content)")
      }
    }
  }
}

/// Simulated weather function. In a real app this would call a weather API.
fn get_current_weather(args_json: String) -> String {
  let location_decoder = {
    use loc <- decode.field("location", decode.string)
    decode.success(loc)
  }
  let unit_decoder = {
    use u <- decode.field("unit", decode.string)
    decode.success(u)
  }
  let location = case json.parse(args_json, location_decoder) {
    Ok(loc) -> loc
    Error(_) -> "unknown"
  }
  let unit = case json.parse(args_json, unit_decoder) {
    Ok(u) -> u
    Error(_) -> "fahrenheit"
  }

  // Return a fake weather response
  let temperature = 72
  "{\"location\": \""
  <> location
  <> "\", \"temperature\": \""
  <> int.to_string(temperature)
  <> "\", \"unit\": \""
  <> unit
  <> "\", \"forecast\": \"sunny\"}"
}

import gleam/list

fn list_map(items: List(a), f: fn(a) -> b) -> List(b) {
  list.map(items, f)
}

fn list_flatten(items: List(List(a))) -> List(a) {
  list.flatten(items)
}
