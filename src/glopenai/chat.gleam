/// Chat completions API: create, list, retrieve, and delete chat completions.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/internal
import glopenai/internal/codec
import glopenai/shared.{
  type CompletionUsage, type FunctionCall, type FunctionName, type FunctionObject,
  type ImageUrl, type ReasoningEffort, type ResponseFormat,
}

// ============================================================================
// Enums
// ============================================================================

pub type Role {
  RoleSystem
  RoleUser
  RoleAssistant
  RoleTool
  RoleDeveloper
}

pub type FinishReason {
  Stop
  Length
  ToolCalls
  ContentFilter
  FunctionCallFinish
}

pub type ServiceTier {
  ServiceTierAuto
  ServiceTierDefault
  ServiceTierFlex
  ServiceTierScale
  ServiceTierPriority
}

pub type InputAudioFormat {
  Wav
  Mp3
}

pub type Verbosity {
  VerbosityLow
  VerbosityMedium
  VerbosityHigh
}

pub type WebSearchContextSize {
  WebSearchLow
  WebSearchMedium
  WebSearchHigh
}

pub type ResponseModality {
  ModalityText
  ModalityAudio
}

pub type ToolChoiceMode {
  ToolChoiceNone
  ToolChoiceAuto
  ToolChoiceRequired
}

// ============================================================================
// Content part types
// ============================================================================

pub type InputAudio {
  InputAudio(data: String, format: InputAudioFormat)
}

pub type FileObject {
  FileObject(
    file_data: Option(String),
    file_id: Option(String),
    filename: Option(String),
  )
}

/// Content part for user messages (tagged by "type").
pub type UserContentPart {
  UserTextPart(text: String)
  UserImageUrlPart(image_url: ImageUrl)
  UserInputAudioPart(input_audio: InputAudio)
  UserFilePart(file: FileObject)
}

/// Content part for assistant messages.
pub type AssistantContentPart {
  AssistantTextPart(text: String)
  AssistantRefusalPart(refusal: String)
}

// ============================================================================
// Message content types (untagged: String | Array)
// ============================================================================

pub type DeveloperMessageContent {
  DeveloperTextContent(String)
  DeveloperPartsContent(List(String))
}

pub type SystemMessageContent {
  SystemTextContent(String)
  SystemPartsContent(List(String))
}

pub type UserMessageContent {
  UserTextContent(String)
  UserPartsContent(List(UserContentPart))
}

pub type AssistantMessageContent {
  AssistantTextContent(String)
  AssistantPartsContent(List(AssistantContentPart))
}

pub type ToolMessageContent {
  ToolTextContent(String)
  ToolPartsContent(List(String))
}

// ============================================================================
// Tool types
// ============================================================================

pub type ChatCompletionTool {
  FunctionTool(function: FunctionObject)
}

/// The name and arguments of a tool call made by the model.
pub type ToolCall {
  FunctionToolCall(id: String, function: FunctionCall)
}

/// Controls which tool the model calls.
pub type ToolChoice {
  ToolChoiceModeChoice(ToolChoiceMode)
  ToolChoiceFunctionChoice(function: FunctionName)
}

// ============================================================================
// Messages (tagged by "role")
// ============================================================================

pub type ChatMessage {
  DeveloperMessage(content: DeveloperMessageContent, name: Option(String))
  SystemMessage(content: SystemMessageContent, name: Option(String))
  UserMessage(content: UserMessageContent, name: Option(String))
  AssistantMessage(
    content: Option(AssistantMessageContent),
    refusal: Option(String),
    name: Option(String),
    tool_calls: Option(List(ToolCall)),
  )
  ToolMessage(content: ToolMessageContent, tool_call_id: String)
}

// ============================================================================
// Convenience message constructors
// ============================================================================

/// Create a simple user text message.
pub fn user_message(text: String) -> ChatMessage {
  UserMessage(content: UserTextContent(text), name: None)
}

/// Create a simple system text message.
pub fn system_message(text: String) -> ChatMessage {
  SystemMessage(content: SystemTextContent(text), name: None)
}

/// Create a simple developer text message.
pub fn developer_message(text: String) -> ChatMessage {
  DeveloperMessage(content: DeveloperTextContent(text), name: None)
}

/// Create a simple assistant text message.
pub fn assistant_message(text: String) -> ChatMessage {
  AssistantMessage(
    content: Some(AssistantTextContent(text)),
    refusal: None,
    name: None,
    tool_calls: None,
  )
}

/// Create a tool result message.
pub fn tool_message(content: String, tool_call_id: String) -> ChatMessage {
  ToolMessage(content: ToolTextContent(content), tool_call_id: tool_call_id)
}

// ============================================================================
// Web search options
// ============================================================================

pub type WebSearchLocation {
  WebSearchLocation(
    country: Option(String),
    region: Option(String),
    city: Option(String),
    timezone: Option(String),
  )
}

pub type WebSearchUserLocation {
  WebSearchUserLocation(approximate: WebSearchLocation)
}

pub type WebSearchOptions {
  WebSearchOptions(
    search_context_size: Option(WebSearchContextSize),
    user_location: Option(WebSearchUserLocation),
  )
}

// ============================================================================
// Stream options
// ============================================================================

pub type ChatCompletionStreamOptions {
  ChatCompletionStreamOptions(
    include_usage: Option(Bool),
    include_obfuscation: Option(Bool),
  )
}

// ============================================================================
// Stop configuration
// ============================================================================

pub type StopConfiguration {
  StopString(String)
  StopStringArray(List(String))
}

// ============================================================================
// Request type
// ============================================================================

pub type CreateChatCompletionRequest {
  CreateChatCompletionRequest(
    model: String,
    messages: List(ChatMessage),
    temperature: Option(Float),
    top_p: Option(Float),
    n: Option(Int),
    stream: Option(Bool),
    stream_options: Option(ChatCompletionStreamOptions),
    stop: Option(StopConfiguration),
    max_completion_tokens: Option(Int),
    frequency_penalty: Option(Float),
    presence_penalty: Option(Float),
    logprobs: Option(Bool),
    top_logprobs: Option(Int),
    response_format: Option(ResponseFormat),
    tools: Option(List(ChatCompletionTool)),
    tool_choice: Option(ToolChoice),
    parallel_tool_calls: Option(Bool),
    reasoning_effort: Option(ReasoningEffort),
    modalities: Option(List(ResponseModality)),
    verbosity: Option(Verbosity),
    web_search_options: Option(WebSearchOptions),
    store: Option(Bool),
    metadata: Option(Dict(String, String)),
    service_tier: Option(ServiceTier),
    safety_identifier: Option(String),
    prompt_cache_key: Option(String),
  )
}

// ============================================================================
// Request builder
// ============================================================================

/// Create a new chat completion request with required fields.
pub fn new_create_request(
  model model: String,
  messages messages: List(ChatMessage),
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(
    model: model,
    messages: messages,
    temperature: None,
    top_p: None,
    n: None,
    stream: None,
    stream_options: None,
    stop: None,
    max_completion_tokens: None,
    frequency_penalty: None,
    presence_penalty: None,
    logprobs: None,
    top_logprobs: None,
    response_format: None,
    tools: None,
    tool_choice: None,
    parallel_tool_calls: None,
    reasoning_effort: None,
    modalities: None,
    verbosity: None,
    web_search_options: None,
    store: None,
    metadata: None,
    service_tier: None,
    safety_identifier: None,
    prompt_cache_key: None,
  )
}

pub fn with_temperature(
  request: CreateChatCompletionRequest,
  temperature: Float,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, temperature: Some(temperature))
}

pub fn with_top_p(
  request: CreateChatCompletionRequest,
  top_p: Float,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, top_p: Some(top_p))
}

pub fn with_n(
  request: CreateChatCompletionRequest,
  n: Int,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, n: Some(n))
}

pub fn with_stream(
  request: CreateChatCompletionRequest,
  stream: Bool,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, stream: Some(stream))
}

pub fn with_max_completion_tokens(
  request: CreateChatCompletionRequest,
  max_tokens: Int,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(
    ..request,
    max_completion_tokens: Some(max_tokens),
  )
}

pub fn with_tools(
  request: CreateChatCompletionRequest,
  tools: List(ChatCompletionTool),
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, tools: Some(tools))
}

pub fn with_tool_choice(
  request: CreateChatCompletionRequest,
  choice: ToolChoice,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, tool_choice: Some(choice))
}

pub fn with_response_format(
  request: CreateChatCompletionRequest,
  format: ResponseFormat,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, response_format: Some(format))
}

pub fn with_reasoning_effort(
  request: CreateChatCompletionRequest,
  effort: ReasoningEffort,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, reasoning_effort: Some(effort))
}

pub fn with_stop(
  request: CreateChatCompletionRequest,
  stop: StopConfiguration,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, stop: Some(stop))
}

pub fn with_store(
  request: CreateChatCompletionRequest,
  store: Bool,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, store: Some(store))
}

pub fn with_service_tier(
  request: CreateChatCompletionRequest,
  tier: ServiceTier,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, service_tier: Some(tier))
}

pub fn with_web_search_options(
  request: CreateChatCompletionRequest,
  options: WebSearchOptions,
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, web_search_options: Some(options))
}

pub fn with_metadata(
  request: CreateChatCompletionRequest,
  metadata: Dict(String, String),
) -> CreateChatCompletionRequest {
  CreateChatCompletionRequest(..request, metadata: Some(metadata))
}

// ============================================================================
// Response types
// ============================================================================

pub type UrlCitation {
  UrlCitation(
    start_index: Int,
    end_index: Int,
    title: String,
    url: String,
  )
}

pub type ResponseMessageAnnotation {
  UrlCitationAnnotation(url_citation: UrlCitation)
}

pub type ChatCompletionResponseMessage {
  ChatCompletionResponseMessage(
    role: Role,
    content: Option(String),
    refusal: Option(String),
    tool_calls: Option(List(ToolCall)),
    annotations: Option(List(ResponseMessageAnnotation)),
  )
}

pub type ChatChoice {
  ChatChoice(
    index: Int,
    message: ChatCompletionResponseMessage,
    finish_reason: Option(FinishReason),
  )
}

pub type CreateChatCompletionResponse {
  CreateChatCompletionResponse(
    id: String,
    object: String,
    created: Int,
    model: String,
    choices: List(ChatChoice),
    usage: Option(CompletionUsage),
    service_tier: Option(ServiceTier),
    system_fingerprint: Option(String),
  )
}

pub type ChatCompletionList {
  ChatCompletionList(
    object: String,
    data: List(CreateChatCompletionResponse),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

pub type ChatCompletionDeleted {
  ChatCompletionDeleted(object: String, id: String, deleted: Bool)
}

// ============================================================================
// Stream response types
// ============================================================================

pub type FunctionCallStream {
  FunctionCallStream(name: Option(String), arguments: Option(String))
}

pub type ToolCallChunk {
  ToolCallChunk(
    index: Int,
    id: Option(String),
    function: Option(FunctionCallStream),
  )
}

pub type ChatCompletionStreamDelta {
  ChatCompletionStreamDelta(
    role: Option(Role),
    content: Option(String),
    refusal: Option(String),
    tool_calls: Option(List(ToolCallChunk)),
  )
}

pub type ChatChoiceStream {
  ChatChoiceStream(
    index: Int,
    delta: ChatCompletionStreamDelta,
    finish_reason: Option(FinishReason),
  )
}

pub type CreateChatCompletionStreamResponse {
  CreateChatCompletionStreamResponse(
    id: String,
    object: String,
    created: Int,
    model: String,
    choices: List(ChatChoiceStream),
    usage: Option(CompletionUsage),
    service_tier: Option(ServiceTier),
    system_fingerprint: Option(String),
  )
}

// ============================================================================
// Encoders
// ============================================================================

pub fn role_to_json(role: Role) -> json.Json {
  json.string(case role {
    RoleSystem -> "system"
    RoleUser -> "user"
    RoleAssistant -> "assistant"
    RoleTool -> "tool"
    RoleDeveloper -> "developer"
  })
}

pub fn finish_reason_to_json(reason: FinishReason) -> json.Json {
  json.string(case reason {
    Stop -> "stop"
    Length -> "length"
    ToolCalls -> "tool_calls"
    ContentFilter -> "content_filter"
    FunctionCallFinish -> "function_call"
  })
}

pub fn service_tier_to_json(tier: ServiceTier) -> json.Json {
  json.string(case tier {
    ServiceTierAuto -> "auto"
    ServiceTierDefault -> "default"
    ServiceTierFlex -> "flex"
    ServiceTierScale -> "scale"
    ServiceTierPriority -> "priority"
  })
}

pub fn input_audio_format_to_json(format: InputAudioFormat) -> json.Json {
  json.string(case format {
    Wav -> "wav"
    Mp3 -> "mp3"
  })
}

pub fn verbosity_to_json(v: Verbosity) -> json.Json {
  json.string(case v {
    VerbosityLow -> "low"
    VerbosityMedium -> "medium"
    VerbosityHigh -> "high"
  })
}

pub fn web_search_context_size_to_json(size: WebSearchContextSize) -> json.Json {
  json.string(case size {
    WebSearchLow -> "low"
    WebSearchMedium -> "medium"
    WebSearchHigh -> "high"
  })
}

pub fn response_modality_to_json(m: ResponseModality) -> json.Json {
  json.string(case m {
    ModalityText -> "text"
    ModalityAudio -> "audio"
  })
}

pub fn tool_choice_mode_to_json(mode: ToolChoiceMode) -> json.Json {
  json.string(case mode {
    ToolChoiceNone -> "none"
    ToolChoiceAuto -> "auto"
    ToolChoiceRequired -> "required"
  })
}

pub fn input_audio_to_json(audio: InputAudio) -> json.Json {
  json.object([
    #("data", json.string(audio.data)),
    #("format", input_audio_format_to_json(audio.format)),
  ])
}

pub fn file_object_to_json(file: FileObject) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field("file_data", file.file_data, json.string),
    codec.optional_field("file_id", file.file_id, json.string),
    codec.optional_field("filename", file.filename, json.string),
  ])
}

pub fn user_content_part_to_json(part: UserContentPart) -> json.Json {
  case part {
    UserTextPart(text) ->
      json.object([
        #("type", json.string("text")),
        #("text", json.string(text)),
      ])
    UserImageUrlPart(image_url) ->
      json.object([
        #("type", json.string("image_url")),
        #("image_url", shared.image_url_to_json(image_url)),
      ])
    UserInputAudioPart(input_audio) ->
      json.object([
        #("type", json.string("input_audio")),
        #("input_audio", input_audio_to_json(input_audio)),
      ])
    UserFilePart(file) ->
      json.object([
        #("type", json.string("file")),
        #("file", file_object_to_json(file)),
      ])
  }
}

pub fn assistant_content_part_to_json(
  part: AssistantContentPart,
) -> json.Json {
  case part {
    AssistantTextPart(text) ->
      json.object([
        #("type", json.string("text")),
        #("text", json.string(text)),
      ])
    AssistantRefusalPart(refusal) ->
      json.object([
        #("type", json.string("refusal")),
        #("refusal", json.string(refusal)),
      ])
  }
}

fn text_part_to_json(text: String) -> json.Json {
  json.object([
    #("type", json.string("text")),
    #("text", json.string(text)),
  ])
}

pub fn user_message_content_to_json(content: UserMessageContent) -> json.Json {
  case content {
    UserTextContent(text) -> json.string(text)
    UserPartsContent(parts) -> json.array(parts, user_content_part_to_json)
  }
}

pub fn developer_message_content_to_json(
  content: DeveloperMessageContent,
) -> json.Json {
  case content {
    DeveloperTextContent(text) -> json.string(text)
    DeveloperPartsContent(parts) -> json.array(parts, text_part_to_json)
  }
}

pub fn system_message_content_to_json(
  content: SystemMessageContent,
) -> json.Json {
  case content {
    SystemTextContent(text) -> json.string(text)
    SystemPartsContent(parts) -> json.array(parts, text_part_to_json)
  }
}

pub fn assistant_message_content_to_json(
  content: AssistantMessageContent,
) -> json.Json {
  case content {
    AssistantTextContent(text) -> json.string(text)
    AssistantPartsContent(parts) ->
      json.array(parts, assistant_content_part_to_json)
  }
}

pub fn tool_message_content_to_json(content: ToolMessageContent) -> json.Json {
  case content {
    ToolTextContent(text) -> json.string(text)
    ToolPartsContent(parts) -> json.array(parts, text_part_to_json)
  }
}

pub fn tool_call_to_json(call: ToolCall) -> json.Json {
  case call {
    FunctionToolCall(id, function) ->
      json.object([
        #("type", json.string("function")),
        #("id", json.string(id)),
        #("function", shared.function_call_to_json(function)),
      ])
  }
}

pub fn chat_completion_tool_to_json(tool: ChatCompletionTool) -> json.Json {
  case tool {
    FunctionTool(function) ->
      json.object([
        #("type", json.string("function")),
        #("function", shared.function_object_to_json(function)),
      ])
  }
}

pub fn tool_choice_to_json(choice: ToolChoice) -> json.Json {
  case choice {
    ToolChoiceModeChoice(mode) -> tool_choice_mode_to_json(mode)
    ToolChoiceFunctionChoice(function) ->
      json.object([
        #("type", json.string("function")),
        #("function", shared.function_name_to_json(function)),
      ])
  }
}

pub fn stop_configuration_to_json(stop: StopConfiguration) -> json.Json {
  case stop {
    StopString(s) -> json.string(s)
    StopStringArray(arr) -> json.array(arr, json.string)
  }
}

pub fn web_search_options_to_json(opts: WebSearchOptions) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field(
      "search_context_size",
      opts.search_context_size,
      web_search_context_size_to_json,
    ),
    codec.optional_field("user_location", opts.user_location, fn(loc) {
      json.object([
        #("type", json.string("approximate")),
        #(
          "approximate",
          codec.object_with_optional([], [
            codec.optional_field("country", loc.approximate.country, json.string),
            codec.optional_field("region", loc.approximate.region, json.string),
            codec.optional_field("city", loc.approximate.city, json.string),
            codec.optional_field(
              "timezone",
              loc.approximate.timezone,
              json.string,
            ),
          ]),
        ),
      ])
    }),
  ])
}

pub fn stream_options_to_json(
  opts: ChatCompletionStreamOptions,
) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field("include_usage", opts.include_usage, json.bool),
    codec.optional_field(
      "include_obfuscation",
      opts.include_obfuscation,
      json.bool,
    ),
  ])
}

pub fn chat_message_to_json(message: ChatMessage) -> json.Json {
  case message {
    DeveloperMessage(content, name) ->
      codec.object_with_optional(
        [
          #("role", json.string("developer")),
          #("content", developer_message_content_to_json(content)),
        ],
        [codec.optional_field("name", name, json.string)],
      )
    SystemMessage(content, name) ->
      codec.object_with_optional(
        [
          #("role", json.string("system")),
          #("content", system_message_content_to_json(content)),
        ],
        [codec.optional_field("name", name, json.string)],
      )
    UserMessage(content, name) ->
      codec.object_with_optional(
        [
          #("role", json.string("user")),
          #("content", user_message_content_to_json(content)),
        ],
        [codec.optional_field("name", name, json.string)],
      )
    AssistantMessage(content, refusal, name, tool_calls) ->
      codec.object_with_optional(
        [#("role", json.string("assistant"))],
        [
          codec.optional_field(
            "content",
            content,
            assistant_message_content_to_json,
          ),
          codec.optional_field("refusal", refusal, json.string),
          codec.optional_field("name", name, json.string),
          codec.optional_field("tool_calls", tool_calls, fn(calls) {
            json.array(calls, tool_call_to_json)
          }),
        ],
      )
    ToolMessage(content, tool_call_id) ->
      json.object([
        #("role", json.string("tool")),
        #("content", tool_message_content_to_json(content)),
        #("tool_call_id", json.string(tool_call_id)),
      ])
  }
}

pub fn create_chat_completion_request_to_json(
  request: CreateChatCompletionRequest,
) -> json.Json {
  codec.object_with_optional(
    [
      #("model", json.string(request.model)),
      #("messages", json.array(request.messages, chat_message_to_json)),
    ],
    [
      codec.optional_field("temperature", request.temperature, json.float),
      codec.optional_field("top_p", request.top_p, json.float),
      codec.optional_field("n", request.n, json.int),
      codec.optional_field("stream", request.stream, json.bool),
      codec.optional_field(
        "stream_options",
        request.stream_options,
        stream_options_to_json,
      ),
      codec.optional_field("stop", request.stop, stop_configuration_to_json),
      codec.optional_field(
        "max_completion_tokens",
        request.max_completion_tokens,
        json.int,
      ),
      codec.optional_field(
        "frequency_penalty",
        request.frequency_penalty,
        json.float,
      ),
      codec.optional_field(
        "presence_penalty",
        request.presence_penalty,
        json.float,
      ),
      codec.optional_field("logprobs", request.logprobs, json.bool),
      codec.optional_field("top_logprobs", request.top_logprobs, json.int),
      codec.optional_field(
        "response_format",
        request.response_format,
        shared.response_format_to_json,
      ),
      codec.optional_field("tools", request.tools, fn(tools) {
        json.array(tools, chat_completion_tool_to_json)
      }),
      codec.optional_field(
        "tool_choice",
        request.tool_choice,
        tool_choice_to_json,
      ),
      codec.optional_field(
        "parallel_tool_calls",
        request.parallel_tool_calls,
        json.bool,
      ),
      codec.optional_field(
        "reasoning_effort",
        request.reasoning_effort,
        shared.reasoning_effort_to_json,
      ),
      codec.optional_field("modalities", request.modalities, fn(mods) {
        json.array(mods, response_modality_to_json)
      }),
      codec.optional_field("verbosity", request.verbosity, verbosity_to_json),
      codec.optional_field(
        "web_search_options",
        request.web_search_options,
        web_search_options_to_json,
      ),
      codec.optional_field("store", request.store, json.bool),
      codec.optional_field("metadata", request.metadata, fn(m) {
        json.object(
          dict.to_list(m) |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
        )
      }),
      codec.optional_field(
        "service_tier",
        request.service_tier,
        service_tier_to_json,
      ),
      codec.optional_field(
        "safety_identifier",
        request.safety_identifier,
        json.string,
      ),
      codec.optional_field(
        "prompt_cache_key",
        request.prompt_cache_key,
        json.string,
      ),
    ],
  )
}

// ============================================================================
// Decoders
// ============================================================================

pub fn role_decoder() -> decode.Decoder(Role) {
  use value <- decode.then(decode.string)
  case value {
    "system" -> decode.success(RoleSystem)
    "user" -> decode.success(RoleUser)
    "assistant" -> decode.success(RoleAssistant)
    "tool" -> decode.success(RoleTool)
    "developer" -> decode.success(RoleDeveloper)
    _ -> decode.failure(RoleUser, "Role")
  }
}

pub fn finish_reason_decoder() -> decode.Decoder(FinishReason) {
  use value <- decode.then(decode.string)
  case value {
    "stop" -> decode.success(Stop)
    "length" -> decode.success(Length)
    "tool_calls" -> decode.success(ToolCalls)
    "content_filter" -> decode.success(ContentFilter)
    "function_call" -> decode.success(FunctionCallFinish)
    _ -> decode.failure(Stop, "FinishReason")
  }
}

pub fn service_tier_decoder() -> decode.Decoder(ServiceTier) {
  use value <- decode.then(decode.string)
  case value {
    "auto" -> decode.success(ServiceTierAuto)
    "default" -> decode.success(ServiceTierDefault)
    "flex" -> decode.success(ServiceTierFlex)
    "scale" -> decode.success(ServiceTierScale)
    "priority" -> decode.success(ServiceTierPriority)
    _ -> decode.failure(ServiceTierAuto, "ServiceTier")
  }
}

pub fn tool_call_decoder() -> decode.Decoder(ToolCall) {
  use id <- decode.field("id", decode.string)
  use function <- decode.field("function", shared.function_call_decoder())
  decode.success(FunctionToolCall(id: id, function: function))
}

pub fn url_citation_decoder() -> decode.Decoder(UrlCitation) {
  use start_index <- decode.field("start_index", decode.int)
  use end_index <- decode.field("end_index", decode.int)
  use title <- decode.field("title", decode.string)
  use url <- decode.field("url", decode.string)
  decode.success(UrlCitation(
    start_index: start_index,
    end_index: end_index,
    title: title,
    url: url,
  ))
}

pub fn response_message_annotation_decoder() -> decode.Decoder(
  ResponseMessageAnnotation,
) {
  use _tag <- decode.field("type", decode.string)
  use citation <- decode.field("url_citation", url_citation_decoder())
  decode.success(UrlCitationAnnotation(url_citation: citation))
}

pub fn chat_completion_response_message_decoder() -> decode.Decoder(
  ChatCompletionResponseMessage,
) {
  use role <- decode.field("role", role_decoder())
  use content <- decode.optional_field(
    "content",
    None,
    decode.optional(decode.string),
  )
  use refusal <- decode.optional_field(
    "refusal",
    None,
    decode.optional(decode.string),
  )
  use tool_calls <- decode.optional_field(
    "tool_calls",
    None,
    decode.optional(decode.list(tool_call_decoder())),
  )
  use annotations <- decode.optional_field(
    "annotations",
    None,
    decode.optional(decode.list(response_message_annotation_decoder())),
  )
  decode.success(ChatCompletionResponseMessage(
    role: role,
    content: content,
    refusal: refusal,
    tool_calls: tool_calls,
    annotations: annotations,
  ))
}

pub fn chat_choice_decoder() -> decode.Decoder(ChatChoice) {
  use index <- decode.field("index", decode.int)
  use message <- decode.field(
    "message",
    chat_completion_response_message_decoder(),
  )
  use finish_reason <- decode.optional_field(
    "finish_reason",
    None,
    decode.optional(finish_reason_decoder()),
  )
  decode.success(ChatChoice(
    index: index,
    message: message,
    finish_reason: finish_reason,
  ))
}

pub fn create_chat_completion_response_decoder() -> decode.Decoder(
  CreateChatCompletionResponse,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use created <- decode.field("created", decode.int)
  use model <- decode.field("model", decode.string)
  use choices <- decode.field("choices", decode.list(chat_choice_decoder()))
  use usage <- decode.optional_field(
    "usage",
    None,
    decode.optional(shared.completion_usage_decoder()),
  )
  use service_tier <- decode.optional_field(
    "service_tier",
    None,
    decode.optional(service_tier_decoder()),
  )
  use system_fingerprint <- decode.optional_field(
    "system_fingerprint",
    None,
    decode.optional(decode.string),
  )
  decode.success(CreateChatCompletionResponse(
    id: id,
    object: object,
    created: created,
    model: model,
    choices: choices,
    usage: usage,
    service_tier: service_tier,
    system_fingerprint: system_fingerprint,
  ))
}

fn chat_completion_list_decoder() -> decode.Decoder(ChatCompletionList) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field(
    "data",
    decode.list(create_chat_completion_response_decoder()),
  )
  use first_id <- decode.optional_field(
    "first_id",
    None,
    decode.optional(decode.string),
  )
  use last_id <- decode.optional_field(
    "last_id",
    None,
    decode.optional(decode.string),
  )
  use has_more <- decode.field("has_more", decode.bool)
  decode.success(ChatCompletionList(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

fn chat_completion_deleted_decoder() -> decode.Decoder(ChatCompletionDeleted) {
  use object <- decode.field("object", decode.string)
  use id <- decode.field("id", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(ChatCompletionDeleted(
    object: object,
    id: id,
    deleted: deleted,
  ))
}

// Stream decoders

pub fn function_call_stream_decoder() -> decode.Decoder(FunctionCallStream) {
  use name <- decode.optional_field(
    "name",
    None,
    decode.optional(decode.string),
  )
  use arguments <- decode.optional_field(
    "arguments",
    None,
    decode.optional(decode.string),
  )
  decode.success(FunctionCallStream(name: name, arguments: arguments))
}

pub fn tool_call_chunk_decoder() -> decode.Decoder(ToolCallChunk) {
  use index <- decode.field("index", decode.int)
  use id <- decode.optional_field("id", None, decode.optional(decode.string))
  use function <- decode.optional_field(
    "function",
    None,
    decode.optional(function_call_stream_decoder()),
  )
  decode.success(ToolCallChunk(index: index, id: id, function: function))
}

pub fn chat_completion_stream_delta_decoder() -> decode.Decoder(
  ChatCompletionStreamDelta,
) {
  use role <- decode.optional_field(
    "role",
    None,
    decode.optional(role_decoder()),
  )
  use content <- decode.optional_field(
    "content",
    None,
    decode.optional(decode.string),
  )
  use refusal <- decode.optional_field(
    "refusal",
    None,
    decode.optional(decode.string),
  )
  use tool_calls <- decode.optional_field(
    "tool_calls",
    None,
    decode.optional(decode.list(tool_call_chunk_decoder())),
  )
  decode.success(ChatCompletionStreamDelta(
    role: role,
    content: content,
    refusal: refusal,
    tool_calls: tool_calls,
  ))
}

pub fn chat_choice_stream_decoder() -> decode.Decoder(ChatChoiceStream) {
  use index <- decode.field("index", decode.int)
  use delta <- decode.field("delta", chat_completion_stream_delta_decoder())
  use finish_reason <- decode.optional_field(
    "finish_reason",
    None,
    decode.optional(finish_reason_decoder()),
  )
  decode.success(ChatChoiceStream(
    index: index,
    delta: delta,
    finish_reason: finish_reason,
  ))
}

pub fn create_chat_completion_stream_response_decoder() -> decode.Decoder(
  CreateChatCompletionStreamResponse,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use created <- decode.field("created", decode.int)
  use model <- decode.field("model", decode.string)
  use choices <- decode.field(
    "choices",
    decode.list(chat_choice_stream_decoder()),
  )
  use usage <- decode.optional_field(
    "usage",
    None,
    decode.optional(shared.completion_usage_decoder()),
  )
  use service_tier <- decode.optional_field(
    "service_tier",
    None,
    decode.optional(service_tier_decoder()),
  )
  use system_fingerprint <- decode.optional_field(
    "system_fingerprint",
    None,
    decode.optional(decode.string),
  )
  decode.success(CreateChatCompletionStreamResponse(
    id: id,
    object: object,
    created: created,
    model: model,
    choices: choices,
    usage: usage,
    service_tier: service_tier,
    system_fingerprint: system_fingerprint,
  ))
}

/// Parse a single SSE data line into a stream chunk.
/// Returns `Ok(Some(chunk))` for data, `Ok(None)` for the [DONE] sentinel.
pub fn parse_stream_chunk(
  data: String,
) -> Result(Option(CreateChatCompletionStreamResponse), GlopenaiError) {
  case data {
    "[DONE]" -> Ok(None)
    _ ->
      case
        json.parse(data, create_chat_completion_stream_response_decoder())
      {
        Ok(chunk) -> Ok(Some(chunk))
        Error(decode_error) -> Error(error.JsonDecodeError(data, decode_error))
      }
  }
}

// ============================================================================
// Request/Response pairs (sans-io)
// ============================================================================

/// Build a request to create a chat completion.
pub fn create_request(
  config: Config,
  params: CreateChatCompletionRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/chat/completions",
    create_chat_completion_request_to_json(params),
  )
}

/// Parse the response from creating a chat completion.
pub fn create_response(
  response: Response(String),
) -> Result(CreateChatCompletionResponse, GlopenaiError) {
  internal.parse_response(
    response,
    create_chat_completion_response_decoder(),
  )
}

/// Build a request to list stored chat completions.
pub fn list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/chat/completions")
}

/// Parse the response from listing chat completions.
pub fn list_response(
  response: Response(String),
) -> Result(ChatCompletionList, GlopenaiError) {
  internal.parse_response(response, chat_completion_list_decoder())
}

/// Build a request to retrieve a stored chat completion.
pub fn retrieve_request(
  config: Config,
  completion_id: String,
) -> Request(String) {
  internal.get_request(config, "/chat/completions/" <> completion_id)
}

/// Parse the response from retrieving a chat completion.
pub fn retrieve_response(
  response: Response(String),
) -> Result(CreateChatCompletionResponse, GlopenaiError) {
  internal.parse_response(
    response,
    create_chat_completion_response_decoder(),
  )
}

/// Build a request to delete a stored chat completion.
pub fn delete_request(
  config: Config,
  completion_id: String,
) -> Request(String) {
  internal.delete_request(config, "/chat/completions/" <> completion_id)
}

/// Parse the response from deleting a chat completion.
pub fn delete_response(
  response: Response(String),
) -> Result(ChatCompletionDeleted, GlopenaiError) {
  internal.parse_response(response, chat_completion_deleted_decoder())
}
