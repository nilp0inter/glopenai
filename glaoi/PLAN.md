# glaoi — Port of async-openai to Gleam

Sans-IO OpenAI API client for Gleam. Builds HTTP requests without sending
them, parses HTTP responses without receiving them. Users bring their own
HTTP client.

## Design principles

- **Sans-IO**: each endpoint exposes `*_request` → `Request(String)` and
  `*_response` → `Result(T, GlaoiError)` function pairs
- **Type fidelity**: port types as closely as possible to the Rust library
- **Gleam conventions**: qualified imports, snake_case, PascalCase types,
  `Result` for errors, no panics, singular module names, no fragmented modules
- **One file per API domain**: all types and request/response functions live
  together (e.g. `chat.gleam` contains types, encoders, decoders, and
  request/response builders)

## Type mapping (Rust → Gleam)

| Rust | Gleam |
|------|-------|
| `Option<T>` | `Option(a)` |
| `Vec<T>` | `List(a)` |
| `HashMap<String, T>` | `Dict(String, a)` |
| `#[serde(rename_all)]` enum | Custom type + string encoder/decoder |
| `#[serde(tag = "type")]` tagged enum | Custom type + tag-dispatched decoder |
| `#[serde(untagged)]` enum | Custom type + `decode.one_of` |
| Builder (`derive_builder`) | `new()` with required args + `with_*()` chainable fns |
| `serde_json::Value` | `Dynamic` (decode) / inline `json.Json` (encode) |
| `Metadata` | `Dict(String, String)` |

## Dependencies

```toml
gleam_stdlib >= 0.44.0
gleam_json   >= 3.1.0
gleam_http   >= 4.3.0
gleeunit     >= 1.0.0   (dev)
```

No HTTP client dependency.

---

## Progress

### Phase 1 — Core infrastructure + 3 APIs ✅ DONE

| File | Status | What it contains |
|------|--------|------------------|
| `src/glaoi.gleam` | ✅ | Re-exports: `Config`, `AzureConfig`, `GlaoiError`, `ApiError` |
| `src/glaoi/config.gleam` | ✅ | `Config` + `AzureConfig` records, builder fns (`new`, `with_api_base`, `with_org_id`, `with_project_id`, `with_header`, `new_azure`) |
| `src/glaoi/error.gleam` | ✅ | `ApiError`, `GlaoiError` types, `api_error_decoder`, `wrapped_error_decoder`, `api_error_to_json` |
| `src/glaoi/internal.gleam` | ✅ | `post_request`, `get_request`, `delete_request`, `parse_response`, Azure variants, URL parsing, config header stamping |
| `src/glaoi/internal/codec.gleam` | ✅ | `optional_field`, `nullable_field`, `object_with_optional` JSON helpers |
| `src/glaoi/shared.gleam` | ✅ | `ImageDetail`, `ImageUrl`, `FunctionObject`, `FunctionCall`, `FunctionName`, `ReasoningEffort`, `ResponseFormat`, `ResponseFormatJsonSchema`, `CompletionUsage`, `PromptTokensDetails`, `CompletionTokensDetails`, `ResponseUsage`, `InputTokenDetails`, `OutputTokenDetails` — all with encoders + decoders |
| `src/glaoi/model.gleam` | ✅ | `Model`, `ListModelResponse`, `DeleteModelResponse` types + `list_request/response`, `retrieve_request/response`, `delete_request/response` |
| `src/glaoi/embedding.gleam` | ✅ | `EmbeddingInput` (4 variants), `EncodingFormat`, `CreateEmbeddingRequest` + builder, `Embedding`, `EmbeddingUsage`, `CreateEmbeddingResponse` + `create_request/response` |
| `src/glaoi/chat.gleam` | ✅ | Full chat completions API — messages (Developer/System/User/Assistant/Tool), content parts (text/image_url/input_audio/file), tool types, tool choice, web search options, stream options, stop config, service tier, verbosity, modalities, `CreateChatCompletionRequest` + builder (13 `with_*` fns), response types, stream types (`ChatCompletionStreamDelta`, `ChatChoiceStream`, `CreateChatCompletionStreamResponse`), `parse_stream_chunk`, CRUD request/response pairs — all with encoders + decoders |
| `test/glaoi/config_test.gleam` | ✅ | 5 tests: config construction, builder, GET/POST/DELETE request building |
| `test/glaoi/model_test.gleam` | ✅ | 5 tests: list/retrieve/delete response decoding, API error, unexpected response |
| `test/glaoi/embedding_test.gleam` | ✅ | 3 tests: request encoding, response decoding, array input encoding |
| `test/glaoi/chat_test.gleam` | ✅ | 10 tests: request encoding, tool messages, tool choice, response decoding, tool calls, stream chunks, [DONE] sentinel, list/delete responses, API errors |

**Stats**: ~2500 lines of Gleam, 23 tests passing, 0 warnings.

#### Examples (Phase 1)

| File | Ports from | Status |
|------|-----------|--------|
| `dev/example/chat.gleam` | `examples/chat/` | ✅ |
| `dev/example/chat_store.gleam` | `examples/chat-store/` | ✅ |
| `dev/example/embedding.gleam` | `examples/embeddings/` | ✅ |
| `dev/example/model.gleam` | `examples/models/` | ✅ |
| `dev/example/structured_output.gleam` | `examples/structured-outputs/` | ✅ |
| `dev/example/vision_chat.gleam` | `examples/vision-chat/` | ✅ |
| `dev/example/web_search.gleam` | `examples/web-search/` | ✅ |
| `dev/example/tool_call.gleam` | `examples/tool-call/` | ✅ |
| `dev/example/azure.gleam` | `examples/azure/` | ✅ (requires Azure credentials) |
| `dev/example/ollama_chat.gleam` | `examples/ollama-chat/` | ✅ (requires Ollama) |
| `dev/example/env.gleam` | — | ✅ Shared helper: `OPENAI_API_KEY` loader |

---

### Phase 2 — Moderation, Image, Audio, File ✅ DONE

Each module follows the same pattern: types + encoders + decoders + request/response pairs.

| File | Status | What it contains |
|------|--------|------------------|
| `src/glaoi/moderation.gleam` | ✅ | `ModerationInput` (String/Array/MultiModal), `ModerationContentPart` (Text/ImageUrl), `ModInputType`, `Categories` (13 bool fields), `CategoryScore` (13 float fields), `CategoryAppliedInputTypes`, `ContentModerationResult`, `CreateModerationRequest` + builder, `CreateModerationResponse` + `create_request/response` — all with encoders + decoders |
| `src/glaoi/image.gleam` | ✅ | `ImageSize` (8 variants), `ImageModel` (5 named + Other), `ImageQuality` (6 variants), `ImageStyle`, `ImageModeration`, `ImageOutputFormat`, `ImageResponseFormat`, `ImageBackground`, `Image` (Url/B64Json), `ImageGenUsage` + detail types, `ImagesResponse`, `CreateImageRequest` + builder (11 `with_*` fns) + `create_request/response` — all with encoders + decoders. Edit/variation deferred (multipart). |
| `src/glaoi/audio.gleam` | ✅ | `Voice` (13 built-in + Custom + Other), `SpeechResponseFormat` (6 variants), `SpeechModel` (3 named + Other), `StreamFormat`, `CreateSpeechRequest` + builder (4 `with_*` fns) + `create_speech_request/response` — all with encoders + decoders. Speech returns raw audio bytes. Transcription/translation deferred (multipart). |
| `src/glaoi/file.gleam` | ✅ | `OpenAiFilePurpose` (8 variants), `OpenAiFile`, `FileExpirationAfter`/`FileExpirationAfterAnchor` (added Phase 4), `CreateFileRequest` + builder + `create_request/response` (multipart, added Phase 4), `ListFilesResponse`, `DeleteFileResponse` + `list_request/response`, `retrieve_request/response`, `delete_request/response`, `content_request/response` — all with encoders + decoders. |
| `test/glaoi/moderation_test.gleam` | ✅ | 5 tests: string input encoding, multimodal encoding, response decoding, API error, array input encoding |
| `test/glaoi/image_test.gleam` | ✅ | 7 tests: request encoding with options, minimal request, HTTP request building, URL response decoding, b64 response decoding, usage decoding, API error |
| `test/glaoi/audio_test.gleam` | ✅ | 6 tests: speech request encoding, minimal encoding, custom voice encoding, HTTP request building, success response, error response |
| `test/glaoi/file_test.gleam` | ✅ | 10 tests: list/retrieve/delete/content request building, list response decoding, pagination, retrieve with expiry, delete response, content success, content error |

**Stats**: ~4200 lines of Gleam, 62 tests passing, 0 warnings.

#### Examples (Phase 2)

| File | Ports from | Status |
|------|-----------|--------|
| `dev/example/moderation.gleam` | `examples/moderations/` | ✅ Single + multi-string moderation |
| `dev/example/image_generate.gleam` | `examples/image-generate/` + `examples/image-generate-b64-json/` | ✅ URL + base64 response formats |
| `dev/example/audio_speech.gleam` | `examples/audio-speech/` | ✅ TTS with binary file saving |
| `dev/example/file_ops.gleam` | File ops from `examples/assistants-*` | ✅ List + retrieve files |
| `dev/example_file_ffi.erl` | — | ✅ Shared FFI: `write_file/2`, `ensure_directory/1` |

**Not ported** (need streaming types not yet in glaoi):
- `examples/image-gen-stream/` — image generation streaming events
- `examples/audio-speech-stream/` — speech streaming events

#### Bug fixes found during example testing

- **`shared.gleam`**: `response_format_json_schema_to_json` was missing the `schema` field, causing structured output requests to fail with `missing_required_parameter`
- **`chat_store.gleam`**: added 5s sleep before retrieve — API has eventual consistency (same as Rust example's `tokio::time::sleep(5s)`)
- **`audio_speech.gleam`**: speech endpoint returns raw binary, must use `httpc.send_bits` + `request.map(bit_array.from_string)` instead of `httpc.send` (which rejects non-UTF-8 response bodies)

**Multipart note**: resolved in Phase 4. `internal.multipart_request` returns
`Request(BitArray)` with a caller-supplied boundary; see CLAUDE.md
"Multipart bodies" for usage. Still deferred (need the same pattern):
audio transcription/translation, image edit/variation, video upload, skill
upload, container upload.

### Phase 3 — Responses API, Fine-tuning, Batch, Completion ✅ DONE

Each module follows the same pattern: types + encoders + decoders + request/response pairs.

| File | Status | What it contains |
|------|--------|------------------|
| `src/glaoi/response.gleam` | ✅ | Full Responses API — `CreateResponse` + builder (20 `with_*` fns), `Response` type, `InputParam`/`InputItem`/`Item` (25 variants), `OutputItem` (20 variants), `Tool` (17 variants), `ToolChoiceParam`, `ResponseStreamEvent` (48 stream event variants), content types, annotations, computer actions, web search actions, MCP types, shell/apply-patch types, reasoning, compaction, `DeleteResponse`, `ResponseItemList`, `TokenCountsResource`, `CompactResource` — all with encoders + decoders + `parse_stream_event` |
| `src/glaoi/fine_tuning.gleam` | ✅ | Fine-tuning jobs API — `NEpochs`/`BatchSize`/`LearningRateMultiplier`/`Beta`/`ComputeMultiplier`/`EvalInterval`/`EvalSamples` (auto-or-value enums), `FineTuneSupervisedHyperparameters`/`FineTuneDpoHyperparameters`/`FineTuneReinforcementHyperparameters`, `FineTuneMethod` (Supervised/Dpo/Reinforcement), `FineTuneGrader` (5 grader types), `CreateFineTuningJobRequest` + builder, `FineTuningJob`, events, checkpoints, checkpoint permissions — 11 endpoints, all with encoders + decoders |
| `src/glaoi/batch.gleam` | ✅ | Batch API — `BatchEndpoint` (5 variants), `BatchStatus` (8 variants), `BatchRequest` + builder, `Batch`, `BatchErrors`, `BatchRequestCounts`, `ListBatchesResponse`, `BatchRequestInput`/`BatchRequestOutput` (JSONL helpers) — create/retrieve/cancel/list endpoints, all with encoders + decoders |
| `src/glaoi/completion.gleam` | ✅ | Legacy completions API — `Prompt` (4 variants), `StopConfiguration`, `CompletionFinishReason`, `Logprobs`, `CompletionChoice`, `CreateCompletionRequest` + builder (15 `with_*` fns), `CreateCompletionResponse` — create endpoint, all with encoders + decoders |
| `test/glaoi/response_test.gleam` | ✅ | 18 tests: request encoding, request building, HTTP method/path, response decoding (message, function_call, reasoning, usage), delete response, API error, 5 stream event tests, tool encoding, include enum encoding |
| `test/glaoi/fine_tuning_test.gleam` | ✅ | 10 tests: request encoding, request/retrieve/cancel building, job decoding, method decoding, list jobs, events, API error, method encoding, checkpoint permission path |
| `test/glaoi/batch_test.gleam` | ✅ | 10 tests: request encoding, request/retrieve/cancel building, batch response, list response, errors, API error, request input/output decoding |
| `test/glaoi/completion_test.gleam` | ✅ | 6 tests: request encoding, array prompt, request building, response decoding, API error, stop configuration |

**Stats (cumulative, end of Phase 3)**: ~14,800 lines of Gleam total
(~10,700 src, ~1,400 tests, ~1,500 dev examples, remainder FFI/config),
108 tests passing, 0 warnings.

#### Examples (Phase 3)

| File | Ports from | Status |
|------|-----------|--------|
| `dev/example/completion.gleam` | `examples/completions/` | ✅ Single + multi-prompt |
| `dev/example/response.gleam` | `examples/responses/` | ✅ Responses API with web search tool |
| `dev/example/response_function_call.gleam` | `examples/responses-function-call/` | ✅ Non-streaming function calling |
| `dev/example/response_stream.gleam` | `examples/responses-stream/` | ✅ SSE parsing with buffered body |
| `dev/example/response_structured_outputs.gleam` | `examples/responses-structured-outputs/` | ✅ JSON schema output (chain-of-thought) |

**Not ported** (Rust lacks a reference example): `batch`, `fine_tuning`. These modules have full unit-test coverage but no runnable example in the upstream repo.

#### Bug fixes found during example testing

- **`response.gleam`**: `text.format` with `json_schema` in the Responses API flattens the schema fields (`name`, `description`, `schema`, `strict`) alongside the type tag. The initial implementation wrongly wrapped them under a `json_schema` key (the shape used by the older Chat Completions API), causing `missing_required_parameter: 'text.format.name'`. Fixed both encoder and decoder.

### Phase 4 — Remaining APIs (partial)

| Module | Rust reference | Status |
|--------|---------------|--------|
| `src/glaoi/webhook.gleam` | `types/webhooks/` | ✅ 15 event types, HMAC-SHA256 verification, build_event |
| `src/glaoi/vector_store.gleam` | `types/vectorstores/` | ✅ Stores + files + batches + search (16 endpoints, Filter, ChunkingStrategy, AttributeValue, paginated queries) |
| `src/glaoi/chatkit.gleam` | `types/chatkit/` | ✅ Sessions + threads + items (6 endpoints, ThreadItem 6-variant union, flattened ThreadStatus) |
| `src/glaoi/upload.gleam` | `types/uploads/` | ✅ create / add_part (multipart) / complete / cancel |
| `src/glaoi/assistant.gleam` | `types/assistants/` | ❌ TODO — Deprecated but still used: assistants, threads, runs, messages, steps |
| `src/glaoi/video.gleam` | `types/videos/` | ❌ TODO — Video generation (Sora): create, edit, extend, remix |
| `src/glaoi/container.gleam` | `types/containers/` | ❌ TODO — Container management |
| `src/glaoi/skill.gleam` | `types/skills/` | ❌ TODO — Skill definitions |
| `src/glaoi/eval.gleam` | `types/evals/` | ❌ TODO — Evaluation framework |
| `src/glaoi/admin.gleam` | `types/admin/` (many subdirs) | ❌ TODO — Administration: users, projects, API keys, audit logs, invites, roles, usage, certificates, groups, rate limits, service accounts |
| `src/glaoi/realtime.gleam` | `types/realtime/` | ❌ TODO — WebSocket real-time API: client/server events, session management. Needs different transport abstraction (not HTTP request/response). |

#### Phase 4 progress notes

**Multipart support** landed alongside `upload.gleam`. `internal.gleam`
exposes `MultipartPart` (FieldPart + FilePart) and
`multipart_request(config, method, path, parts, boundary) -> Request(BitArray)`.
Callers pass an explicit boundary so requests stay reproducible.

**Webhook verification** lives in pure Gleam plus a 3-function Erlang FFI
(`glaoi_webhook_ffi.erl`) for HMAC-SHA256 + base64. `verify_signature` takes
an explicit `now: Int` so the function is sans-IO.

**Pagination queries**: `vector_store` and `chatkit` introduced a per-module
`*Query` record type and a `*_request_with_query` variant of each list
endpoint. Each module currently inlines its own `optional_string_pair`
helper — could be promoted to `internal/codec.gleam` if a third module
needs it.

**File upload** (`file.create_request`/`file.create_response`) was previously
deferred but landed alongside the multipart helper. It builds a multipart
request and returns `Request(BitArray)`; callers send it with
`httpc.send_bits` and convert the JSON response body back to `String` for
the parser. The `file.guess_content_type` helper picks a sensible
`Content-Type` from the filename suffix.

**Cumulative stats** (after webhook + vector_store + chatkit + upload + file
upload + 3 new examples): 181 tests passing, 0 warnings.

#### Examples (Phase 4)

| File | Ports from | Status |
|------|-----------|--------|
| `dev/example/webhook_verify.gleam` | `examples/webhooks/` | ✅ Self-contained: synthesises a signed payload locally, then verifies + parses it. The Rust example needed Axum + ngrok + dashboard config; this version exercises the API surface end-to-end without a server. |
| `dev/example/vector_store_retrieval.gleam` | `examples/vector-store-retrieval/` | ✅ Uploads two PDFs (multipart!) → creates vector store → polls until ready → searches "uber profit" → cleans up. Verified live against the real API. PDF fixtures committed under `dev/example/input/vector_store_retrieval/` so the example is self-contained. |
| `dev/example/chatkit.gleam` | `examples/chatkit/` | ✅ Reads `CHATKIT_WORKFLOW_ID`, sets the `OpenAI-Beta: chatkit_beta=v1` header, creates and cancels a session. Verified live. |

### Phase 5 — Cross-cutting concerns

| Feature | Status |
|---------|--------|
| **Multipart support** | ✅ landed in Phase 4 — `internal.MultipartPart` + `internal.multipart_request`. Used by `file.create_request` and `upload.add_part_request`. |
| **Query parameter encoding** | ✅ partial — per-module `*Query` records + `*_request_with_query` builders for vector_store and chatkit list endpoints. `optional_string_pair` helper is currently inlined per module; promote to `internal/codec.gleam` if a 3rd module needs it. Existing list endpoints in older modules (file, chat completions) don't yet have query variants. |
| **SSE streaming helpers** | ❌ TODO — `parse_sse_line(line: String) -> SseEvent` to help users parse raw SSE. Already have `chat.parse_stream_chunk` and `response.parse_stream_event` as per-module decoders. |
| **Retry guidance** | ❌ TODO — Document recommended retry strategy (exponential backoff, retry on 429/5xx, not on insufficient_quota). User-side since sans-IO. |
| **BYOT (Bring Your Own Types)** | ❌ TODO — Allow passing `Dynamic` / raw JSON instead of typed requests. Low priority. |

---

## Rust modules NOT being ported

| Module | Reason |
|--------|--------|
| `types/mcp/` | Model Context Protocol — niche, internal to OpenAI |
| `types/graders/` | Tightly coupled with evals, port with evals if needed |
| `types/shared/custom_grammar_format_param.rs` | Custom grammar format — niche feature, add when needed |
| ~~`types/shared/filter.rs`~~ | ✅ Ported in Phase 4 as `vector_store.Filter` (kept module-local rather than promoting to `shared.gleam` — only one consumer so far) |
| `types/shared/transcription_usage.rs` | Port with audio module |
| `types/input_source.rs` | File/URL/bytes abstraction — Rust-specific, not needed in Gleam |
| `types/impls.rs` | Rust trait implementations (From, Into) — not applicable |
| `types/metadata.rs` | Simple type alias — using `Dict(String, String)` directly |

---

## File layout (target state)

```
glaoi/
  gleam.toml
  PLAN.md
  CLAUDE.md
  src/
    glaoi.gleam                    # Re-exports
    glaoi_codec_ffi.erl            # Erlang FFI: dynamic_to_json
    glaoi_webhook_ffi.erl          # Erlang FFI: HMAC-SHA256 + base64 (Phase 4)
    glaoi/
      config.gleam                 # Config + AzureConfig
      error.gleam                  # ApiError, GlaoiError
      internal.gleam               # Request building, response parsing,
                                   # multipart helper (Phase 4)
      internal/
        codec.gleam                # JSON encoding helpers
      shared.gleam                 # Cross-module types
      # --- API modules ---
      model.gleam                  # Models API
      embedding.gleam              # Embeddings API
      chat.gleam                   # Chat completions API
      moderation.gleam             # Moderations API          (Phase 2)
      image.gleam                  # Image generation API     (Phase 2)
      audio.gleam                  # Audio API                (Phase 2)
      file.gleam                   # Files API                (Phase 2)
                                   # — upload added Phase 4 (multipart)
      response.gleam               # Responses API            (Phase 3)
      fine_tuning.gleam            # Fine-tuning API          (Phase 3)
      batch.gleam                  # Batch API                (Phase 3)
      completion.gleam             # Legacy completions       (Phase 3)
      upload.gleam                 # Uploads API              (Phase 4 ✅)
      vector_store.gleam           # Vector stores API        (Phase 4 ✅)
      chatkit.gleam                # ChatKit API              (Phase 4 ✅)
      webhook.gleam                # Webhook verification     (Phase 4 ✅)
      assistant.gleam              # Assistants API           (Phase 4 TODO)
      video.gleam                  # Video API                (Phase 4 TODO)
      container.gleam              # Containers API           (Phase 4 TODO)
      skill.gleam                  # Skills API               (Phase 4 TODO)
      eval.gleam                   # Evals API                (Phase 4 TODO)
      admin.gleam                  # Administration API       (Phase 4 TODO)
      realtime.gleam               # Realtime WebSocket API   (Phase 4 TODO)
  test/
    glaoi_test.gleam
    glaoi/
      <one *_test.gleam per src/glaoi/*.gleam module>
  dev/
    example_env_ffi.erl            # FFI: getenv
    example_file_ffi.erl           # FFI: read_file/write_file/sleep_ms
    example/
      <one *.gleam per ported Rust example>
      env.gleam                    # Shared: get_api_key, get_env_var
      input/
        vector_store_retrieval/    # PDF fixtures committed for self-contained runs
          uber-10k.pdf
          lyft-10k.pdf
```
