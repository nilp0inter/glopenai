# glopenai

Sans-IO OpenAI API client for Gleam, ported from the `async-openai` Rust
library in the parent directory.

## Build and test

```sh
cd glopenai
gleam build
gleam test
```

All code must compile with zero warnings. Run `gleam test` after every change.

## Architecture

### Sans-IO pattern

This library does **not** send HTTP requests. Each API endpoint exposes a
pair of functions:

- `*_request(config, params) -> Request(String)` — builds the HTTP request
- `*_response(response) -> Result(T, GlopenaiError)` — parses the HTTP response

Users bring their own HTTP client (httpc, hackney, fetch, etc.) and call it
between the request and response functions.

Multipart endpoints (file/upload) deviate slightly: they return
`Request(BitArray)` because file payloads are binary. See **Multipart bodies**
below.

Some helpers that classically depend on the system clock (e.g.
`webhook.verify_signature`) take an explicit `now: Int` argument so the
function stays sans-IO and reproducible. Callers pass
`erlang:system_time(seconds)` (or whatever clock they trust).

### Module layout

- **One file per API domain** — all types, encoders, decoders, and
  request/response functions live in the same module (e.g. `chat.gleam`).
  Do not split into sub-modules.
- `internal.gleam` + `internal/codec.gleam` — private helpers, not part of
  the public API
- `shared.gleam` — types used across multiple API modules
- `glopenai.gleam` — re-exports of `Config`, `AzureConfig`, `GlopenaiError`,
  `ApiError` for convenience

### Adding a new API module

1. Read the corresponding Rust types in `../async-openai/src/types/<module>/`
2. Create `src/glopenai/<module>.gleam` with:
   - All types as Gleam custom types
   - `*_to_json` encoder for each type
   - `*_decoder` decoder for each type
   - `*_request` / `*_response` function pairs for each endpoint
   - Builder: `new_create_request(required_fields)` + `with_*()` fns
3. Create `test/glopenai/<module>_test.gleam` with:
   - Roundtrip JSON encoding/decoding tests
   - Request building tests (method, path, headers)
   - Response parsing tests (success + error cases)
4. Update `PLAN.md` to mark the module as done

### Conventions

Follow the Gleam skill strictly. Key rules:

- **Qualified imports** for functions and constants — never unqualified
- **Annotate all functions** with argument types and return type
- **Result for errors** — never panic, never Option for errors
- **Singular module names** — `model.gleam` not `models.gleam`
- **Comments** — explain what and why, especially for non-obvious decoder logic
- **No abbreviations** — write names in full
- Encoder naming: `thing_to_json(thing) -> json.Json`
- Decoder naming: `thing_decoder() -> decode.Decoder(Thing)`
- Builder naming: `new_create_request(required_fields) -> Request` then
  `with_field(request, value) -> Request`

### JSON encoding/decoding

- Use `gleam_json` (`json.parse` to decode, `json.to_string` to encode)
- Use `gleam/dynamic/decode` for decoders
- Optional fields in requests: use `codec.optional_field` to omit when `None`
- Optional fields in responses: use `decode.optional_field` with `None` default
- Tagged enums (`#[serde(tag = "type")]`): read the tag field, then `case` dispatch
- Untagged enums (`#[serde(untagged)]`): use `decode.one_of`
- String enums (`#[serde(rename_all)]`): `case` on the string value
- **`decode.at(path, decoder)` can't be used with `use <-`** — it takes exactly
  two arguments, so `use x <- decode.at(["a", "b"], decoder)` fails at compile
  time. For nested field access, factor out a sub-decoder and use
  `decode.field(outer, sub_decoder())` with a chain of `decode.field` calls
  inside.
- **`#[serde(flatten)]` on a tagged enum** — the variant's discriminator and
  payload are spread directly onto the parent JSON object. Decode by reading
  the parent's other fields first, then chaining `decode.then(child_decoder())`
  so the child decoder runs against the same root. Example:
  `chatkit.thread_resource_decoder` decodes `id`/`object`/`created_at`/`title`
  via `decode.field`, then does `use status <- decode.then(thread_status_decoder())`
  to consume the flattened `type`/`reason` fields.

### Gleam gotchas

- **Reserved keywords** — `echo` and `type` are Gleam keywords and cannot be
  used as record field names. When a Rust field uses one of these names, rename
  it (e.g. `echo` → `echo_prompt`, `type` → `item_type`/`message_type`) and
  map back to the original wire name in the encoder/decoder. Leave a comment
  explaining the rename.
- **Reserved field-name example**: `completion.CreateCompletionRequest`
  declares `echo_prompt: Option(Bool)` but the encoder writes the field as
  `"echo"` to match the OpenAI wire format.

### Multipart bodies

For endpoints that take binary uploads (`file.create_request`,
`upload.add_part_request`, future audio transcription / image edit / video
upload / skill upload / container upload):

- Build via `internal.multipart_request(config, method, path, parts, boundary)`,
  which returns `Request(BitArray)`.
- `MultipartPart` has two constructors: `FieldPart(name, value)` for plain
  text fields and `FilePart(name, filename, content_type, data)` for the
  bytes payload.
- `boundary` is a caller-supplied string. Pick a long random or
  content-derived value; it must not appear inside any part body. Sans-IO
  callers pass it explicitly so requests are reproducible.
- For non-string field values, encode to string in the caller (see the
  `expires_after[anchor]` / `expires_after[seconds]` pattern in
  `file.create_request`).
- **Sending side**: use `httpc.send_bits` (not `httpc.send`). It returns
  `Response(BitArray)`.
- **Parsing side**: the `*_response` parsers all expect `Response(String)`
  because OpenAI returns JSON. Convert with a small helper:
  ```gleam
  fn bits_response_to_string(
    resp: response.Response(BitArray),
  ) -> response.Response(String) {
    let body = case bit_array.to_string(resp.body) {
      Ok(s) -> s
      Error(_) -> ""
    }
    response.Response(status: resp.status, headers: resp.headers, body: body)
  }
  ```
  See `dev/example/vector_store_retrieval.gleam` for the full pattern.

### Pagination queries

List endpoints that accept query parameters expose two builders:

- `list_request(config) -> Request(String)` — no query, all defaults.
- `list_request_with_query(config, query) -> Request(String)` — apply the
  given `*Query` record.

Each module declares its own `*Query` record (see
`vector_store.ListVectorStoresQuery`, `chatkit.ListChatKitThreadsQuery`).
Order/filter enums are also per-module to keep variant names short
(e.g. `vector_store.Asc`, `chatkit.ThreadsAsc`). Internally each module has
a private `optional_string_pair` helper plus a `*_query_pairs` function
that flattens the query into `List(#(String, String))` for
`request.set_query`. If a third module needs the same shape, promote
`optional_string_pair` to `internal/codec.gleam`.

### Streaming (SSE) APIs

The Responses and Chat Completions APIs support server-sent events. glopenai
exposes a single sans-io helper per module:

- `chat.parse_stream_chunk(data: String) -> Result(Option(CreateChatCompletionStreamResponse), GlopenaiError)`
- `response.parse_stream_event(data: String) -> Result(Option(ResponseStreamEvent), GlopenaiError)`

Both return `Ok(None)` for the literal `[DONE]` sentinel line and `Ok(Some(_))`
for a parsed data payload. The user is responsible for reading the HTTP body
as a stream, splitting it on blank lines, and stripping the `data: ` prefix
before passing each payload to the parser. See `dev/example/response_stream.gleam`
for a reference implementation (buffered-body variant).

### POST endpoints with empty bodies

Some endpoints (cancel, pause, resume) require a POST with an empty JSON
object as the body. Use `json.object([])`:

```gleam
internal.post_request(
  config,
  "/fine_tuning/jobs/" <> job_id <> "/cancel",
  json.object([]),
)
```

### Module naming and import collisions

`glopenai/response.gleam` declares a `Response` type. Callers that also import
`gleam/http/response` should alias one of them:

```gleam
import gleam/http/response
import glopenai/response as resp

pub fn handle(http_resp: response.Response(String)) {
  resp.create_response_response(http_resp)
}
```

Inside `response.gleam` itself, the collision is resolved by aliasing only
the imported `Response` *type*, not the module:

```gleam
import gleam/http/response.{type Response as HttpResponse}
```

This keeps the module's own `Response` type unqualified while still allowing
the HTTP response type to be referred to as `HttpResponse(String)`.

### Known OpenAI API wire-shape quirks

The Chat Completions API and the Responses API use **different JSON shapes**
for the same conceptual payload. These are the ones we've hit:

- **JSON-schema response format** — in Chat Completions, the schema is nested
  under a `json_schema` key:
  ```json
  { "type": "json_schema", "json_schema": { "name": "...", "schema": {...} } }
  ```
  In the Responses API (`text.format`), the schema fields are **flattened**
  alongside the type tag:
  ```json
  { "type": "json_schema", "name": "...", "schema": {...}, "strict": true }
  ```
  The `shared.ResponseFormatJsonSchema` type is used for both, but the
  encoders differ: `shared.response_format_json_schema_to_json` nests for Chat,
  `response.text_response_format_to_json` flattens for Responses.
- **`CompletionUsage` vs `ResponseUsage`** — Chat-style endpoints return
  `prompt_tokens`/`completion_tokens`/`total_tokens`; Responses-style endpoints
  return `input_tokens`/`output_tokens`/`total_tokens` with nested
  `input_tokens_details.cached_tokens` and `output_tokens_details.reasoning_tokens`.
  Both live in `shared.gleam`; pick the right one for the module you're
  porting.

### Type mapping from Rust

| Rust | Gleam |
|------|-------|
| `Option<T>` | `Option(a)` |
| `Vec<T>` | `List(a)` |
| `HashMap<String, T>` | `Dict(String, a)` |
| `serde_json::Value` | `Dynamic` (decode side) |
| `u32` / `i64` | `Int` |
| `f32` / `f64` | `Float` |
| `Metadata` | `Dict(String, String)` |
| Deprecated fields | Omit unless needed for wire compat |

### Error handling

`GlopenaiError` has three variants:
- `ApiResponseError(status, ApiError)` — API returned an error body
- `JsonDecodeError(body, json.DecodeError)` — response couldn't be decoded
- `UnexpectedResponse(status, body)` — non-2xx with no parseable error

`internal.parse_response` handles all three cases automatically.

### FFI modules

Tiny Erlang shims live alongside the Gleam source under `src/`:

- `glopenai_codec_ffi.erl` — `dynamic_to_json/1` (re-encode a decoded `Dynamic`)
- `glopenai_webhook_ffi.erl` — `hmac_sha256/2`, `base64_encode/1`,
  `base64_decode/1`. Used by `webhook.gleam`.

Add new FFIs as standalone `glopenai_*_ffi.erl` files. Keep them tiny; do all
data shaping on the Gleam side.

## Reference

The Rust source of truth is in `../async-openai/src/`. Key locations:

- Types: `../async-openai/src/types/<module>/`
- Config: `../async-openai/src/config.rs`
- Errors: `../async-openai/src/error.rs`
- API implementations: `../async-openai/src/<module>.rs`

**Repo layout gotcha**: example code (and example fixtures like the
vector-store-retrieval PDFs) lives at `../examples/`, **not** under
`../async-openai/examples/`. The `async-openai/` directory is the Rust
library crate only. Relative paths from a glopenai example file should target
`../examples/...` if you need them — but prefer copying fixtures into
`dev/example/input/<example-name>/` so glopenai stays self-contained.

See `PLAN.md` for the full implementation roadmap and status.
