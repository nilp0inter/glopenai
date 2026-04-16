// Port of: examples/vector-store-retrieval/src/main.rs
//
// 1. Upload two PDFs (uber-10k.pdf, lyft-10k.pdf) for use with Assistants.
// 2. Create a vector store containing both files.
// 3. Wait for the vector store to finish indexing.
// 4. Search "uber profit".
// 5. Clean up: delete the vector store and both files.
//
// The PDFs are committed under `dev/example/input/vector_store_retrieval/`
// so this example is self-contained. Paths are relative to the project root,
// which is the working directory used by `gleam run`.
//
// Run with:
//   export OPENAI_API_KEY=...
//   gleam run -m example/vector_store_retrieval

import example/env
import gleam/bit_array
import gleam/bool
import gleam/float
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glaoi/config
import glaoi/file
import glaoi/vector_store as vs

const uber_path = "dev/example/input/vector_store_retrieval/uber-10k.pdf"

const lyft_path = "dev/example/input/vector_store_retrieval/lyft-10k.pdf"

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // ---- Step 1: upload both PDFs ----

  io.println("Uploading uber-10k.pdf...")
  let uber_file = upload_pdf(cfg, uber_path, "uber-10k.pdf", "boundary-uber-9f3e2c1a")
  io.println("  Uploaded: " <> uber_file.id)

  io.println("Uploading lyft-10k.pdf...")
  let lyft_file = upload_pdf(cfg, lyft_path, "lyft-10k.pdf", "boundary-lyft-7b1d8e4f")
  io.println("  Uploaded: " <> lyft_file.id)

  // ---- Step 2: create vector store containing both files ----

  io.println("\nCreating vector store with both files...")
  let create_req =
    vs.create_request(
      cfg,
      vs.new_create_request()
        |> vs.with_name("Financial Statements")
        |> vs.with_file_ids([uber_file.id, lyft_file.id]),
    )
  let assert Ok(create_http) = httpc.send(create_req)
  let assert Ok(initial_store) = vs.create_response(create_http)
  io.println("  Vector store created: " <> initial_store.id)

  // ---- Step 3: poll until ingestion completes ----

  let store = wait_for_completion(cfg, initial_store)
  io.println(
    "  Status: completed ("
    <> int.to_string(store.file_counts.completed)
    <> " of "
    <> int.to_string(store.file_counts.total)
    <> " files)",
  )

  // ---- Step 4: run a search ----

  io.println("\nSearching for \"uber profit\"...")
  let search_req =
    vs.search_request(
      cfg,
      store.id,
      vs.new_search_request(vs.TextQuery("uber profit")),
    )
  let assert Ok(search_http) = httpc.send(search_req)
  let assert Ok(results) = vs.search_response(search_http)
  print_search_results(results)

  // ---- Step 5: cleanup ----

  io.println("\nCleaning up...")
  let _ = delete_vector_store(cfg, store.id)
  let _ = delete_file(cfg, uber_file.id)
  let _ = delete_file(cfg, lyft_file.id)
  io.println("Done.")
}

// --- Helpers ---

fn upload_pdf(
  cfg: config.Config,
  path: String,
  filename: String,
  boundary: String,
) -> file.OpenAiFile {
  let assert Ok(bytes) = read_file(path)
  let req =
    file.create_request(
      cfg,
      file.new_create_request(filename, bytes, file.Assistants),
      boundary,
    )
  // The body is a BitArray (multipart). Use httpc.send_bits, then convert
  // the JSON response body back to a String for the parser.
  let assert Ok(http_resp) = httpc.send_bits(req)
  let assert Ok(uploaded) = file.create_response(bits_response_to_string(http_resp))
  uploaded
}

fn bits_response_to_string(
  resp: response.Response(BitArray),
) -> response.Response(String) {
  // The OpenAI Files endpoint returns JSON text, so the body is always valid
  // UTF-8 on success. On error responses it's also UTF-8 JSON.
  let body = case bit_array.to_string(resp.body) {
    Ok(s) -> s
    Error(_) -> ""
  }
  response.Response(status: resp.status, headers: resp.headers, body: body)
}

fn wait_for_completion(
  cfg: config.Config,
  store: vs.VectorStoreObject,
) -> vs.VectorStoreObject {
  case store.status {
    vs.StoreCompleted -> store
    _ -> {
      io.println("  Waiting for vector store to be ready...")
      sleep_ms(5000)
      let req = vs.retrieve_request(cfg, store.id)
      let assert Ok(http_resp) = httpc.send(req)
      let assert Ok(refreshed) = vs.retrieve_response(http_resp)
      wait_for_completion(cfg, refreshed)
    }
  }
}

fn print_search_results(page: vs.VectorStoreSearchResultsPage) -> Nil {
  io.println(
    "  " <> int.to_string(list.length(page.data)) <> " result(s):",
  )
  list.each(page.data, fn(item) {
    io.println(
      "    "
      <> item.filename
      <> " (file_id="
      <> item.file_id
      <> ", score="
      <> float.to_string(item.score)
      <> ")",
    )
    list.each(item.content, fn(chunk) {
      let snippet = case string.length(chunk.text) > 200 {
        True -> string.slice(chunk.text, 0, 200) <> "..."
        False -> chunk.text
      }
      io.println("      " <> snippet)
    })
  })
  io.println("  has_more: " <> bool.to_string(page.has_more))
  case page.next_page {
    Some(token) -> io.println("  next_page: " <> token)
    None -> Nil
  }
}

fn delete_vector_store(cfg: config.Config, id: String) -> Nil {
  let req = vs.delete_request(cfg, id)
  case httpc.send(req) {
    Ok(http_resp) ->
      case vs.delete_response(http_resp) {
        Ok(result) ->
          io.println(
            "  Deleted vector store " <> result.id
            <> ": " <> bool.to_string(result.deleted),
          )
        Error(_) -> io.println("  (failed to parse delete response)")
      }
    Error(_) -> io.println("  (HTTP error deleting vector store)")
  }
}

fn delete_file(cfg: config.Config, id: String) -> Nil {
  let req = file.delete_request(cfg, id)
  case httpc.send(req) {
    Ok(http_resp) ->
      case file.delete_response(http_resp) {
        Ok(result) ->
          io.println(
            "  Deleted file " <> result.id
            <> ": " <> bool.to_string(result.deleted),
          )
        Error(_) -> io.println("  (failed to parse delete response)")
      }
    Error(_) -> io.println("  (HTTP error deleting file)")
  }
}

@external(erlang, "example_file_ffi", "read_file")
fn read_file(path: String) -> Result(BitArray, a)

@external(erlang, "example_file_ffi", "sleep_ms")
fn sleep_ms(millis: Int) -> Nil
