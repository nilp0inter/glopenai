// Port of: examples/azure-openai-service/
//
// Chat completion and embeddings using Azure OpenAI Service.
//
// Run with: gleam run -m example/azure
//
// Set your Azure credentials before running.

import gleam/int
import gleam/io
import gleam/string
import gleam/list
import gleam/httpc
import gleam/option.{Some}
import glaoi/chat
import glaoi/config
import glaoi/embedding
import glaoi/internal

pub fn main() -> Nil {
  // Configure for Azure OpenAI Service
  let azure =
    config.new_azure(
      api_base: "https://your-resource-name.openai.azure.com",
      api_key: "your-azure-api-key",
      deployment_id: "your-deployment-id",
      api_version: "2024-02-01",
    )

  io.println("=== Chat Completion (Azure) ===\n")
  chat_completion_example(azure)

  io.println("\n=== Embeddings (Azure) ===\n")
  embedding_example(azure)
}

fn chat_completion_example(azure: config.AzureConfig) -> Nil {
  let request =
    chat.new_create_request(model: "gpt-4o", messages: [
      chat.system_message("You are a helpful assistant."),
      chat.user_message("How does large language model work?"),
    ])
    |> chat.with_max_completion_tokens(512)

  // Build an Azure request (uses different URL scheme and auth header)
  let http_request =
    internal.azure_post_request(
      azure,
      "/chat/completions",
      chat.create_chat_completion_request_to_json(request),
    )

  case httpc.send(http_request) {
    Ok(http_response) ->
      case chat.create_response(http_response) {
        Ok(response) ->
          case response.choices {
            [choice, ..] ->
              case choice.message.content {
                Some(content) -> io.println(content)
                _ -> io.println("(no content)")
              }
            [] -> io.println("(no choices)")
          }
        Error(err) -> {
          io.println("API error:")
          io.println(string.inspect(err))
          Nil
        }
      }
    Error(err) -> {
      io.println("HTTP error:")
      io.println(string.inspect(err))
      Nil
    }
  }
}

fn embedding_example(azure: config.AzureConfig) -> Nil {
  let request =
    embedding.new_create_request(
      model: "text-embedding-ada-002",
      input: embedding.StringInput(
        "Why do programmers hate nature? It has too many bugs.",
      ),
    )

  let http_request =
    internal.azure_post_request(
      azure,
      "/embeddings",
      embedding.create_embedding_request_to_json(request),
    )

  case httpc.send(http_request) {
    Ok(http_response) ->
      case embedding.create_response(http_response) {
        Ok(response) ->
          list.each(response.data, fn(data) {
            io.println(
              "[" <> int.to_string(data.index) <> "]: has embedding of length "
              <> int.to_string(list.length(data.embedding)),
            )
          })
        Error(err) -> {
          io.println("API error:")
          io.println(string.inspect(err))
          Nil
        }
      }
    Error(err) -> {
      io.println("HTTP error:")
      io.println(string.inspect(err))
      Nil
    }
  }
}
