# glaoi

Sans-IO OpenAI API client for Gleam, ported from the `async-openai` Rust
library in the parent directory.

## Build and test

```sh
cd glaoi
gleam build
gleam test
```

All code must compile with zero warnings. Run `gleam test` after every change.

## Architecture

### Sans-IO pattern

This library does **not** send HTTP requests. Each API endpoint exposes a
pair of functions:

- `*_request(config, params) -> Request(String)` — builds the HTTP request
- `*_response(response) -> Result(T, GlaoiError)` — parses the HTTP response

Users bring their own HTTP client (httpc, hackney, fetch, etc.) and call it
between the request and response functions.

### Module layout

- **One file per API domain** — all types, encoders, decoders, and
  request/response functions live in the same module (e.g. `chat.gleam`).
  Do not split into sub-modules.
- `internal.gleam` + `internal/codec.gleam` — private helpers, not part of
  the public API
- `shared.gleam` — types used across multiple API modules
- `glaoi.gleam` — re-exports of `Config`, `AzureConfig`, `GlaoiError`,
  `ApiError` for convenience

### Adding a new API module

1. Read the corresponding Rust types in `../async-openai/src/types/<module>/`
2. Create `src/glaoi/<module>.gleam` with:
   - All types as Gleam custom types
   - `*_to_json` encoder for each type
   - `*_decoder` decoder for each type
   - `*_request` / `*_response` function pairs for each endpoint
   - Builder: `new_create_request(required_fields)` + `with_*()` fns
3. Create `test/glaoi/<module>_test.gleam` with:
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

### Gleam gotchas

- **Reserved keywords** — `echo` and `type` are Gleam keywords and cannot be
  used as record field names. When a Rust field uses one of these names, rename
  it (e.g. `echo` → `echo_prompt`, `type` → `item_type`/`message_type`) and
  map back to the original wire name in the encoder/decoder. Leave a comment
  explaining the rename.
- **Reserved field-name example**: `completion.CreateCompletionRequest`
  declares `echo_prompt: Option(Bool)` but the encoder writes the field as
  `"echo"` to match the OpenAI wire format.

### Streaming (SSE) APIs

The Responses and Chat Completions APIs support server-sent events. glaoi
exposes a single sans-io helper per module:

- `chat.parse_stream_chunk(data: String) -> Result(Option(CreateChatCompletionStreamResponse), GlaoiError)`
- `response.parse_stream_event(data: String) -> Result(Option(ResponseStreamEvent), GlaoiError)`

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

`glaoi/response.gleam` declares a `Response` type. Callers that also import
`gleam/http/response` should alias one of them:

```gleam
import gleam/http/response
import glaoi/response as resp

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

`GlaoiError` has three variants:
- `ApiResponseError(status, ApiError)` — API returned an error body
- `JsonDecodeError(body, json.DecodeError)` — response couldn't be decoded
- `UnexpectedResponse(status, body)` — non-2xx with no parseable error

`internal.parse_response` handles all three cases automatically.

## Reference

The Rust source of truth is in `../async-openai/src/`. Key locations:

- Types: `async-openai/src/types/<module>/`
- Config: `async-openai/src/config.rs`
- Errors: `async-openai/src/error.rs`
- API implementations: `async-openai/src/<module>.rs`

See `PLAN.md` for the full implementation roadmap and status.
