// Port of: examples/responses/
//
// Basic Responses API usage with multiple input prompts and a web search tool.
//
// Run with: gleam run -m example/response

import example/env
import gleam/httpc
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import glaoi/config
import glaoi/response as resp

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  let request =
    resp.new_create_response(input: resp.InputText(
      "What is MCP? Also, what transport protocols does it support?",
    ))
    |> resp.with_model("gpt-4.1")
    |> resp.with_max_output_tokens(512)
    |> resp.with_text(resp.ResponseTextParam(
      format: resp.TextFormatText,
      verbosity: Some(resp.VerbosityMedium),
    ))
    |> resp.with_tools([
      resp.ToolWebSearchPreview(resp.WebSearchTool(
        filters: None,
        user_location: None,
        search_context_size: None,
        search_content_types: None,
      )),
    ])

  let http_request = resp.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = resp.create_response_response(http_response)

  io.println("\nResponse output items:")
  list.each(response.output, fn(item) {
    case item {
      resp.OutputItemMessage(msg) -> {
        io.println("\n[message]")
        list.each(msg.content, fn(content) {
          case content {
            resp.OutputMessageOutputText(text) -> io.println(text.text)
            resp.OutputMessageRefusal(refusal) ->
              io.println("(refusal) " <> refusal.refusal)
          }
        })
      }
      resp.OutputItemWebSearchCall(call) -> {
        io.println("\n[web_search_call] id=" <> call.id)
      }
      resp.OutputItemReasoning(_) -> io.println("\n[reasoning]")
      _ -> io.println("\n[other output item]")
    }
  })
}
