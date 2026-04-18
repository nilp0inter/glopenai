/// ChatKit API: provision sessions and manage their threads.
///
/// Endpoints:
///
/// - `session_create_request` — `POST /chatkit/sessions`
/// - `session_cancel_request` — `POST /chatkit/sessions/{id}/cancel`
/// - `thread_list_request`    — `GET /chatkit/threads`
/// - `thread_retrieve_request` — `GET /chatkit/threads/{id}`
/// - `thread_delete_request`  — `DELETE /chatkit/threads/{id}`
/// - `thread_items_list_request` — `GET /chatkit/threads/{id}/items`

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/internal
import glopenai/internal/codec

// =============================================================================
// Session types
// =============================================================================

pub type ChatSessionStatus {
  SessionActive
  SessionExpired
  SessionCancelled
}

pub fn chat_session_status_to_json(status: ChatSessionStatus) -> json.Json {
  json.string(case status {
    SessionActive -> "active"
    SessionExpired -> "expired"
    SessionCancelled -> "cancelled"
  })
}

pub fn chat_session_status_decoder() -> decode.Decoder(ChatSessionStatus) {
  use value <- decode.then(decode.string)
  case value {
    "active" -> decode.success(SessionActive)
    "expired" -> decode.success(SessionExpired)
    "cancelled" -> decode.success(SessionCancelled)
    _ -> decode.failure(SessionActive, "ChatSessionStatus")
  }
}

pub type ChatkitWorkflowTracing {
  ChatkitWorkflowTracing(enabled: Bool)
}

pub fn chatkit_workflow_tracing_to_json(
  tracing: ChatkitWorkflowTracing,
) -> json.Json {
  json.object([#("enabled", json.bool(tracing.enabled))])
}

pub fn chatkit_workflow_tracing_decoder() -> decode.Decoder(
  ChatkitWorkflowTracing,
) {
  use enabled <- decode.field("enabled", decode.bool)
  decode.success(ChatkitWorkflowTracing(enabled: enabled))
}

pub type ChatkitWorkflow {
  ChatkitWorkflow(
    id: String,
    version: Option(String),
    /// Workflow state-variable overrides. Values are arbitrary JSON.
    state_variables: Option(Dict(String, Dynamic)),
    tracing: ChatkitWorkflowTracing,
  )
}

pub fn chatkit_workflow_to_json(workflow: ChatkitWorkflow) -> json.Json {
  codec.object_with_optional(
    [
      #("id", json.string(workflow.id)),
      #("tracing", chatkit_workflow_tracing_to_json(workflow.tracing)),
    ],
    [
      codec.optional_field("version", workflow.version, json.string),
      codec.optional_field(
        "state_variables",
        workflow.state_variables,
        state_variables_to_json,
      ),
    ],
  )
}

fn state_variables_to_json(vars: Dict(String, Dynamic)) -> json.Json {
  json.object(
    dict.to_list(vars)
    |> list.map(fn(pair) { #(pair.0, codec.dynamic_to_json(pair.1)) }),
  )
}

pub fn chatkit_workflow_decoder() -> decode.Decoder(ChatkitWorkflow) {
  use id <- decode.field("id", decode.string)
  use version <- decode.optional_field(
    "version",
    None,
    decode.optional(decode.string),
  )
  use state_variables <- decode.optional_field(
    "state_variables",
    None,
    decode.optional(decode.dict(decode.string, decode.dynamic)),
  )
  use tracing <- decode.field("tracing", chatkit_workflow_tracing_decoder())
  decode.success(ChatkitWorkflow(
    id: id,
    version: version,
    state_variables: state_variables,
    tracing: tracing,
  ))
}

pub type ChatSessionRateLimits {
  ChatSessionRateLimits(max_requests_per_1_minute: Int)
}

pub fn chat_session_rate_limits_decoder() -> decode.Decoder(
  ChatSessionRateLimits,
) {
  use max_requests <- decode.field(
    "max_requests_per_1_minute",
    decode.int,
  )
  decode.success(ChatSessionRateLimits(
    max_requests_per_1_minute: max_requests,
  ))
}

pub type ChatSessionAutomaticThreadTitling {
  ChatSessionAutomaticThreadTitling(enabled: Bool)
}

fn chat_session_automatic_thread_titling_decoder() -> decode.Decoder(
  ChatSessionAutomaticThreadTitling,
) {
  use enabled <- decode.field("enabled", decode.bool)
  decode.success(ChatSessionAutomaticThreadTitling(enabled: enabled))
}

pub type ChatSessionFileUpload {
  ChatSessionFileUpload(
    enabled: Bool,
    max_file_size: Option(Int),
    max_files: Option(Int),
  )
}

fn chat_session_file_upload_decoder() -> decode.Decoder(ChatSessionFileUpload) {
  use enabled <- decode.field("enabled", decode.bool)
  use max_file_size <- decode.optional_field(
    "max_file_size",
    None,
    decode.optional(decode.int),
  )
  use max_files <- decode.optional_field(
    "max_files",
    None,
    decode.optional(decode.int),
  )
  decode.success(ChatSessionFileUpload(
    enabled: enabled,
    max_file_size: max_file_size,
    max_files: max_files,
  ))
}

pub type ChatSessionHistory {
  ChatSessionHistory(enabled: Bool, recent_threads: Option(Int))
}

fn chat_session_history_decoder() -> decode.Decoder(ChatSessionHistory) {
  use enabled <- decode.field("enabled", decode.bool)
  use recent_threads <- decode.optional_field(
    "recent_threads",
    None,
    decode.optional(decode.int),
  )
  decode.success(ChatSessionHistory(
    enabled: enabled,
    recent_threads: recent_threads,
  ))
}

pub type ChatSessionChatkitConfiguration {
  ChatSessionChatkitConfiguration(
    automatic_thread_titling: ChatSessionAutomaticThreadTitling,
    file_upload: ChatSessionFileUpload,
    history: ChatSessionHistory,
  )
}

fn chat_session_chatkit_configuration_decoder() -> decode.Decoder(
  ChatSessionChatkitConfiguration,
) {
  use automatic <- decode.field(
    "automatic_thread_titling",
    chat_session_automatic_thread_titling_decoder(),
  )
  use file_upload <- decode.field(
    "file_upload",
    chat_session_file_upload_decoder(),
  )
  use history <- decode.field("history", chat_session_history_decoder())
  decode.success(ChatSessionChatkitConfiguration(
    automatic_thread_titling: automatic,
    file_upload: file_upload,
    history: history,
  ))
}

pub type ChatSessionResource {
  ChatSessionResource(
    id: String,
    object: String,
    expires_at: Int,
    client_secret: String,
    workflow: ChatkitWorkflow,
    user: String,
    rate_limits: ChatSessionRateLimits,
    max_requests_per_1_minute: Int,
    status: ChatSessionStatus,
    chatkit_configuration: ChatSessionChatkitConfiguration,
  )
}

pub fn chat_session_resource_decoder() -> decode.Decoder(ChatSessionResource) {
  use id <- decode.field("id", decode.string)
  use object <- decode.optional_field(
    "object",
    "chatkit.session",
    decode.string,
  )
  use expires_at <- decode.field("expires_at", decode.int)
  use client_secret <- decode.field("client_secret", decode.string)
  use workflow <- decode.field("workflow", chatkit_workflow_decoder())
  use user <- decode.field("user", decode.string)
  use rate_limits <- decode.field(
    "rate_limits",
    chat_session_rate_limits_decoder(),
  )
  use max_requests <- decode.field(
    "max_requests_per_1_minute",
    decode.int,
  )
  use status <- decode.field("status", chat_session_status_decoder())
  use configuration <- decode.field(
    "chatkit_configuration",
    chat_session_chatkit_configuration_decoder(),
  )
  decode.success(ChatSessionResource(
    id: id,
    object: object,
    expires_at: expires_at,
    client_secret: client_secret,
    workflow: workflow,
    user: user,
    rate_limits: rate_limits,
    max_requests_per_1_minute: max_requests,
    status: status,
    chatkit_configuration: configuration,
  ))
}

// --- CreateChatSessionBody and its parameter records ---

pub type WorkflowTracingParam {
  WorkflowTracingParam(enabled: Option(Bool))
}

pub fn new_workflow_tracing_param() -> WorkflowTracingParam {
  WorkflowTracingParam(enabled: None)
}

pub fn workflow_tracing_param_to_json(
  tracing: WorkflowTracingParam,
) -> json.Json {
  codec.object_with_optional(
    [],
    [codec.optional_field("enabled", tracing.enabled, json.bool)],
  )
}

pub type WorkflowParam {
  WorkflowParam(
    id: String,
    version: Option(String),
    state_variables: Option(Dict(String, Dynamic)),
    tracing: Option(WorkflowTracingParam),
  )
}

pub fn new_workflow_param(id: String) -> WorkflowParam {
  WorkflowParam(id: id, version: None, state_variables: None, tracing: None)
}

pub fn workflow_param_with_version(
  workflow: WorkflowParam,
  version: String,
) -> WorkflowParam {
  WorkflowParam(..workflow, version: Some(version))
}

pub fn workflow_param_with_state_variables(
  workflow: WorkflowParam,
  state_variables: Dict(String, Dynamic),
) -> WorkflowParam {
  WorkflowParam(..workflow, state_variables: Some(state_variables))
}

pub fn workflow_param_with_tracing(
  workflow: WorkflowParam,
  tracing: WorkflowTracingParam,
) -> WorkflowParam {
  WorkflowParam(..workflow, tracing: Some(tracing))
}

pub fn workflow_param_to_json(workflow: WorkflowParam) -> json.Json {
  codec.object_with_optional(
    [#("id", json.string(workflow.id))],
    [
      codec.optional_field("version", workflow.version, json.string),
      codec.optional_field(
        "state_variables",
        workflow.state_variables,
        state_variables_to_json,
      ),
      codec.optional_field(
        "tracing",
        workflow.tracing,
        workflow_tracing_param_to_json,
      ),
    ],
  )
}

pub type ExpiresAfterParam {
  ExpiresAfterParam(anchor: String, seconds: Int)
}

/// Default anchor `"created_at"`.
pub fn new_expires_after_param(seconds: Int) -> ExpiresAfterParam {
  ExpiresAfterParam(anchor: "created_at", seconds: seconds)
}

pub fn expires_after_param_to_json(
  expires: ExpiresAfterParam,
) -> json.Json {
  json.object([
    #("anchor", json.string(expires.anchor)),
    #("seconds", json.int(expires.seconds)),
  ])
}

pub type RateLimitsParam {
  RateLimitsParam(max_requests_per_1_minute: Option(Int))
}

pub fn rate_limits_param_to_json(rate_limits: RateLimitsParam) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field(
        "max_requests_per_1_minute",
        rate_limits.max_requests_per_1_minute,
        json.int,
      ),
    ],
  )
}

pub type AutomaticThreadTitlingParam {
  AutomaticThreadTitlingParam(enabled: Option(Bool))
}

pub fn automatic_thread_titling_param_to_json(
  param: AutomaticThreadTitlingParam,
) -> json.Json {
  codec.object_with_optional(
    [],
    [codec.optional_field("enabled", param.enabled, json.bool)],
  )
}

pub type FileUploadParam {
  FileUploadParam(
    enabled: Option(Bool),
    max_file_size: Option(Int),
    max_files: Option(Int),
  )
}

pub fn file_upload_param_to_json(param: FileUploadParam) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field("enabled", param.enabled, json.bool),
      codec.optional_field("max_file_size", param.max_file_size, json.int),
      codec.optional_field("max_files", param.max_files, json.int),
    ],
  )
}

pub type HistoryParam {
  HistoryParam(enabled: Option(Bool), recent_threads: Option(Int))
}

pub fn history_param_to_json(param: HistoryParam) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field("enabled", param.enabled, json.bool),
      codec.optional_field("recent_threads", param.recent_threads, json.int),
    ],
  )
}

pub type ChatkitConfigurationParam {
  ChatkitConfigurationParam(
    automatic_thread_titling: Option(AutomaticThreadTitlingParam),
    file_upload: Option(FileUploadParam),
    history: Option(HistoryParam),
  )
}

pub fn chatkit_configuration_param_to_json(
  config: ChatkitConfigurationParam,
) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field(
        "automatic_thread_titling",
        config.automatic_thread_titling,
        automatic_thread_titling_param_to_json,
      ),
      codec.optional_field(
        "file_upload",
        config.file_upload,
        file_upload_param_to_json,
      ),
      codec.optional_field(
        "history",
        config.history,
        history_param_to_json,
      ),
    ],
  )
}

pub type CreateChatSessionBody {
  CreateChatSessionBody(
    workflow: WorkflowParam,
    user: String,
    expires_after: Option(ExpiresAfterParam),
    rate_limits: Option(RateLimitsParam),
    chatkit_configuration: Option(ChatkitConfigurationParam),
  )
}

pub fn new_create_chat_session_body(
  workflow: WorkflowParam,
  user: String,
) -> CreateChatSessionBody {
  CreateChatSessionBody(
    workflow: workflow,
    user: user,
    expires_after: None,
    rate_limits: None,
    chatkit_configuration: None,
  )
}

pub fn with_expires_after(
  body: CreateChatSessionBody,
  expires_after: ExpiresAfterParam,
) -> CreateChatSessionBody {
  CreateChatSessionBody(..body, expires_after: Some(expires_after))
}

pub fn with_rate_limits(
  body: CreateChatSessionBody,
  rate_limits: RateLimitsParam,
) -> CreateChatSessionBody {
  CreateChatSessionBody(..body, rate_limits: Some(rate_limits))
}

pub fn with_chatkit_configuration(
  body: CreateChatSessionBody,
  configuration: ChatkitConfigurationParam,
) -> CreateChatSessionBody {
  CreateChatSessionBody(..body, chatkit_configuration: Some(configuration))
}

pub fn create_chat_session_body_to_json(
  body: CreateChatSessionBody,
) -> json.Json {
  codec.object_with_optional(
    [
      #("workflow", workflow_param_to_json(body.workflow)),
      #("user", json.string(body.user)),
    ],
    [
      codec.optional_field(
        "expires_after",
        body.expires_after,
        expires_after_param_to_json,
      ),
      codec.optional_field(
        "rate_limits",
        body.rate_limits,
        rate_limits_param_to_json,
      ),
      codec.optional_field(
        "chatkit_configuration",
        body.chatkit_configuration,
        chatkit_configuration_param_to_json,
      ),
    ],
  )
}

// =============================================================================
// Thread types
// =============================================================================

/// Status discriminator on a `ThreadResource`. Note: in the wire format these
/// fields are flattened directly onto the thread object, with `type`
/// distinguishing the variant.
pub type ThreadStatus {
  ThreadActive
  ThreadLocked(reason: Option(String))
  ThreadClosed(reason: Option(String))
}

pub fn thread_status_decoder() -> decode.Decoder(ThreadStatus) {
  use status_type <- decode.field("type", decode.string)
  case status_type {
    "active" -> decode.success(ThreadActive)
    "locked" -> {
      use reason <- decode.optional_field(
        "reason",
        None,
        decode.optional(decode.string),
      )
      decode.success(ThreadLocked(reason: reason))
    }
    "closed" -> {
      use reason <- decode.optional_field(
        "reason",
        None,
        decode.optional(decode.string),
      )
      decode.success(ThreadClosed(reason: reason))
    }
    _ -> decode.failure(ThreadActive, "ThreadStatus")
  }
}

// --- Annotations ---

pub type FileAnnotationSource {
  FileAnnotationSource(filename: String)
}

fn file_annotation_source_decoder() -> decode.Decoder(FileAnnotationSource) {
  use filename <- decode.field("filename", decode.string)
  decode.success(FileAnnotationSource(filename: filename))
}

pub type UrlAnnotationSource {
  UrlAnnotationSource(url: String)
}

fn url_annotation_source_decoder() -> decode.Decoder(UrlAnnotationSource) {
  use url <- decode.field("url", decode.string)
  decode.success(UrlAnnotationSource(url: url))
}

pub type Annotation {
  FileAnnotation(source: FileAnnotationSource)
  UrlAnnotation(source: UrlAnnotationSource)
}

pub fn annotation_decoder() -> decode.Decoder(Annotation) {
  use annotation_type <- decode.field("type", decode.string)
  case annotation_type {
    "file" -> {
      use source <- decode.field("source", file_annotation_source_decoder())
      decode.success(FileAnnotation(source: source))
    }
    "url" -> {
      use source <- decode.field("source", url_annotation_source_decoder())
      decode.success(UrlAnnotation(source: source))
    }
    _ ->
      decode.failure(
        FileAnnotation(FileAnnotationSource("")),
        "Annotation",
      )
  }
}

pub type ResponseOutputText {
  ResponseOutputText(
    output_text_type: String,
    text: String,
    annotations: List(Annotation),
  )
}

fn response_output_text_decoder() -> decode.Decoder(ResponseOutputText) {
  use output_text_type <- decode.optional_field(
    "type",
    "output_text",
    decode.string,
  )
  use text <- decode.field("text", decode.string)
  use annotations <- decode.optional_field(
    "annotations",
    [],
    decode.list(annotation_decoder()),
  )
  decode.success(ResponseOutputText(
    output_text_type: output_text_type,
    text: text,
    annotations: annotations,
  ))
}

// --- Attachment / InferenceOptions ---

pub type AttachmentType {
  AttachmentImage
  AttachmentFile
}

fn attachment_type_decoder() -> decode.Decoder(AttachmentType) {
  use value <- decode.then(decode.string)
  case value {
    "image" -> decode.success(AttachmentImage)
    "file" -> decode.success(AttachmentFile)
    _ -> decode.failure(AttachmentFile, "AttachmentType")
  }
}

pub type Attachment {
  Attachment(
    attachment_type: AttachmentType,
    id: String,
    name: String,
    mime_type: String,
    preview_url: Option(String),
  )
}

fn attachment_decoder() -> decode.Decoder(Attachment) {
  use attachment_type <- decode.field("type", attachment_type_decoder())
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use mime_type <- decode.field("mime_type", decode.string)
  use preview_url <- decode.field(
    "preview_url",
    decode.optional(decode.string),
  )
  decode.success(Attachment(
    attachment_type: attachment_type,
    id: id,
    name: name,
    mime_type: mime_type,
    preview_url: preview_url,
  ))
}

pub type ToolChoice {
  ToolChoice(id: String)
}

fn tool_choice_decoder() -> decode.Decoder(ToolChoice) {
  use id <- decode.field("id", decode.string)
  decode.success(ToolChoice(id: id))
}

pub type InferenceOptions {
  InferenceOptions(tool_choice: Option(ToolChoice), model: Option(String))
}

fn inference_options_decoder() -> decode.Decoder(InferenceOptions) {
  use tool_choice <- decode.optional_field(
    "tool_choice",
    None,
    decode.optional(tool_choice_decoder()),
  )
  use model <- decode.optional_field(
    "model",
    None,
    decode.optional(decode.string),
  )
  decode.success(InferenceOptions(tool_choice: tool_choice, model: model))
}

// --- UserMessageContent ---

pub type UserMessageContent {
  InputTextContent(text: String)
  QuotedTextContent(text: String)
}

fn user_message_content_decoder() -> decode.Decoder(UserMessageContent) {
  use content_type <- decode.field("type", decode.string)
  case content_type {
    "input_text" -> {
      use text <- decode.field("text", decode.string)
      decode.success(InputTextContent(text: text))
    }
    "quoted_text" -> {
      use text <- decode.field("text", decode.string)
      decode.success(QuotedTextContent(text: text))
    }
    _ -> decode.failure(InputTextContent(""), "UserMessageContent")
  }
}

// --- Task and TaskGroup ---

pub type TaskType {
  TaskCustom
  TaskThought
}

fn task_type_decoder() -> decode.Decoder(TaskType) {
  use value <- decode.then(decode.string)
  case value {
    "custom" -> decode.success(TaskCustom)
    "thought" -> decode.success(TaskThought)
    _ -> decode.failure(TaskCustom, "TaskType")
  }
}

pub type TaskGroupTask {
  TaskGroupTask(
    task_type: TaskType,
    heading: Option(String),
    summary: Option(String),
  )
}

fn task_group_task_decoder() -> decode.Decoder(TaskGroupTask) {
  use task_type <- decode.field("task_type", task_type_decoder())
  use heading <- decode.field("heading", decode.optional(decode.string))
  use summary <- decode.field("summary", decode.optional(decode.string))
  decode.success(TaskGroupTask(
    task_type: task_type,
    heading: heading,
    summary: summary,
  ))
}

// --- ClientToolCallStatus ---

pub type ClientToolCallStatus {
  ClientToolInProgress
  ClientToolCompleted
}

fn client_tool_call_status_decoder() -> decode.Decoder(ClientToolCallStatus) {
  use value <- decode.then(decode.string)
  case value {
    "in_progress" -> decode.success(ClientToolInProgress)
    "completed" -> decode.success(ClientToolCompleted)
    _ -> decode.failure(ClientToolInProgress, "ClientToolCallStatus")
  }
}

// --- ThreadItem (tagged union of 6 variants) ---

pub type ThreadItem {
  UserMessageItem(
    id: String,
    object: String,
    created_at: Int,
    thread_id: String,
    content: List(UserMessageContent),
    attachments: List(Attachment),
    inference_options: Option(InferenceOptions),
  )
  AssistantMessageItem(
    id: String,
    object: String,
    created_at: Int,
    thread_id: String,
    content: List(ResponseOutputText),
  )
  WidgetMessageItem(
    id: String,
    object: String,
    created_at: Int,
    thread_id: String,
    widget: String,
  )
  ClientToolCallItem(
    id: String,
    object: String,
    created_at: Int,
    thread_id: String,
    status: ClientToolCallStatus,
    call_id: String,
    name: String,
    arguments: String,
    output: Option(String),
  )
  TaskItem(
    id: String,
    object: String,
    created_at: Int,
    thread_id: String,
    task_type: TaskType,
    heading: Option(String),
    summary: Option(String),
  )
  TaskGroupItem(
    id: String,
    object: String,
    created_at: Int,
    thread_id: String,
    tasks: List(TaskGroupTask),
  )
}

pub fn thread_item_decoder() -> decode.Decoder(ThreadItem) {
  use item_type <- decode.field("type", decode.string)
  use id <- decode.field("id", decode.string)
  use object <- decode.optional_field(
    "object",
    "chatkit.thread_item",
    decode.string,
  )
  use created_at <- decode.field("created_at", decode.int)
  use thread_id <- decode.field("thread_id", decode.string)

  case item_type {
    "chatkit.user_message" -> {
      use content <- decode.field(
        "content",
        decode.list(user_message_content_decoder()),
      )
      use attachments <- decode.optional_field(
        "attachments",
        [],
        decode.list(attachment_decoder()),
      )
      use inference_options <- decode.optional_field(
        "inference_options",
        None,
        decode.optional(inference_options_decoder()),
      )
      decode.success(UserMessageItem(
        id: id,
        object: object,
        created_at: created_at,
        thread_id: thread_id,
        content: content,
        attachments: attachments,
        inference_options: inference_options,
      ))
    }
    "chatkit.assistant_message" -> {
      use content <- decode.field(
        "content",
        decode.list(response_output_text_decoder()),
      )
      decode.success(AssistantMessageItem(
        id: id,
        object: object,
        created_at: created_at,
        thread_id: thread_id,
        content: content,
      ))
    }
    "chatkit.widget" -> {
      use widget <- decode.field("widget", decode.string)
      decode.success(WidgetMessageItem(
        id: id,
        object: object,
        created_at: created_at,
        thread_id: thread_id,
        widget: widget,
      ))
    }
    "chatkit.client_tool_call" -> {
      use status <- decode.field("status", client_tool_call_status_decoder())
      use call_id <- decode.field("call_id", decode.string)
      use name <- decode.field("name", decode.string)
      use arguments <- decode.field("arguments", decode.string)
      use output <- decode.field("output", decode.optional(decode.string))
      decode.success(ClientToolCallItem(
        id: id,
        object: object,
        created_at: created_at,
        thread_id: thread_id,
        status: status,
        call_id: call_id,
        name: name,
        arguments: arguments,
        output: output,
      ))
    }
    "chatkit.task" -> {
      use task_type <- decode.field("task_type", task_type_decoder())
      use heading <- decode.field("heading", decode.optional(decode.string))
      use summary <- decode.field("summary", decode.optional(decode.string))
      decode.success(TaskItem(
        id: id,
        object: object,
        created_at: created_at,
        thread_id: thread_id,
        task_type: task_type,
        heading: heading,
        summary: summary,
      ))
    }
    "chatkit.task_group" -> {
      use tasks <- decode.field(
        "tasks",
        decode.list(task_group_task_decoder()),
      )
      decode.success(TaskGroupItem(
        id: id,
        object: object,
        created_at: created_at,
        thread_id: thread_id,
        tasks: tasks,
      ))
    }
    _ ->
      decode.failure(
        WidgetMessageItem(
          id: "",
          object: "",
          created_at: 0,
          thread_id: "",
          widget: "",
        ),
        "ThreadItem",
      )
  }
}

// --- ThreadResource ---

pub type ThreadResource {
  ThreadResource(
    id: String,
    object: String,
    created_at: Int,
    title: Option(String),
    /// Status discriminator. Wire format flattens these fields onto the
    /// thread object (e.g. `"type": "active"` or `"type": "locked",
    /// "reason": "..."`).
    status: ThreadStatus,
    user: String,
    items: Option(ThreadItemListResource),
  )
}

pub fn thread_resource_decoder() -> decode.Decoder(ThreadResource) {
  use id <- decode.field("id", decode.string)
  use object <- decode.optional_field(
    "object",
    "chatkit.thread",
    decode.string,
  )
  use created_at <- decode.field("created_at", decode.int)
  use title <- decode.field("title", decode.optional(decode.string))
  // Status fields are flattened — pull them off the same decoder root.
  use status <- decode.then(thread_status_decoder())
  use user <- decode.field("user", decode.string)
  use items <- decode.optional_field(
    "items",
    None,
    decode.optional(thread_item_list_resource_decoder()),
  )
  decode.success(ThreadResource(
    id: id,
    object: object,
    created_at: created_at,
    title: title,
    status: status,
    user: user,
    items: items,
  ))
}

pub type ThreadListResource {
  ThreadListResource(
    object: String,
    data: List(ThreadResource),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

fn thread_list_resource_decoder() -> decode.Decoder(ThreadListResource) {
  use object <- decode.optional_field("object", "list", decode.string)
  use data <- decode.field("data", decode.list(thread_resource_decoder()))
  use first_id <- decode.field("first_id", decode.optional(decode.string))
  use last_id <- decode.field("last_id", decode.optional(decode.string))
  use has_more <- decode.field("has_more", decode.bool)
  decode.success(ThreadListResource(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

pub type DeletedThreadResource {
  DeletedThreadResource(id: String, object: String, deleted: Bool)
}

fn deleted_thread_resource_decoder() -> decode.Decoder(DeletedThreadResource) {
  use id <- decode.field("id", decode.string)
  use object <- decode.optional_field(
    "object",
    "chatkit.thread.deleted",
    decode.string,
  )
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeletedThreadResource(
    id: id,
    object: object,
    deleted: deleted,
  ))
}

pub type ThreadItemListResource {
  ThreadItemListResource(
    object: String,
    data: List(ThreadItem),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

fn thread_item_list_resource_decoder() -> decode.Decoder(
  ThreadItemListResource,
) {
  use object <- decode.optional_field("object", "list", decode.string)
  use data <- decode.field("data", decode.list(thread_item_decoder()))
  use first_id <- decode.field("first_id", decode.optional(decode.string))
  use last_id <- decode.field("last_id", decode.optional(decode.string))
  use has_more <- decode.field("has_more", decode.bool)
  decode.success(ThreadItemListResource(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

// =============================================================================
// Pagination queries
// =============================================================================

pub type ListChatKitThreadsOrder {
  ThreadsAsc
  ThreadsDesc
}

fn threads_order_to_string(order: ListChatKitThreadsOrder) -> String {
  case order {
    ThreadsAsc -> "asc"
    ThreadsDesc -> "desc"
  }
}

pub type ListChatKitThreadsQuery {
  ListChatKitThreadsQuery(
    limit: Option(Int),
    order: Option(ListChatKitThreadsOrder),
    after: Option(String),
    before: Option(String),
    user: Option(String),
  )
}

pub fn empty_list_threads_query() -> ListChatKitThreadsQuery {
  ListChatKitThreadsQuery(
    limit: None,
    order: None,
    after: None,
    before: None,
    user: None,
  )
}

fn list_threads_query_pairs(
  query: ListChatKitThreadsQuery,
) -> List(#(String, String)) {
  list.flatten([
    optional_string_pair("limit", query.limit, int.to_string),
    optional_string_pair("order", query.order, threads_order_to_string),
    optional_string_pair("after", query.after, fn(s) { s }),
    optional_string_pair("before", query.before, fn(s) { s }),
    optional_string_pair("user", query.user, fn(s) { s }),
  ])
}

pub type ListChatKitThreadItemsOrder {
  ItemsAsc
  ItemsDesc
}

fn items_order_to_string(order: ListChatKitThreadItemsOrder) -> String {
  case order {
    ItemsAsc -> "asc"
    ItemsDesc -> "desc"
  }
}

pub type ListChatKitThreadItemsQuery {
  ListChatKitThreadItemsQuery(
    limit: Option(Int),
    order: Option(ListChatKitThreadItemsOrder),
    after: Option(String),
    before: Option(String),
  )
}

pub fn empty_list_thread_items_query() -> ListChatKitThreadItemsQuery {
  ListChatKitThreadItemsQuery(
    limit: None,
    order: None,
    after: None,
    before: None,
  )
}

fn list_thread_items_query_pairs(
  query: ListChatKitThreadItemsQuery,
) -> List(#(String, String)) {
  list.flatten([
    optional_string_pair("limit", query.limit, int.to_string),
    optional_string_pair("order", query.order, items_order_to_string),
    optional_string_pair("after", query.after, fn(s) { s }),
    optional_string_pair("before", query.before, fn(s) { s }),
  ])
}

fn optional_string_pair(
  key: String,
  value: Option(a),
  encode: fn(a) -> String,
) -> List(#(String, String)) {
  case value {
    Some(v) -> [#(key, encode(v))]
    None -> []
  }
}

// =============================================================================
// Endpoints
// =============================================================================

pub fn session_create_request(
  config: Config,
  body: CreateChatSessionBody,
) -> Request(String) {
  internal.post_request(
    config,
    "/chatkit/sessions",
    create_chat_session_body_to_json(body),
  )
}

pub fn session_create_response(
  response: Response(String),
) -> Result(ChatSessionResource, GlopenaiError) {
  internal.parse_response(response, chat_session_resource_decoder())
}

pub fn session_cancel_request(
  config: Config,
  session_id: String,
) -> Request(String) {
  internal.post_request(
    config,
    "/chatkit/sessions/" <> session_id <> "/cancel",
    json.object([]),
  )
}

pub fn session_cancel_response(
  response: Response(String),
) -> Result(ChatSessionResource, GlopenaiError) {
  internal.parse_response(response, chat_session_resource_decoder())
}

pub fn thread_list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/chatkit/threads")
}

pub fn thread_list_request_with_query(
  config: Config,
  query: ListChatKitThreadsQuery,
) -> Request(String) {
  internal.get_request(config, "/chatkit/threads")
  |> request.set_query(list_threads_query_pairs(query))
}

pub fn thread_list_response(
  response: Response(String),
) -> Result(ThreadListResource, GlopenaiError) {
  internal.parse_response(response, thread_list_resource_decoder())
}

pub fn thread_retrieve_request(
  config: Config,
  thread_id: String,
) -> Request(String) {
  internal.get_request(config, "/chatkit/threads/" <> thread_id)
}

pub fn thread_retrieve_response(
  response: Response(String),
) -> Result(ThreadResource, GlopenaiError) {
  internal.parse_response(response, thread_resource_decoder())
}

pub fn thread_delete_request(
  config: Config,
  thread_id: String,
) -> Request(String) {
  internal.delete_request(config, "/chatkit/threads/" <> thread_id)
}

pub fn thread_delete_response(
  response: Response(String),
) -> Result(DeletedThreadResource, GlopenaiError) {
  internal.parse_response(response, deleted_thread_resource_decoder())
}

pub fn thread_items_list_request(
  config: Config,
  thread_id: String,
) -> Request(String) {
  internal.get_request(config, "/chatkit/threads/" <> thread_id <> "/items")
}

pub fn thread_items_list_request_with_query(
  config: Config,
  thread_id: String,
  query: ListChatKitThreadItemsQuery,
) -> Request(String) {
  internal.get_request(config, "/chatkit/threads/" <> thread_id <> "/items")
  |> request.set_query(list_thread_items_query_pairs(query))
}

pub fn thread_items_list_response(
  response: Response(String),
) -> Result(ThreadItemListResource, GlopenaiError) {
  internal.parse_response(response, thread_item_list_resource_decoder())
}
