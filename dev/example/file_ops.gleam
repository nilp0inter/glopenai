// Demonstrates the Files API: list, retrieve, and delete files.
//
// Unlike the Rust examples which embed file operations inside assistant
// workflows, this example focuses on the file management operations
// themselves: listing available files, retrieving metadata for a specific
// file, and deleting it.
//
// Run with: gleam run -m example/file_ops

import example/env
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/httpc
import glopenai/config
import glopenai/file

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // List all files
  io.println("--- Listing files ---")
  let list_req = file.list_request(cfg)
  let assert Ok(http_response) = httpc.send(list_req)
  let assert Ok(files) = file.list_response(http_response)

  io.println("Found " <> int.to_string(list.length(files.data)) <> " files")
  io.println("Has more: " <> bool.to_string(files.has_more))

  list.each(files.data, fn(f) {
    io.println(
      "  - " <> f.filename
      <> " (id: " <> f.id
      <> ", bytes: " <> int.to_string(f.bytes)
      <> ", purpose: " <> purpose_to_string(f.purpose) <> ")",
    )
  })

  // Retrieve the first file if any exist
  case files.data {
    [first, ..] -> {
      io.println("\n--- Retrieving file: " <> first.id <> " ---")
      let retrieve_req = file.retrieve_request(cfg, first.id)
      let assert Ok(http_response) = httpc.send(retrieve_req)
      let assert Ok(f) = file.retrieve_response(http_response)

      io.println("  id: " <> f.id)
      io.println("  filename: " <> f.filename)
      io.println("  bytes: " <> int.to_string(f.bytes))
      io.println("  created_at: " <> int.to_string(f.created_at))
      io.println("  purpose: " <> purpose_to_string(f.purpose))
    }
    [] -> io.println("\nNo files to retrieve.")
  }
}

fn purpose_to_string(purpose: file.OpenAiFilePurpose) -> String {
  case purpose {
    file.Assistants -> "assistants"
    file.AssistantsOutput -> "assistants_output"
    file.Batch -> "batch"
    file.BatchOutput -> "batch_output"
    file.FineTune -> "fine-tune"
    file.FineTuneResults -> "fine-tune-results"
    file.Vision -> "vision"
    file.UserData -> "user_data"
  }
}
