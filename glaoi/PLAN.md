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

---

### Phase 2 — Moderation, Image, Audio, File ❌ TODO

Each module follows the same pattern: types + encoders + decoders + request/response pairs.

| Module | Rust reference | Notes |
|--------|---------------|-------|
| `src/glaoi/moderation.gleam` | `types/moderations/moderation.rs` | `ModerationInput` (String/Array/MultiModal), `Categories` (12 bool fields), `CategoryScore` (12 float fields), `CreateModerationRequest` + builder, `CreateModerationResponse`, `ContentModerationResult` |
| `src/glaoi/image.gleam` | `types/images/image.rs`, `form.rs` | `CreateImageRequest` + builder, `ImageSize` (8 variants), `ImageModel`, `ImageQuality`, `ImageStyle`, `ImageResponseFormat`, `Image` (Url/B64Json), generation is JSON POST; edit/variation are multipart (deferred) |
| `src/glaoi/audio.gleam` | `types/audio/audio_.rs`, `form.rs` | Speech: `CreateSpeechRequest` + builder, `Voice`, `SpeechResponseFormat`, `SpeechModel` — JSON POST returning audio bytes. Transcription/translation: multipart (deferred) |
| `src/glaoi/file.gleam` | `types/files/file.rs`, `form.rs`, `api.rs` | `OpenAIFile`, `ListFilesResponse`, `DeleteFileResponse`, `ListFilesQuery`. Upload is multipart (deferred); list/retrieve/delete/content are JSON |

**Multipart note**: APIs requiring file uploads (audio transcription, image edit/variation, file upload) need a different body type. Options:
1. Return `Request(BitArray)` with manually-built multipart body + boundary in content-type
2. Return a `MultipartRequest` record that the user's HTTP client can convert
3. Defer multipart to Phase 4 and only implement JSON endpoints first

### Phase 3 — Responses API, Fine-tuning, Batch ❌ TODO

| Module | Rust reference | Notes |
|--------|---------------|-------|
| `src/glaoi/response.gleam` | `types/responses/` (many files) | The newer unified Responses API. Very large type surface: `Response`, `InputItem` (20+ variants), `OutputContent` (15+ variants), `ResponseStreamEvent` (60+ event types). This is the biggest single module. |
| `src/glaoi/fine_tuning.gleam` | `types/finetuning/fine_tuning.rs` | Fine-tuning jobs: create, list, retrieve, cancel, list events, list checkpoints |
| `src/glaoi/batch.gleam` | `types/batches/batch.rs`, `api.rs` | Batch API: create, retrieve, cancel, list |
| `src/glaoi/completion.gleam` | `types/completions/completion.rs` | Legacy completions API (simple, low priority) |

### Phase 4 — Remaining APIs ❌ TODO

| Module | Rust reference | Notes |
|--------|---------------|-------|
| `src/glaoi/upload.gleam` | `types/uploads/` | Chunked file uploads: create, add part, complete, cancel |
| `src/glaoi/vector_store.gleam` | `types/vectorstores/` | Vector stores + files + file batches |
| `src/glaoi/assistant.gleam` | `types/assistants/` | Deprecated but still used: assistants, threads, runs, messages, steps |
| `src/glaoi/video.gleam` | `types/videos/` | Video generation (Sora): create, edit, extend, remix |
| `src/glaoi/container.gleam` | `types/containers/` | Container management |
| `src/glaoi/skill.gleam` | `types/skills/` | Skill definitions |
| `src/glaoi/chatkit.gleam` | `types/chatkit/` | Chat kit sessions/threads |
| `src/glaoi/eval.gleam` | `types/evals/` | Evaluation framework |
| `src/glaoi/admin.gleam` | `types/admin/` (many subdirs) | Administration: users, projects, API keys, audit logs, invites, roles, usage, certificates, groups, rate limits, service accounts |
| `src/glaoi/realtime.gleam` | `types/realtime/` | WebSocket real-time API: client/server events, session management. Needs different transport abstraction (not HTTP request/response). |
| `src/glaoi/webhook.gleam` | `types/webhooks/` | Webhook signature verification |

### Phase 5 — Cross-cutting concerns ❌ TODO

| Feature | Notes |
|---------|-------|
| **Multipart support** | Define a `MultipartPart` type and `build_multipart_request` helper. Needed by: audio transcription/translation, image edit/variation, file upload, video upload, skill upload, container upload |
| **SSE streaming helpers** | `parse_sse_line(line: String) -> SseEvent` to help users parse raw SSE from their HTTP client. Already have `chat.parse_stream_chunk` as a model. |
| **Query parameter encoding** | `ListFilesQuery`, `ListChatCompletionsQuery`, etc. need URL query encoding via `serde_urlencoded` equivalent. Use `request.set_query` with key-value pairs. |
| **Retry guidance** | Document recommended retry strategy (exponential backoff, retry on 429/5xx, not on insufficient_quota). This is user-side since we're sans-IO. |
| **BYOT (Bring Your Own Types)** | Allow passing `Dynamic` / raw JSON instead of typed requests. Low priority — the typed API is the main value. |

---

## Rust modules NOT being ported

| Module | Reason |
|--------|--------|
| `types/mcp/` | Model Context Protocol — niche, internal to OpenAI |
| `types/graders/` | Tightly coupled with evals, port with evals if needed |
| `types/shared/custom_grammar_format_param.rs` | Custom grammar format — niche feature, add when needed |
| `types/shared/filter.rs` | Vector store filters — port with vector stores |
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
  src/
    glaoi.gleam                    # Re-exports
    glaoi/
      config.gleam                 # Config + AzureConfig
      error.gleam                  # ApiError, GlaoiError
      internal.gleam               # Request building, response parsing
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
      response.gleam               # Responses API            (Phase 3)
      fine_tuning.gleam            # Fine-tuning API          (Phase 3)
      batch.gleam                  # Batch API                (Phase 3)
      completion.gleam             # Legacy completions       (Phase 3)
      upload.gleam                 # Uploads API              (Phase 4)
      vector_store.gleam           # Vector stores API        (Phase 4)
      assistant.gleam              # Assistants API           (Phase 4)
      video.gleam                  # Video API                (Phase 4)
      container.gleam              # Containers API           (Phase 4)
      skill.gleam                  # Skills API               (Phase 4)
      chatkit.gleam                # ChatKit API              (Phase 4)
      eval.gleam                   # Evals API                (Phase 4)
      admin.gleam                  # Administration API       (Phase 4)
      realtime.gleam               # Realtime WebSocket API   (Phase 4)
      webhook.gleam                # Webhook verification     (Phase 4)
  test/
    glaoi_test.gleam
    glaoi/
      config_test.gleam
      model_test.gleam
      embedding_test.gleam
      chat_test.gleam
      moderation_test.gleam        # (Phase 2)
      image_test.gleam             # (Phase 2)
      audio_test.gleam             # (Phase 2)
      file_test.gleam              # (Phase 2)
      ...                          # (Phase 3+)
```
