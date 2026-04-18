# glopenai

[![Package Version](https://img.shields.io/hexpm/v/glopenai)](https://hex.pm/packages/glopenai)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glopenai/)

A sans-IO OpenAI API client for Gleam, ported from the Rust
[async-openai](https://github.com/64bit/async-openai) library.

**Sans-IO** means glopenai builds HTTP requests and parses HTTP responses, but
never sends or receives anything itself. You bring your own HTTP client
(`gleam_httpc`, `hackney`, `fetch`, etc.) and call it between the request and
response functions. This makes the library transport-agnostic, easy to test,
and free of runtime dependencies beyond the Gleam standard library.

## Installation

```sh
gleam add glopenai
```

## Quick start

```gleam
import gleam/httpc
import gleam/io
import gleam/option.{Some}
import glopenai/chat
import glopenai/config

pub fn main() {
  let cfg = config.new(api_key: "sk-...")

  // 1. Build the request
  let request =
    chat.new_create_request(model: "gpt-4o-mini", messages: [
      chat.system_message("You are a helpful assistant."),
      chat.user_message("What is the capital of France?"),
    ])
    |> chat.with_max_completion_tokens(256)

  let http_request = chat.create_request(cfg, request)

  // 2. Send it with any HTTP client
  let assert Ok(http_response) = httpc.send(http_request)

  // 3. Parse the response
  let assert Ok(response) = chat.create_response(http_response)

  case response.choices {
    [choice, ..] ->
      case choice.message.content {
        Some(content) -> io.println(content)
        _ -> Nil
      }
    _ -> Nil
  }
}
```

Every API module follows the same `*_request` / `*_response` pattern.
Multipart endpoints (file uploads, upload parts) return `Request(BitArray)`
instead of `Request(String)` -- use `httpc.send_bits` for those.

## Origin

glopenai started as a direct port of
[async-openai](https://github.com/64bit/async-openai), the most complete
OpenAI client library for Rust. Types, field names, and API coverage are
mapped as faithfully as possible from the Rust source, adapted to Gleam
conventions (custom types instead of serde enums, `Result` instead of panics,
builder functions instead of derive_builder macros).

The port tracks upstream type changes from the Rust source.

## API coverage

### Available now

| Module | API | Highlights |
|--------|-----|------------|
| `chat` | Chat Completions | Messages, tools, streaming, web search, structured output |
| `response` | Responses API | 25 input item types, 20 output types, 48 stream events, tools |
| `model` | Models | List, retrieve, delete |
| `embedding` | Embeddings | String, array, token, and multi-input variants |
| `moderation` | Moderations | Text, image, and multi-modal input |
| `image` | Image Generation | 8 sizes, 5 models, URL and base64 responses |
| `audio` | Audio (TTS) | 13 voices, 6 output formats |
| `file` | Files | List, retrieve, delete, content, and multipart upload |
| `completion` | Completions (legacy) | 4 prompt variants, logprobs, streaming |
| `fine_tuning` | Fine-tuning | Jobs, events, checkpoints, DPO/reinforcement methods |
| `batch` | Batch API | Create, retrieve, cancel, list, JSONL helpers |
| `vector_store` | Vector Stores | Stores, files, batches, search with filters, chunking strategies |
| `chatkit` | ChatKit | Sessions, threads, items |
| `upload` | Uploads | Create, add part (multipart), complete, cancel |
| `webhook` | Webhooks | 15 event types, HMAC-SHA256 signature verification |
| `config` | Configuration | OpenAI and Azure endpoints, custom headers |

### Not yet ported

| Module | Notes |
|--------|-------|
| Assistants | Deprecated upstream but still used; large surface area |
| Video (Sora) | Create, edit, extend, remix |
| Containers | Container management |
| Skills | Skill definitions |
| Evals | Evaluation framework |
| Admin | Users, projects, API keys, audit logs, invites, roles, usage, and more |
| Realtime | WebSocket-based; needs a different transport abstraction |
| Audio transcription/translation | Waiting on multipart integration |
| Image edit/variation | Waiting on multipart integration |
| SSE parsing helper | Per-module stream parsers exist; generic helper planned |

## Compatible APIs

glopenai works with any API that follows the OpenAI HTTP contract. Set
`config.with_api_base` to point at a different endpoint:

```gleam
let cfg =
  config.new(api_key: "...")
  |> config.with_api_base("http://localhost:11434/v1")  // Ollama
```

Azure OpenAI is also supported via `config.new_azure`.

## Dependencies

```toml
gleam_stdlib >= 0.44.0
gleam_json   >= 3.1.0
gleam_http   >= 4.3.0
```

No HTTP client dependency. Bring your own.

## Development

```sh
cd glopenai
gleam build   # Compile
gleam test    # Run the test suite
```

Runnable examples live in `dev/example/`. Run them with:

```sh
OPENAI_API_KEY=sk-... gleam run -m example/chat
```

## License

MIT
