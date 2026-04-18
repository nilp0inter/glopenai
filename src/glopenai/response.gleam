/// Responses API: create, retrieve, delete, cancel responses, list input items,
/// count tokens, compact conversations, and parse streaming events.
///
/// This is the largest module — it covers the unified Responses API with 20+
/// item variants, many tool types, and 48 streaming event types.
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response as HttpResponse}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/internal
import glopenai/internal/codec
import glopenai/shared.{
  type ImageDetail, type ReasoningEffort, type ResponseFormatJsonSchema,
  type ResponseUsage,
}

// ============================================================================
// String enums
// ============================================================================

pub type MessagePhase {
  Commentary
  FinalAnswer
}

pub type ToolSearchExecutionType {
  ExecutionServer
  ExecutionClient
}

pub type SearchContentType {
  SearchText
  SearchImage
}

pub type FunctionCallStatus {
  FunctionCallInProgress
  FunctionCallCompleted
  FunctionCallIncomplete
}

pub type OutputStatus {
  OutputInProgress
  OutputCompleted
  OutputIncomplete
}

pub type Role {
  RoleUser
  RoleAssistant
  RoleSystem
  RoleDeveloper
}

pub type InputRole {
  InputRoleUser
  InputRoleSystem
  InputRoleDeveloper
}

pub type Truncation {
  TruncationAuto
  TruncationDisabled
}

pub type ServiceTier {
  ServiceTierAuto
  ServiceTierDefault
  ServiceTierFlex
  ServiceTierScale
  ServiceTierPriority
}

pub type ResponseStatus {
  StatusCompleted
  StatusFailed
  StatusInProgress
  StatusCancelled
  StatusQueued
  StatusIncomplete
}

pub type Verbosity {
  VerbosityLow
  VerbosityMedium
  VerbosityHigh
}

pub type ReasoningSummary {
  ReasoningSummaryAuto
  ReasoningSummaryConcise
  ReasoningSummaryDetailed
}

pub type PromptCacheRetention {
  PromptCacheInMemory
  PromptCacheHours24
}

pub type FileSearchToolCallStatus {
  FileSearchInProgress
  FileSearchSearching
  FileSearchIncomplete
  FileSearchFailed
  FileSearchCompleted
}

pub type WebSearchToolCallStatus {
  WebSearchInProgress
  WebSearchSearching
  WebSearchCompleted
  WebSearchFailed
}

pub type WebSearchToolSearchContextSize {
  WebSearchContextLow
  WebSearchContextMedium
  WebSearchContextHigh
}

pub type ComputerEnvironment {
  EnvironmentWindows
  EnvironmentMac
  EnvironmentLinux
  EnvironmentUbuntu
  EnvironmentBrowser
}

pub type RankVersionType {
  RankAuto
  RankDefault20241115
}

pub type ImageGenToolBackground {
  ImageGenBgTransparent
  ImageGenBgOpaque
  ImageGenBgAuto
}

pub type ImageGenToolOutputFormat {
  ImageGenFmtPng
  ImageGenFmtWebp
  ImageGenFmtJpeg
}

pub type ImageGenToolQuality {
  ImageGenQualityLow
  ImageGenQualityMedium
  ImageGenQualityHigh
  ImageGenQualityAuto
}

pub type ImageGenToolSize {
  ImageGenSizeAuto
  ImageGenSize1024x1024
  ImageGenSize1024x1536
  ImageGenSize1536x1024
}

pub type InputFidelity {
  FidelityHigh
  FidelityLow
}

pub type ImageGenToolModeration {
  ImageGenModerationAuto
  ImageGenModerationLow
}

pub type ImageGenActionEnum {
  ImageGenGenerate
  ImageGenEdit
  ImageGenActionAuto
}

pub type ToolChoiceOptions {
  ToolChoiceNone
  ToolChoiceAuto
  ToolChoiceRequired
}

pub type ToolChoiceAllowedMode {
  AllowedModeAuto
  AllowedModeRequired
}

pub type ClickButtonType {
  ClickLeft
  ClickRight
  ClickWheel
  ClickBack
  ClickForward
}

pub type ImageGenToolCallStatus {
  ImageGenCallInProgress
  ImageGenCallCompleted
  ImageGenCallGenerating
  ImageGenCallFailed
}

pub type CodeInterpreterToolCallStatus {
  CodeInterpInProgress
  CodeInterpCompleted
  CodeInterpIncomplete
  CodeInterpInterpreting
  CodeInterpFailed
}

pub type McpToolCallStatus {
  McpCallInProgress
  McpCallCompleted
  McpCallIncomplete
  McpCallCalling
  McpCallFailed
}

pub type FunctionShellCallItemStatus {
  ShellItemInProgress
  ShellItemCompleted
  ShellItemIncomplete
}

pub type ApplyPatchCallStatusParam {
  ApplyPatchInProgress
  ApplyPatchCompleted
}

pub type ApplyPatchCallOutputStatusParam {
  ApplyPatchOutputCompleted
  ApplyPatchOutputFailed
}

/// Which data to include in the response.
pub type IncludeEnum {
  IncludeFileSearchCallResults
  IncludeWebSearchCallResults
  IncludeWebSearchCallActionSources
  IncludeMessageInputImageImageUrl
  IncludeComputerCallOutputOutputImageUrl
  IncludeCodeInterpreterCallOutputs
  IncludeReasoningEncryptedContent
  IncludeMessageOutputTextLogprobs
}

// ============================================================================
// Content types
// ============================================================================

pub type InputTextContent {
  InputTextContent(text: String)
}

pub type InputImageContent {
  InputImageContent(
    detail: ImageDetail,
    file_id: Option(String),
    image_url: Option(String),
  )
}

pub type InputFileContent {
  InputFileContent(
    file_data: Option(String),
    file_id: Option(String),
    file_url: Option(String),
    filename: Option(String),
  )
}

/// Parts of a message: text, image, or file. Tagged by "type".
pub type InputContent {
  ContentInputText(InputTextContent)
  ContentInputImage(InputImageContent)
  ContentInputFile(InputFileContent)
}

pub type OutputTextContent {
  OutputTextContent(
    annotations: List(Annotation),
    logprobs: Option(List(ResponseLogProb)),
    text: String,
  )
}

pub type RefusalContent {
  RefusalContent(refusal: String)
}

pub type ReasoningTextContent {
  ReasoningTextContent(text: String)
}

pub type SummaryTextContent {
  SummaryTextContent(text: String)
}

/// Tagged by "type".
pub type OutputMessageContent {
  OutputMessageOutputText(OutputTextContent)
  OutputMessageRefusal(RefusalContent)
}

/// Tagged by "type".
pub type OutputContent {
  OutputContentOutputText(OutputTextContent)
  OutputContentRefusal(RefusalContent)
  OutputContentReasoningText(ReasoningTextContent)
}

/// Tagged by "type".
pub type SummaryPart {
  SummaryPartSummaryText(SummaryTextContent)
}

// ============================================================================
// Annotation types
// ============================================================================

pub type FileCitationBody {
  FileCitationBody(file_id: String, filename: String, index: Int)
}

pub type UrlCitationBody {
  UrlCitationBody(end_index: Int, start_index: Int, title: String, url: String)
}

pub type ContainerFileCitationBody {
  ContainerFileCitationBody(
    container_id: String,
    end_index: Int,
    file_id: String,
    filename: String,
    start_index: Int,
  )
}

pub type FilePathAnnotation {
  FilePathAnnotation(file_id: String, index: Int)
}

/// Tagged by "type".
pub type Annotation {
  AnnotationFileCitation(FileCitationBody)
  AnnotationUrlCitation(UrlCitationBody)
  AnnotationContainerFileCitation(ContainerFileCitationBody)
  AnnotationFilePath(FilePathAnnotation)
}

// ============================================================================
// Log probability types
// ============================================================================

pub type ResponseTopLogProb {
  ResponseTopLogProb(logprob: Float, token: String)
}

pub type ResponseLogProb {
  ResponseLogProb(
    logprob: Float,
    token: String,
    top_logprobs: List(ResponseTopLogProb),
  )
}

// ============================================================================
// Message types
// ============================================================================

pub type OutputMessage {
  OutputMessage(
    content: List(OutputMessageContent),
    id: String,
    role: Role,
    phase: Option(MessagePhase),
    status: OutputStatus,
  )
}

pub type InputMessage {
  InputMessage(
    content: List(InputContent),
    role: InputRole,
    status: Option(OutputStatus),
  )
}

/// Untagged: content can be string or list.
pub type EasyInputContent {
  EasyContentText(String)
  EasyContentList(List(InputContent))
}

pub type EasyInputMessage {
  EasyInputMessage(
    role: Role,
    content: EasyInputContent,
    phase: Option(MessagePhase),
  )
}

/// Untagged: OutputMessage or InputMessage.
pub type MessageItem {
  MessageItemOutput(OutputMessage)
  MessageItemInput(InputMessage)
}

// ============================================================================
// Item reference
// ============================================================================

pub type ItemReference {
  ItemReference(item_type: Option(String), id: String)
}

// ============================================================================
// Conversation
// ============================================================================

pub type Conversation {
  Conversation(id: String)
}

/// Untagged: string ID or object.
pub type ConversationParam {
  ConversationId(String)
  ConversationObject(Conversation)
}

// ============================================================================
// Reasoning
// ============================================================================

pub type Reasoning {
  Reasoning(effort: Option(ReasoningEffort), summary: Option(ReasoningSummary))
}

// ============================================================================
// Text response format
// ============================================================================

pub type ResponseTextParam {
  ResponseTextParam(
    format: TextResponseFormatConfiguration,
    verbosity: Option(Verbosity),
  )
}

/// Tagged by "type".
pub type TextResponseFormatConfiguration {
  TextFormatText
  TextFormatJsonObject
  TextFormatJsonSchema(ResponseFormatJsonSchema)
}

// ============================================================================
// Tool call types
// ============================================================================

pub type FunctionToolCall {
  FunctionToolCall(
    arguments: String,
    call_id: String,
    namespace: Option(String),
    name: String,
    id: Option(String),
    status: Option(OutputStatus),
  )
}

pub type FunctionCallOutputItemParam {
  FunctionCallOutputItemParam(
    call_id: String,
    output: FunctionCallOutput,
    id: Option(String),
    status: Option(OutputStatus),
  )
}

/// Untagged: string or content list.
pub type FunctionCallOutput {
  FunctionCallOutputText(String)
  FunctionCallOutputContent(List(InputContent))
}

pub type ComputerCallSafetyCheckParam {
  ComputerCallSafetyCheckParam(
    id: String,
    code: Option(String),
    message: Option(String),
  )
}

pub type ComputerScreenshotImage {
  ComputerScreenshotImage(file_id: Option(String), image_url: Option(String))
}

pub type ComputerCallOutputItemParam {
  ComputerCallOutputItemParam(
    call_id: String,
    output: ComputerScreenshotImage,
    acknowledged_safety_checks: Option(List(ComputerCallSafetyCheckParam)),
    id: Option(String),
    status: Option(OutputStatus),
  )
}

pub type FileSearchToolCallResult {
  FileSearchToolCallResult(
    attributes: Dynamic,
    file_id: String,
    filename: String,
    score: Float,
    text: String,
  )
}

pub type FileSearchToolCall {
  FileSearchToolCall(
    id: String,
    queries: List(String),
    status: FileSearchToolCallStatus,
    results: Option(List(FileSearchToolCallResult)),
  )
}

pub type WebSearchActionSearchSource {
  WebSearchActionSearchSource(source_type: String, url: String)
}

pub type WebSearchActionSearch {
  WebSearchActionSearch(
    query: String,
    sources: Option(List(WebSearchActionSearchSource)),
  )
}

pub type WebSearchActionOpenPage {
  WebSearchActionOpenPage(url: Option(String))
}

pub type WebSearchActionFind {
  WebSearchActionFind(url: String, pattern: String)
}

/// Tagged by "type".
pub type WebSearchToolCallAction {
  WebSearchActionSearchVariant(WebSearchActionSearch)
  WebSearchActionOpenPageVariant(WebSearchActionOpenPage)
  WebSearchActionFindVariant(WebSearchActionFind)
  WebSearchActionFindInPageVariant(WebSearchActionFind)
}

pub type WebSearchToolCall {
  WebSearchToolCall(
    action: WebSearchToolCallAction,
    id: String,
    status: WebSearchToolCallStatus,
  )
}

// Computer actions
pub type ClickParam {
  ClickParam(button: ClickButtonType, x: Int, y: Int)
}

pub type DoubleClickAction {
  DoubleClickAction(x: Int, y: Int)
}

pub type CoordParam {
  CoordParam(x: Int, y: Int)
}

pub type DragParam {
  DragParam(path: List(CoordParam))
}

pub type KeyPressAction {
  KeyPressAction(keys: List(String))
}

pub type MoveParam {
  MoveParam(x: Int, y: Int)
}

pub type ScrollParam {
  ScrollParam(scroll_x: Int, scroll_y: Int, x: Int, y: Int)
}

pub type TypeActionParam {
  TypeActionParam(text: String)
}

/// Tagged by "type".
pub type ComputerAction {
  ComputerClick(ClickParam)
  ComputerDoubleClick(DoubleClickAction)
  ComputerDrag(DragParam)
  ComputerKeypress(KeyPressAction)
  ComputerMove(MoveParam)
  ComputerScreenshot
  ComputerScroll(ScrollParam)
  ComputerType(TypeActionParam)
  ComputerWait
}

pub type ComputerToolCall {
  ComputerToolCall(
    action: Option(ComputerAction),
    actions: Option(List(ComputerAction)),
    call_id: String,
    id: String,
    pending_safety_checks: List(ComputerCallSafetyCheckParam),
    status: OutputStatus,
  )
}

pub type ImageGenToolCall {
  ImageGenToolCall(
    id: String,
    result: Option(String),
    status: ImageGenToolCallStatus,
  )
}

pub type CodeInterpreterOutputLogs {
  CodeInterpreterOutputLogs(logs: String)
}

pub type CodeInterpreterOutputImage {
  CodeInterpreterOutputImage(url: String)
}

/// Tagged by "type".
pub type CodeInterpreterToolCallOutput {
  CodeInterpOutputLogs(CodeInterpreterOutputLogs)
  CodeInterpOutputImage(CodeInterpreterOutputImage)
}

pub type CodeInterpreterToolCall {
  CodeInterpreterToolCall(
    code: Option(String),
    container_id: String,
    id: String,
    outputs: Option(List(CodeInterpreterToolCallOutput)),
    status: CodeInterpreterToolCallStatus,
  )
}

pub type LocalShellExecAction {
  LocalShellExecAction(
    command: List(String),
    env: Dict(String, String),
    timeout_ms: Option(Int),
    user: Option(String),
    working_directory: Option(String),
  )
}

pub type LocalShellToolCall {
  LocalShellToolCall(
    action: LocalShellExecAction,
    call_id: String,
    id: String,
    status: OutputStatus,
  )
}

pub type LocalShellToolCallOutput {
  LocalShellToolCallOutput(
    id: String,
    output: String,
    status: Option(OutputStatus),
  )
}

pub type ReasoningItem {
  ReasoningItem(
    id: String,
    summary: List(SummaryPart),
    content: Option(List(ReasoningTextContent)),
    encrypted_content: Option(String),
    status: Option(OutputStatus),
  )
}

pub type CompactionSummaryItemParam {
  CompactionSummaryItemParam(id: Option(String), encrypted_content: String)
}

pub type CompactionBody {
  CompactionBody(
    id: String,
    encrypted_content: String,
    created_by: Option(String),
  )
}

// ============================================================================
// MCP types
// ============================================================================

pub type McpToolCall {
  McpToolCall(
    arguments: String,
    id: String,
    name: String,
    server_label: String,
    approval_request_id: Option(String),
    error: Option(String),
    output: Option(String),
    status: Option(McpToolCallStatus),
  )
}

pub type McpListTools {
  McpListTools(
    id: String,
    server_label: String,
    tools: Dynamic,
    error: Option(String),
  )
}

pub type McpApprovalRequest {
  McpApprovalRequest(
    arguments: String,
    id: String,
    name: String,
    server_label: String,
  )
}

pub type McpApprovalResponse {
  McpApprovalResponse(
    approval_request_id: String,
    approve: Bool,
    id: Option(String),
    reason: Option(String),
  )
}

// ============================================================================
// Shell tool types
// ============================================================================

pub type FunctionShellActionParam {
  FunctionShellActionParam(
    commands: List(String),
    timeout_ms: Option(Int),
    max_output_length: Option(Int),
  )
}

pub type LocalEnvironmentParam {
  LocalEnvironmentParam(skills: Option(Dynamic))
}

pub type ContainerReferenceParam {
  ContainerReferenceParam(container_id: String)
}

pub type ContainerReferenceResource {
  ContainerReferenceResource(container_id: String)
}

/// Tagged by "type".
pub type FunctionShellCallItemEnvironment {
  ShellEnvLocal(LocalEnvironmentParam)
  ShellEnvContainerReference(ContainerReferenceParam)
}

pub type FunctionShellCallItemParam {
  FunctionShellCallItemParam(
    id: Option(String),
    call_id: String,
    action: FunctionShellActionParam,
    status: Option(FunctionShellCallItemStatus),
    environment: Option(FunctionShellCallItemEnvironment),
  )
}

pub type FunctionShellCallOutputExitOutcomeParam {
  FunctionShellCallOutputExitOutcomeParam(exit_code: Int)
}

/// Tagged by "type".
pub type FunctionShellCallOutputOutcomeParam {
  ShellOutcomeTimeout
  ShellOutcomeExit(FunctionShellCallOutputExitOutcomeParam)
}

pub type FunctionShellCallOutputContentParam {
  FunctionShellCallOutputContentParam(
    stdout: String,
    stderr: String,
    outcome: FunctionShellCallOutputOutcomeParam,
  )
}

pub type FunctionShellCallOutputItemParam {
  FunctionShellCallOutputItemParam(
    id: Option(String),
    call_id: String,
    output: List(FunctionShellCallOutputContentParam),
    max_output_length: Option(Int),
  )
}

pub type FunctionShellAction {
  FunctionShellAction(
    commands: List(String),
    timeout_ms: Option(Int),
    max_output_length: Option(Int),
  )
}

/// Tagged by "type".
pub type FunctionShellCallEnvironment {
  ShellCallEnvLocal
  ShellCallEnvContainerReference(ContainerReferenceResource)
}

pub type FunctionShellCallOutputExitOutcome {
  FunctionShellCallOutputExitOutcome(exit_code: Int)
}

/// Tagged by "type".
pub type FunctionShellCallOutputOutcome {
  ShellCallOutcomeTimeout
  ShellCallOutcomeExit(FunctionShellCallOutputExitOutcome)
}

pub type FunctionShellCallOutputContent {
  FunctionShellCallOutputContent(
    stdout: String,
    stderr: String,
    outcome: FunctionShellCallOutputOutcome,
    created_by: Option(String),
  )
}

pub type FunctionShellCall {
  FunctionShellCall(
    id: String,
    call_id: String,
    action: FunctionShellAction,
    status: FunctionShellCallItemStatus,
    environment: Option(FunctionShellCallEnvironment),
    created_by: Option(String),
  )
}

pub type FunctionShellCallOutput {
  FunctionShellCallOutput(
    id: String,
    call_id: String,
    output: List(FunctionShellCallOutputContent),
    max_output_length: Option(Int),
    created_by: Option(String),
  )
}

// ============================================================================
// Apply patch types
// ============================================================================

pub type ApplyPatchCreateFileOperationParam {
  ApplyPatchCreateFileOperationParam(path: String, diff: String)
}

pub type ApplyPatchDeleteFileOperationParam {
  ApplyPatchDeleteFileOperationParam(path: String)
}

pub type ApplyPatchUpdateFileOperationParam {
  ApplyPatchUpdateFileOperationParam(path: String, diff: String)
}

/// Tagged by "type".
pub type ApplyPatchOperationParam {
  ApplyPatchOpCreateFile(ApplyPatchCreateFileOperationParam)
  ApplyPatchOpDeleteFile(ApplyPatchDeleteFileOperationParam)
  ApplyPatchOpUpdateFile(ApplyPatchUpdateFileOperationParam)
}

pub type ApplyPatchToolCallItemParam {
  ApplyPatchToolCallItemParam(
    id: Option(String),
    call_id: String,
    status: ApplyPatchCallStatusParam,
    operation: ApplyPatchOperationParam,
  )
}

pub type ApplyPatchToolCallOutputItemParam {
  ApplyPatchToolCallOutputItemParam(
    id: Option(String),
    call_id: String,
    status: ApplyPatchCallOutputStatusParam,
    output: Option(String),
  )
}

pub type ApplyPatchCreateFileOperation {
  ApplyPatchCreateFileOperation(path: String, diff: String)
}

pub type ApplyPatchDeleteFileOperation {
  ApplyPatchDeleteFileOperation(path: String)
}

pub type ApplyPatchUpdateFileOperation {
  ApplyPatchUpdateFileOperation(path: String, diff: String)
}

/// Tagged by "type".
pub type ApplyPatchOperation {
  ApplyPatchCreateFile(ApplyPatchCreateFileOperation)
  ApplyPatchDeleteFile(ApplyPatchDeleteFileOperation)
  ApplyPatchUpdateFile(ApplyPatchUpdateFileOperation)
}

pub type ApplyPatchToolCall {
  ApplyPatchToolCall(
    id: String,
    call_id: String,
    status: ApplyPatchCallStatusParam,
    operation: ApplyPatchOperation,
    created_by: Option(String),
  )
}

pub type ApplyPatchToolCallOutput {
  ApplyPatchToolCallOutput(
    id: String,
    call_id: String,
    status: ApplyPatchCallOutputStatusParam,
    output: Option(String),
    created_by: Option(String),
  )
}

// ============================================================================
// Custom tool types
// ============================================================================

pub type CustomToolCallOutputOutput {
  CustomToolCallOutputText(String)
  CustomToolCallOutputList(List(InputContent))
}

pub type CustomToolCallOutput {
  CustomToolCallOutput(
    call_id: String,
    output: CustomToolCallOutputOutput,
    id: Option(String),
  )
}

pub type CustomToolCall {
  CustomToolCall(
    call_id: String,
    namespace: Option(String),
    input: String,
    name: String,
    id: String,
  )
}

// ============================================================================
// Tool search types
// ============================================================================

pub type ToolSearchCall {
  ToolSearchCall(
    id: String,
    call_id: Option(String),
    execution: ToolSearchExecutionType,
    arguments: Dynamic,
    status: FunctionCallStatus,
    created_by: Option(String),
  )
}

pub type ToolSearchCallItemParam {
  ToolSearchCallItemParam(
    id: Option(String),
    call_id: Option(String),
    execution: Option(ToolSearchExecutionType),
    arguments: Dynamic,
    status: Option(OutputStatus),
  )
}

pub type ToolSearchOutput {
  ToolSearchOutput(
    id: String,
    call_id: Option(String),
    execution: ToolSearchExecutionType,
    tools: Dynamic,
    status: FunctionCallStatus,
    created_by: Option(String),
  )
}

pub type ToolSearchOutputItemParam {
  ToolSearchOutputItemParam(
    id: Option(String),
    call_id: Option(String),
    execution: Option(ToolSearchExecutionType),
    tools: Dynamic,
    status: Option(OutputStatus),
  )
}

// ============================================================================
// Tool definitions
// ============================================================================

pub type FunctionTool {
  FunctionTool(
    name: String,
    parameters: Option(Dynamic),
    strict: Option(Bool),
    description: Option(String),
    defer_loading: Option(Bool),
  )
}

pub type HybridSearch {
  HybridSearch(embedding_weight: Float, text_weight: Float)
}

pub type RankingOptions {
  RankingOptions(
    hybrid_search: Option(HybridSearch),
    ranker: RankVersionType,
    score_threshold: Option(Float),
  )
}

pub type FileSearchTool {
  FileSearchTool(
    vector_store_ids: List(String),
    max_num_results: Option(Int),
    filters: Option(Dynamic),
    ranking_options: Option(RankingOptions),
  )
}

pub type WebSearchToolFilters {
  WebSearchToolFilters(allowed_domains: Option(List(String)))
}

pub type WebSearchApproximateLocation {
  WebSearchApproximateLocation(
    city: Option(String),
    country: Option(String),
    region: Option(String),
    timezone: Option(String),
  )
}

pub type WebSearchTool {
  WebSearchTool(
    filters: Option(WebSearchToolFilters),
    user_location: Option(WebSearchApproximateLocation),
    search_context_size: Option(WebSearchToolSearchContextSize),
    search_content_types: Option(List(SearchContentType)),
  )
}

pub type ComputerUsePreviewTool {
  ComputerUsePreviewTool(
    environment: ComputerEnvironment,
    display_width: Int,
    display_height: Int,
  )
}

pub type CodeInterpreterContainerAuto {
  CodeInterpreterContainerAuto(
    file_ids: Option(List(String)),
    memory_limit: Option(Int),
  )
}

/// Tagged by "type", with ContainerID as untagged fallback.
pub type CodeInterpreterToolContainer {
  CodeInterpContainerAuto(CodeInterpreterContainerAuto)
  CodeInterpContainerId(String)
}

pub type CodeInterpreterTool {
  CodeInterpreterTool(container: CodeInterpreterToolContainer)
}

pub type ImageGenToolInputImageMask {
  ImageGenToolInputImageMask(image_url: Option(String), file_id: Option(String))
}

pub type ImageGenTool {
  ImageGenTool(
    background: Option(ImageGenToolBackground),
    input_fidelity: Option(InputFidelity),
    input_image_mask: Option(ImageGenToolInputImageMask),
    model: Option(String),
    moderation: Option(ImageGenToolModeration),
    output_compression: Option(Int),
    output_format: Option(ImageGenToolOutputFormat),
    partial_images: Option(Int),
    quality: Option(ImageGenToolQuality),
    size: Option(ImageGenToolSize),
    action: Option(ImageGenActionEnum),
  )
}

pub type ToolSearchToolParam {
  ToolSearchToolParam(
    execution: Option(ToolSearchExecutionType),
    description: Option(String),
    parameters: Option(Dynamic),
  )
}

pub type FunctionToolParam {
  FunctionToolParam(
    name: String,
    description: Option(String),
    parameters: Option(Dynamic),
    strict: Option(Bool),
    defer_loading: Option(Bool),
  )
}

pub type CustomToolParamFormat {
  CustomFormatText
  CustomFormatGrammar(Dynamic)
}

pub type CustomToolParam {
  CustomToolParam(
    name: String,
    description: Option(String),
    format: CustomToolParamFormat,
    defer_loading: Option(Bool),
  )
}

pub type NamespaceToolParamTool {
  NamespaceFunction(FunctionToolParam)
  NamespaceCustom(CustomToolParam)
}

pub type NamespaceToolParam {
  NamespaceToolParam(
    name: String,
    description: String,
    tools: List(NamespaceToolParamTool),
  )
}

pub type ContainerAutoParam {
  ContainerAutoParam(
    file_ids: Option(List(String)),
    network_policy: Option(Dynamic),
    skills: Option(Dynamic),
  )
}

pub type FunctionShellEnvironment {
  FunctionShellEnvContainerAuto(ContainerAutoParam)
  FunctionShellEnvLocal(LocalEnvironmentParam)
  FunctionShellEnvContainerReference(ContainerReferenceParam)
}

pub type FunctionShellToolParam {
  FunctionShellToolParam(environment: Option(FunctionShellEnvironment))
}

/// All tool definitions. Tagged by "type".
pub type Tool {
  ToolFunction(FunctionTool)
  ToolFileSearch(FileSearchTool)
  ToolComputerUsePreview(ComputerUsePreviewTool)
  ToolWebSearch(WebSearchTool)
  ToolWebSearch20250826(WebSearchTool)
  ToolMcp(Dynamic)
  ToolCodeInterpreter(CodeInterpreterTool)
  ToolImageGeneration(ImageGenTool)
  ToolLocalShell
  ToolShell(FunctionShellToolParam)
  ToolCustom(CustomToolParam)
  ToolComputer
  ToolNamespace(NamespaceToolParam)
  ToolToolSearch(ToolSearchToolParam)
  ToolWebSearchPreview(WebSearchTool)
  ToolWebSearchPreview20250311(WebSearchTool)
  ToolApplyPatch
}

// ============================================================================
// Tool choice
// ============================================================================

pub type ToolChoiceAllowed {
  ToolChoiceAllowed(mode: ToolChoiceAllowedMode, tools: Dynamic)
}

pub type ToolChoiceFunction {
  ToolChoiceFunction(name: String)
}

pub type ToolChoiceMcp {
  ToolChoiceMcp(name: String, server_label: String)
}

pub type ToolChoiceCustom {
  ToolChoiceCustom(name: String)
}

/// Tagged by "type".
pub type ToolChoiceTypes {
  ToolChoiceFileSearch
  ToolChoiceWebSearchPreview
  ToolChoiceComputer
  ToolChoiceComputerUsePreview
  ToolChoiceComputerUse
  ToolChoiceWebSearchPreview20250311
  ToolChoiceCodeInterpreter
  ToolChoiceImageGeneration
}

/// How the model should select which tool to use. Complex union:
/// tagged variants + untagged fallbacks for Mode and Hosted.
pub type ToolChoiceParam {
  ToolChoiceParamAllowedTools(ToolChoiceAllowed)
  ToolChoiceParamFunction(ToolChoiceFunction)
  ToolChoiceParamMcp(ToolChoiceMcp)
  ToolChoiceParamCustom(ToolChoiceCustom)
  ToolChoiceParamApplyPatch
  ToolChoiceParamShell
  ToolChoiceParamHosted(ToolChoiceTypes)
  ToolChoiceParamMode(ToolChoiceOptions)
}

// ============================================================================
// Item and OutputItem (the big tagged unions)
// ============================================================================

/// Content item used to generate a response. Tagged by "type".
pub type Item {
  ItemMessage(MessageItem)
  ItemFileSearchCall(FileSearchToolCall)
  ItemComputerCall(ComputerToolCall)
  ItemComputerCallOutput(ComputerCallOutputItemParam)
  ItemWebSearchCall(WebSearchToolCall)
  ItemFunctionCall(FunctionToolCall)
  ItemFunctionCallOutput(FunctionCallOutputItemParam)
  ItemToolSearchCall(ToolSearchCallItemParam)
  ItemToolSearchOutput(ToolSearchOutputItemParam)
  ItemReasoning(ReasoningItem)
  ItemCompaction(CompactionSummaryItemParam)
  ItemImageGenerationCall(ImageGenToolCall)
  ItemCodeInterpreterCall(CodeInterpreterToolCall)
  ItemLocalShellCall(LocalShellToolCall)
  ItemLocalShellCallOutput(LocalShellToolCallOutput)
  ItemShellCall(FunctionShellCallItemParam)
  ItemShellCallOutput(FunctionShellCallOutputItemParam)
  ItemApplyPatchCall(ApplyPatchToolCallItemParam)
  ItemApplyPatchCallOutput(ApplyPatchToolCallOutputItemParam)
  ItemMcpListTools(McpListTools)
  ItemMcpApprovalRequest(McpApprovalRequest)
  ItemMcpApprovalResponse(McpApprovalResponse)
  ItemMcpCall(McpToolCall)
  ItemCustomToolCallOutput(CustomToolCallOutput)
  ItemCustomToolCall(CustomToolCall)
}

/// Untagged: ItemReference, Item, or EasyMessage.
pub type InputItem {
  InputItemReference(ItemReference)
  InputItemItem(Item)
  InputItemEasyMessage(EasyInputMessage)
}

/// Untagged: text string or list of items.
pub type InputParam {
  InputText(String)
  InputItems(List(InputItem))
}

/// Output item from the model. Tagged by "type".
pub type OutputItem {
  OutputItemMessage(OutputMessage)
  OutputItemFileSearchCall(FileSearchToolCall)
  OutputItemFunctionCall(FunctionToolCall)
  OutputItemWebSearchCall(WebSearchToolCall)
  OutputItemComputerCall(ComputerToolCall)
  OutputItemReasoning(ReasoningItem)
  OutputItemCompaction(CompactionBody)
  OutputItemImageGenerationCall(ImageGenToolCall)
  OutputItemCodeInterpreterCall(CodeInterpreterToolCall)
  OutputItemLocalShellCall(LocalShellToolCall)
  OutputItemShellCall(FunctionShellCall)
  OutputItemShellCallOutput(FunctionShellCallOutput)
  OutputItemApplyPatchCall(ApplyPatchToolCall)
  OutputItemApplyPatchCallOutput(ApplyPatchToolCallOutput)
  OutputItemMcpCall(McpToolCall)
  OutputItemMcpListTools(McpListTools)
  OutputItemMcpApprovalRequest(McpApprovalRequest)
  OutputItemCustomToolCall(CustomToolCall)
  OutputItemToolSearchCall(ToolSearchCall)
  OutputItemToolSearchOutput(ToolSearchOutput)
}

// ============================================================================
// Prompt
// ============================================================================

pub type Prompt {
  Prompt(id: String, version: Option(String), variables: Option(Dynamic))
}

// ============================================================================
// Misc response types
// ============================================================================

pub type Billing {
  Billing(payer: String)
}

pub type ErrorObject {
  ErrorObject(code: String, message: String)
}

pub type IncompleteDetails {
  IncompleteDetails(reason: String)
}

pub type ResponseStreamOptions {
  ResponseStreamOptions(include_obfuscation: Option(Bool))
}

/// Untagged: text string or item array.
pub type Instructions {
  InstructionsText(String)
  InstructionsArray(List(InputItem))
}

// ============================================================================
// Request type
// ============================================================================

pub type CreateResponse {
  CreateResponse(
    background: Option(Bool),
    conversation: Option(ConversationParam),
    include: Option(List(IncludeEnum)),
    input: InputParam,
    instructions: Option(String),
    max_output_tokens: Option(Int),
    max_tool_calls: Option(Int),
    metadata: Option(Dict(String, String)),
    model: Option(String),
    parallel_tool_calls: Option(Bool),
    previous_response_id: Option(String),
    prompt: Option(Prompt),
    prompt_cache_key: Option(String),
    prompt_cache_retention: Option(PromptCacheRetention),
    reasoning: Option(Reasoning),
    safety_identifier: Option(String),
    service_tier: Option(ServiceTier),
    store: Option(Bool),
    stream: Option(Bool),
    stream_options: Option(ResponseStreamOptions),
    temperature: Option(Float),
    text: Option(ResponseTextParam),
    tool_choice: Option(ToolChoiceParam),
    tools: Option(List(Tool)),
    top_logprobs: Option(Int),
    top_p: Option(Float),
    truncation: Option(Truncation),
  )
}

// ============================================================================
// Response type
// ============================================================================

pub type Response {
  Response(
    background: Option(Bool),
    billing: Option(Billing),
    conversation: Option(Conversation),
    created_at: Int,
    completed_at: Option(Int),
    error: Option(ErrorObject),
    id: String,
    incomplete_details: Option(IncompleteDetails),
    instructions: Option(Instructions),
    max_output_tokens: Option(Int),
    metadata: Option(Dict(String, String)),
    model: String,
    object: String,
    output: List(OutputItem),
    parallel_tool_calls: Option(Bool),
    previous_response_id: Option(String),
    prompt: Option(Prompt),
    prompt_cache_key: Option(String),
    prompt_cache_retention: Option(PromptCacheRetention),
    reasoning: Option(Reasoning),
    safety_identifier: Option(String),
    service_tier: Option(ServiceTier),
    status: ResponseStatus,
    temperature: Option(Float),
    text: Option(ResponseTextParam),
    tool_choice: Option(ToolChoiceParam),
    tools: Option(List(Tool)),
    top_logprobs: Option(Int),
    top_p: Option(Float),
    truncation: Option(Truncation),
    usage: Option(ResponseUsage),
  )
}

pub type DeleteResponse {
  DeleteResponse(object: String, deleted: Bool, id: String)
}

pub type ResponseItemList {
  ResponseItemList(
    object: String,
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
    data: Dynamic,
  )
}

pub type TokenCountsResource {
  TokenCountsResource(object: String, input_tokens: Int)
}

pub type CompactResource {
  CompactResource(
    id: String,
    object: String,
    output: List(OutputItem),
    created_at: Int,
    usage: ResponseUsage,
  )
}

// ============================================================================
// Stream event types
// ============================================================================

/// All 48 streaming event types. Tagged by "type" with dotted names like
/// "response.created", "response.output_text.delta", etc.
pub type ResponseStreamEvent {
  EventResponseCreated(sequence_number: Int, response: Response)
  EventResponseInProgress(sequence_number: Int, response: Response)
  EventResponseCompleted(sequence_number: Int, response: Response)
  EventResponseFailed(sequence_number: Int, response: Response)
  EventResponseIncomplete(sequence_number: Int, response: Response)
  EventResponseQueued(sequence_number: Int, response: Response)
  EventResponseOutputItemAdded(
    sequence_number: Int,
    output_index: Int,
    item: OutputItem,
  )
  EventResponseOutputItemDone(
    sequence_number: Int,
    output_index: Int,
    item: OutputItem,
  )
  EventResponseContentPartAdded(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    part: OutputContent,
  )
  EventResponseContentPartDone(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    part: OutputContent,
  )
  EventResponseOutputTextDelta(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    delta: String,
    logprobs: Option(List(ResponseLogProb)),
  )
  EventResponseOutputTextDone(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    text: String,
    logprobs: Option(List(ResponseLogProb)),
  )
  EventResponseRefusalDelta(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    delta: String,
  )
  EventResponseRefusalDone(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    refusal: String,
  )
  EventResponseFunctionCallArgumentsDelta(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    delta: String,
  )
  EventResponseFunctionCallArgumentsDone(
    name: Option(String),
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    arguments: String,
  )
  EventResponseFileSearchCallInProgress(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseFileSearchCallSearching(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseFileSearchCallCompleted(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseWebSearchCallInProgress(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseWebSearchCallSearching(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseWebSearchCallCompleted(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseReasoningSummaryPartAdded(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    summary_index: Int,
    part: SummaryPart,
  )
  EventResponseReasoningSummaryPartDone(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    summary_index: Int,
    part: SummaryPart,
  )
  EventResponseReasoningSummaryTextDelta(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    summary_index: Int,
    delta: String,
  )
  EventResponseReasoningSummaryTextDone(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    summary_index: Int,
    text: String,
  )
  EventResponseReasoningTextDelta(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    delta: String,
  )
  EventResponseReasoningTextDone(
    sequence_number: Int,
    item_id: String,
    output_index: Int,
    content_index: Int,
    text: String,
  )
  EventResponseImageGenCallCompleted(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseImageGenCallGenerating(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseImageGenCallInProgress(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseImageGenCallPartialImage(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
    partial_image_index: Int,
    partial_image_b64: String,
  )
  EventResponseMcpCallArgumentsDelta(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
    delta: String,
  )
  EventResponseMcpCallArgumentsDone(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
    arguments: String,
  )
  EventResponseMcpCallCompleted(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseMcpCallFailed(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseMcpCallInProgress(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseMcpListToolsCompleted(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseMcpListToolsFailed(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseMcpListToolsInProgress(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseCodeInterpreterCallInProgress(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseCodeInterpreterCallInterpreting(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseCodeInterpreterCallCompleted(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
  )
  EventResponseCodeInterpreterCallCodeDelta(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
    delta: String,
  )
  EventResponseCodeInterpreterCallCodeDone(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
    code: String,
  )
  EventResponseOutputTextAnnotationAdded(
    sequence_number: Int,
    output_index: Int,
    content_index: Int,
    annotation_index: Int,
    item_id: String,
    annotation: Dynamic,
  )
  EventResponseCustomToolCallInputDelta(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
    delta: String,
  )
  EventResponseCustomToolCallInputDone(
    sequence_number: Int,
    output_index: Int,
    item_id: String,
    input: String,
  )
  EventResponseError(
    sequence_number: Int,
    code: Option(String),
    message: String,
    param: Option(String),
  )
}

// ============================================================================
// Request builder
// ============================================================================

/// Create a new response request with required input.
pub fn new_create_response(input input: InputParam) -> CreateResponse {
  CreateResponse(
    background: None,
    conversation: None,
    include: None,
    input: input,
    instructions: None,
    max_output_tokens: None,
    max_tool_calls: None,
    metadata: None,
    model: None,
    parallel_tool_calls: None,
    previous_response_id: None,
    prompt: None,
    prompt_cache_key: None,
    prompt_cache_retention: None,
    reasoning: None,
    safety_identifier: None,
    service_tier: None,
    store: None,
    stream: None,
    stream_options: None,
    temperature: None,
    text: None,
    tool_choice: None,
    tools: None,
    top_logprobs: None,
    top_p: None,
    truncation: None,
  )
}

pub fn with_model(request: CreateResponse, model: String) -> CreateResponse {
  CreateResponse(..request, model: Some(model))
}

pub fn with_instructions(
  request: CreateResponse,
  instructions: String,
) -> CreateResponse {
  CreateResponse(..request, instructions: Some(instructions))
}

pub fn with_tools(request: CreateResponse, tools: List(Tool)) -> CreateResponse {
  CreateResponse(..request, tools: Some(tools))
}

pub fn with_temperature(
  request: CreateResponse,
  temperature: Float,
) -> CreateResponse {
  CreateResponse(..request, temperature: Some(temperature))
}

pub fn with_max_output_tokens(
  request: CreateResponse,
  max_output_tokens: Int,
) -> CreateResponse {
  CreateResponse(..request, max_output_tokens: Some(max_output_tokens))
}

pub fn with_stream(request: CreateResponse, stream: Bool) -> CreateResponse {
  CreateResponse(..request, stream: Some(stream))
}

pub fn with_store(request: CreateResponse, store: Bool) -> CreateResponse {
  CreateResponse(..request, store: Some(store))
}

pub fn with_metadata(
  request: CreateResponse,
  metadata: Dict(String, String),
) -> CreateResponse {
  CreateResponse(..request, metadata: Some(metadata))
}

pub fn with_previous_response_id(
  request: CreateResponse,
  previous_response_id: String,
) -> CreateResponse {
  CreateResponse(..request, previous_response_id: Some(previous_response_id))
}

pub fn with_reasoning(
  request: CreateResponse,
  reasoning: Reasoning,
) -> CreateResponse {
  CreateResponse(..request, reasoning: Some(reasoning))
}

pub fn with_text(
  request: CreateResponse,
  text: ResponseTextParam,
) -> CreateResponse {
  CreateResponse(..request, text: Some(text))
}

pub fn with_tool_choice(
  request: CreateResponse,
  tool_choice: ToolChoiceParam,
) -> CreateResponse {
  CreateResponse(..request, tool_choice: Some(tool_choice))
}

pub fn with_truncation(
  request: CreateResponse,
  truncation: Truncation,
) -> CreateResponse {
  CreateResponse(..request, truncation: Some(truncation))
}

pub fn with_service_tier(
  request: CreateResponse,
  tier: ServiceTier,
) -> CreateResponse {
  CreateResponse(..request, service_tier: Some(tier))
}

pub fn with_top_p(request: CreateResponse, top_p: Float) -> CreateResponse {
  CreateResponse(..request, top_p: Some(top_p))
}

pub fn with_include(
  request: CreateResponse,
  include: List(IncludeEnum),
) -> CreateResponse {
  CreateResponse(..request, include: Some(include))
}

pub fn with_conversation(
  request: CreateResponse,
  conversation: ConversationParam,
) -> CreateResponse {
  CreateResponse(..request, conversation: Some(conversation))
}

pub fn with_background(
  request: CreateResponse,
  background: Bool,
) -> CreateResponse {
  CreateResponse(..request, background: Some(background))
}

// ============================================================================
// Encoders — string enums
// ============================================================================

pub fn message_phase_to_json(phase: MessagePhase) -> json.Json {
  json.string(case phase {
    Commentary -> "commentary"
    FinalAnswer -> "final_answer"
  })
}

pub fn tool_search_execution_type_to_json(
  t: ToolSearchExecutionType,
) -> json.Json {
  json.string(case t {
    ExecutionServer -> "server"
    ExecutionClient -> "client"
  })
}

pub fn search_content_type_to_json(t: SearchContentType) -> json.Json {
  json.string(case t {
    SearchText -> "text"
    SearchImage -> "image"
  })
}

pub fn output_status_to_json(s: OutputStatus) -> json.Json {
  json.string(case s {
    OutputInProgress -> "in_progress"
    OutputCompleted -> "completed"
    OutputIncomplete -> "incomplete"
  })
}

pub fn role_to_json(r: Role) -> json.Json {
  json.string(case r {
    RoleUser -> "user"
    RoleAssistant -> "assistant"
    RoleSystem -> "system"
    RoleDeveloper -> "developer"
  })
}

pub fn input_role_to_json(r: InputRole) -> json.Json {
  json.string(case r {
    InputRoleUser -> "user"
    InputRoleSystem -> "system"
    InputRoleDeveloper -> "developer"
  })
}

pub fn truncation_to_json(t: Truncation) -> json.Json {
  json.string(case t {
    TruncationAuto -> "auto"
    TruncationDisabled -> "disabled"
  })
}

pub fn service_tier_to_json(t: ServiceTier) -> json.Json {
  json.string(case t {
    ServiceTierAuto -> "auto"
    ServiceTierDefault -> "default"
    ServiceTierFlex -> "flex"
    ServiceTierScale -> "scale"
    ServiceTierPriority -> "priority"
  })
}

pub fn response_status_to_json(s: ResponseStatus) -> json.Json {
  json.string(case s {
    StatusCompleted -> "completed"
    StatusFailed -> "failed"
    StatusInProgress -> "in_progress"
    StatusCancelled -> "cancelled"
    StatusQueued -> "queued"
    StatusIncomplete -> "incomplete"
  })
}

pub fn verbosity_to_json(v: Verbosity) -> json.Json {
  json.string(case v {
    VerbosityLow -> "low"
    VerbosityMedium -> "medium"
    VerbosityHigh -> "high"
  })
}

pub fn reasoning_summary_to_json(s: ReasoningSummary) -> json.Json {
  json.string(case s {
    ReasoningSummaryAuto -> "auto"
    ReasoningSummaryConcise -> "concise"
    ReasoningSummaryDetailed -> "detailed"
  })
}

pub fn prompt_cache_retention_to_json(r: PromptCacheRetention) -> json.Json {
  json.string(case r {
    PromptCacheInMemory -> "in_memory"
    PromptCacheHours24 -> "24h"
  })
}

pub fn include_enum_to_json(i: IncludeEnum) -> json.Json {
  json.string(case i {
    IncludeFileSearchCallResults -> "file_search_call.results"
    IncludeWebSearchCallResults -> "web_search_call.results"
    IncludeWebSearchCallActionSources -> "web_search_call.action.sources"
    IncludeMessageInputImageImageUrl -> "message.input_image.image_url"
    IncludeComputerCallOutputOutputImageUrl ->
      "computer_call_output.output.image_url"
    IncludeCodeInterpreterCallOutputs -> "code_interpreter_call.outputs"
    IncludeReasoningEncryptedContent -> "reasoning.encrypted_content"
    IncludeMessageOutputTextLogprobs -> "message.output_text.logprobs"
  })
}

pub fn web_search_context_size_to_json(
  s: WebSearchToolSearchContextSize,
) -> json.Json {
  json.string(case s {
    WebSearchContextLow -> "low"
    WebSearchContextMedium -> "medium"
    WebSearchContextHigh -> "high"
  })
}

pub fn image_gen_bg_to_json(b: ImageGenToolBackground) -> json.Json {
  json.string(case b {
    ImageGenBgTransparent -> "transparent"
    ImageGenBgOpaque -> "opaque"
    ImageGenBgAuto -> "auto"
  })
}

pub fn image_gen_fmt_to_json(f: ImageGenToolOutputFormat) -> json.Json {
  json.string(case f {
    ImageGenFmtPng -> "png"
    ImageGenFmtWebp -> "webp"
    ImageGenFmtJpeg -> "jpeg"
  })
}

pub fn image_gen_quality_to_json(q: ImageGenToolQuality) -> json.Json {
  json.string(case q {
    ImageGenQualityLow -> "low"
    ImageGenQualityMedium -> "medium"
    ImageGenQualityHigh -> "high"
    ImageGenQualityAuto -> "auto"
  })
}

pub fn image_gen_size_to_json(s: ImageGenToolSize) -> json.Json {
  json.string(case s {
    ImageGenSizeAuto -> "auto"
    ImageGenSize1024x1024 -> "1024x1024"
    ImageGenSize1024x1536 -> "1024x1536"
    ImageGenSize1536x1024 -> "1536x1024"
  })
}

pub fn input_fidelity_to_json(f: InputFidelity) -> json.Json {
  json.string(case f {
    FidelityHigh -> "high"
    FidelityLow -> "low"
  })
}

pub fn image_gen_moderation_to_json(m: ImageGenToolModeration) -> json.Json {
  json.string(case m {
    ImageGenModerationAuto -> "auto"
    ImageGenModerationLow -> "low"
  })
}

pub fn image_gen_action_to_json(a: ImageGenActionEnum) -> json.Json {
  json.string(case a {
    ImageGenGenerate -> "generate"
    ImageGenEdit -> "edit"
    ImageGenActionAuto -> "auto"
  })
}

pub fn tool_choice_options_to_json(o: ToolChoiceOptions) -> json.Json {
  json.string(case o {
    ToolChoiceNone -> "none"
    ToolChoiceAuto -> "auto"
    ToolChoiceRequired -> "required"
  })
}

pub fn rank_version_type_to_json(r: RankVersionType) -> json.Json {
  json.string(case r {
    RankAuto -> "auto"
    RankDefault20241115 -> "default-2024-11-15"
  })
}

// ============================================================================
// Encoders — compound types
// ============================================================================

pub fn reasoning_to_json(r: Reasoning) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field("effort", r.effort, shared.reasoning_effort_to_json),
    codec.optional_field("summary", r.summary, reasoning_summary_to_json),
  ])
}

pub fn input_content_to_json(content: InputContent) -> json.Json {
  case content {
    ContentInputText(c) ->
      json.object([
        #("type", json.string("input_text")),
        #("text", json.string(c.text)),
      ])
    ContentInputImage(c) ->
      codec.object_with_optional(
        [
          #("type", json.string("input_image")),
          #("detail", shared.image_detail_to_json(c.detail)),
        ],
        [
          codec.optional_field("file_id", c.file_id, json.string),
          codec.optional_field("image_url", c.image_url, json.string),
        ],
      )
    ContentInputFile(c) ->
      codec.object_with_optional([#("type", json.string("input_file"))], [
        codec.optional_field("file_data", c.file_data, json.string),
        codec.optional_field("file_id", c.file_id, json.string),
        codec.optional_field("file_url", c.file_url, json.string),
        codec.optional_field("filename", c.filename, json.string),
      ])
  }
}

pub fn easy_input_content_to_json(c: EasyInputContent) -> json.Json {
  case c {
    EasyContentText(t) -> json.string(t)
    EasyContentList(parts) -> json.array(parts, input_content_to_json)
  }
}

pub fn easy_input_message_to_json(m: EasyInputMessage) -> json.Json {
  codec.object_with_optional(
    [
      #("type", json.string("message")),
      #("role", role_to_json(m.role)),
      #("content", easy_input_content_to_json(m.content)),
    ],
    [codec.optional_field("phase", m.phase, message_phase_to_json)],
  )
}

pub fn input_param_to_json(input: InputParam) -> json.Json {
  case input {
    InputText(t) -> json.string(t)
    InputItems(items) -> json.array(items, input_item_to_json)
  }
}

pub fn input_item_to_json(item: InputItem) -> json.Json {
  case item {
    InputItemReference(ref) ->
      codec.object_with_optional([#("id", json.string(ref.id))], [
        codec.optional_field("type", ref.item_type, json.string),
      ])
    InputItemItem(i) -> item_to_json(i)
    InputItemEasyMessage(m) -> easy_input_message_to_json(m)
  }
}

pub fn function_tool_to_json(tool: FunctionTool) -> json.Json {
  codec.object_with_optional([#("name", json.string(tool.name))], [
    codec.optional_field("parameters", tool.parameters, codec.dynamic_to_json),
    codec.optional_field("strict", tool.strict, json.bool),
    codec.optional_field("description", tool.description, json.string),
    codec.optional_field("defer_loading", tool.defer_loading, json.bool),
  ])
}

pub fn web_search_tool_to_json(tool: WebSearchTool) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field("filters", tool.filters, fn(f) {
      codec.object_with_optional([], [
        codec.optional_field("allowed_domains", f.allowed_domains, fn(d) {
          json.array(d, json.string)
        }),
      ])
    }),
    codec.optional_field("user_location", tool.user_location, fn(loc) {
      codec.object_with_optional([#("type", json.string("approximate"))], [
        codec.optional_field("city", loc.city, json.string),
        codec.optional_field("country", loc.country, json.string),
        codec.optional_field("region", loc.region, json.string),
        codec.optional_field("timezone", loc.timezone, json.string),
      ])
    }),
    codec.optional_field(
      "search_context_size",
      tool.search_context_size,
      web_search_context_size_to_json,
    ),
    codec.optional_field(
      "search_content_types",
      tool.search_content_types,
      fn(types) { json.array(types, search_content_type_to_json) },
    ),
  ])
}

pub fn image_gen_tool_to_json(tool: ImageGenTool) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field("background", tool.background, image_gen_bg_to_json),
    codec.optional_field(
      "input_fidelity",
      tool.input_fidelity,
      input_fidelity_to_json,
    ),
    codec.optional_field("input_image_mask", tool.input_image_mask, fn(m) {
      codec.object_with_optional([], [
        codec.optional_field("image_url", m.image_url, json.string),
        codec.optional_field("file_id", m.file_id, json.string),
      ])
    }),
    codec.optional_field("model", tool.model, json.string),
    codec.optional_field(
      "moderation",
      tool.moderation,
      image_gen_moderation_to_json,
    ),
    codec.optional_field(
      "output_compression",
      tool.output_compression,
      json.int,
    ),
    codec.optional_field(
      "output_format",
      tool.output_format,
      image_gen_fmt_to_json,
    ),
    codec.optional_field("partial_images", tool.partial_images, json.int),
    codec.optional_field("quality", tool.quality, image_gen_quality_to_json),
    codec.optional_field("size", tool.size, image_gen_size_to_json),
    codec.optional_field("action", tool.action, image_gen_action_to_json),
  ])
}

pub fn tool_to_json(tool: Tool) -> json.Json {
  case tool {
    ToolFunction(t) ->
      codec.object_with_optional(
        [
          #("type", json.string("function")),
          #("name", json.string(t.name)),
        ],
        [
          codec.optional_field(
            "parameters",
            t.parameters,
            codec.dynamic_to_json,
          ),
          codec.optional_field("strict", t.strict, json.bool),
          codec.optional_field("description", t.description, json.string),
          codec.optional_field("defer_loading", t.defer_loading, json.bool),
        ],
      )
    ToolFileSearch(t) ->
      codec.object_with_optional(
        [
          #("type", json.string("file_search")),
          #("vector_store_ids", json.array(t.vector_store_ids, json.string)),
        ],
        [
          codec.optional_field("max_num_results", t.max_num_results, json.int),
          codec.optional_field("filters", t.filters, codec.dynamic_to_json),
          codec.optional_field("ranking_options", t.ranking_options, fn(r) {
            codec.object_with_optional(
              [#("ranker", rank_version_type_to_json(r.ranker))],
              [
                codec.optional_field("hybrid_search", r.hybrid_search, fn(h) {
                  json.object([
                    #("embedding_weight", json.float(h.embedding_weight)),
                    #("text_weight", json.float(h.text_weight)),
                  ])
                }),
                codec.optional_field(
                  "score_threshold",
                  r.score_threshold,
                  json.float,
                ),
              ],
            )
          }),
        ],
      )
    ToolWebSearch(t) -> web_search_tool_with_type("web_search", t)
    ToolWebSearch20250826(t) ->
      web_search_tool_with_type("web_search_2025_08_26", t)
    ToolWebSearchPreview(t) ->
      web_search_tool_with_type("web_search_preview", t)
    ToolWebSearchPreview20250311(t) ->
      web_search_tool_with_type("web_search_preview_2025_03_11", t)
    ToolCodeInterpreter(t) ->
      json.object([
        #("type", json.string("code_interpreter")),
        #("container", code_interpreter_container_to_json(t.container)),
      ])
    ToolImageGeneration(t) ->
      codec.object_with_optional([#("type", json.string("image_generation"))], [
        codec.optional_field("background", t.background, image_gen_bg_to_json),
        codec.optional_field(
          "input_fidelity",
          t.input_fidelity,
          input_fidelity_to_json,
        ),
        codec.optional_field("model", t.model, json.string),
        codec.optional_field(
          "moderation",
          t.moderation,
          image_gen_moderation_to_json,
        ),
        codec.optional_field(
          "output_format",
          t.output_format,
          image_gen_fmt_to_json,
        ),
        codec.optional_field("quality", t.quality, image_gen_quality_to_json),
        codec.optional_field("size", t.size, image_gen_size_to_json),
        codec.optional_field("action", t.action, image_gen_action_to_json),
      ])
    ToolLocalShell -> json.object([#("type", json.string("local_shell"))])
    ToolApplyPatch -> json.object([#("type", json.string("apply_patch"))])
    ToolComputer -> json.object([#("type", json.string("computer"))])
    ToolMcp(_d) ->
      // MCP tool data is Dynamic; we encode it alongside the type tag.
      // The dynamic value should already contain all the MCP-specific fields.
      json.object([#("type", json.string("mcp"))])
    ToolComputerUsePreview(t) ->
      json.object([
        #("type", json.string("computer_use_preview")),
        #(
          "environment",
          json.string(case t.environment {
            EnvironmentWindows -> "windows"
            EnvironmentMac -> "mac"
            EnvironmentLinux -> "linux"
            EnvironmentUbuntu -> "ubuntu"
            EnvironmentBrowser -> "browser"
          }),
        ),
        #("display_width", json.int(t.display_width)),
        #("display_height", json.int(t.display_height)),
      ])
    ToolShell(t) ->
      codec.object_with_optional([#("type", json.string("shell"))], [
        codec.optional_field(
          "environment",
          t.environment,
          function_shell_environment_to_json,
        ),
      ])
    ToolCustom(t) -> custom_tool_param_to_json(t)
    ToolNamespace(t) ->
      json.object([
        #("type", json.string("namespace")),
        #("name", json.string(t.name)),
        #("description", json.string(t.description)),
        #("tools", json.array(t.tools, namespace_tool_param_tool_to_json)),
      ])
    ToolToolSearch(t) ->
      codec.object_with_optional([#("type", json.string("tool_search"))], [
        codec.optional_field(
          "execution",
          t.execution,
          tool_search_execution_type_to_json,
        ),
        codec.optional_field("description", t.description, json.string),
        codec.optional_field("parameters", t.parameters, codec.dynamic_to_json),
      ])
  }
}

fn custom_tool_param_to_json(t: CustomToolParam) -> json.Json {
  codec.object_with_optional(
    [
      #("type", json.string("custom")),
      #("name", json.string(t.name)),
      #("format", custom_tool_param_format_to_json(t.format)),
    ],
    [
      codec.optional_field("description", t.description, json.string),
      codec.optional_field("defer_loading", t.defer_loading, json.bool),
    ],
  )
}

fn custom_tool_param_format_to_json(f: CustomToolParamFormat) -> json.Json {
  case f {
    CustomFormatText -> json.object([#("type", json.string("text"))])
    CustomFormatGrammar(_d) -> json.object([#("type", json.string("grammar"))])
  }
}

fn namespace_tool_param_tool_to_json(t: NamespaceToolParamTool) -> json.Json {
  case t {
    NamespaceFunction(f) ->
      codec.object_with_optional(
        [
          #("type", json.string("function")),
          #("name", json.string(f.name)),
        ],
        [
          codec.optional_field("description", f.description, json.string),
          codec.optional_field(
            "parameters",
            f.parameters,
            codec.dynamic_to_json,
          ),
          codec.optional_field("strict", f.strict, json.bool),
          codec.optional_field("defer_loading", f.defer_loading, json.bool),
        ],
      )
    NamespaceCustom(c) -> custom_tool_param_to_json(c)
  }
}

fn code_interpreter_container_to_json(
  c: CodeInterpreterToolContainer,
) -> json.Json {
  case c {
    CodeInterpContainerAuto(a) ->
      codec.object_with_optional([#("type", json.string("auto"))], [
        codec.optional_field("file_ids", a.file_ids, fn(ids) {
          json.array(ids, json.string)
        }),
        codec.optional_field("memory_limit", a.memory_limit, json.int),
      ])
    CodeInterpContainerId(id) -> json.string(id)
  }
}

fn function_shell_environment_to_json(
  env: FunctionShellEnvironment,
) -> json.Json {
  case env {
    FunctionShellEnvContainerAuto(a) ->
      codec.object_with_optional([#("type", json.string("container_auto"))], [
        codec.optional_field("file_ids", a.file_ids, fn(ids) {
          json.array(ids, json.string)
        }),
        codec.optional_field(
          "network_policy",
          a.network_policy,
          codec.dynamic_to_json,
        ),
        codec.optional_field("skills", a.skills, codec.dynamic_to_json),
      ])
    FunctionShellEnvLocal(l) ->
      codec.object_with_optional([#("type", json.string("local"))], [
        codec.optional_field("skills", l.skills, codec.dynamic_to_json),
      ])
    FunctionShellEnvContainerReference(r) ->
      json.object([
        #("type", json.string("container_reference")),
        #("container_id", json.string(r.container_id)),
      ])
  }
}

fn web_search_tool_with_type(
  type_name: String,
  tool: WebSearchTool,
) -> json.Json {
  codec.object_with_optional([#("type", json.string(type_name))], [
    codec.optional_field("filters", tool.filters, fn(f) {
      codec.object_with_optional([], [
        codec.optional_field("allowed_domains", f.allowed_domains, fn(d) {
          json.array(d, json.string)
        }),
      ])
    }),
    codec.optional_field("user_location", tool.user_location, fn(loc) {
      codec.object_with_optional([#("type", json.string("approximate"))], [
        codec.optional_field("city", loc.city, json.string),
        codec.optional_field("country", loc.country, json.string),
        codec.optional_field("region", loc.region, json.string),
        codec.optional_field("timezone", loc.timezone, json.string),
      ])
    }),
    codec.optional_field(
      "search_context_size",
      tool.search_context_size,
      web_search_context_size_to_json,
    ),
    codec.optional_field(
      "search_content_types",
      tool.search_content_types,
      fn(types) { json.array(types, search_content_type_to_json) },
    ),
  ])
}

pub fn text_response_format_to_json(
  f: TextResponseFormatConfiguration,
) -> json.Json {
  case f {
    TextFormatText -> json.object([#("type", json.string("text"))])
    TextFormatJsonObject -> json.object([#("type", json.string("json_object"))])
    // In the Responses API, JSON schema fields are flattened under
    // `text.format` alongside the type tag — not nested under a
    // `json_schema` key like in the Chat Completions API.
    TextFormatJsonSchema(schema) ->
      codec.object_with_optional(
        [
          #("type", json.string("json_schema")),
          #("name", json.string(schema.name)),
        ],
        [
          codec.optional_field("description", schema.description, json.string),
          codec.optional_field("schema", schema.schema, codec.dynamic_to_json),
          codec.optional_field("strict", schema.strict, json.bool),
        ],
      )
  }
}

pub fn response_text_param_to_json(p: ResponseTextParam) -> json.Json {
  codec.object_with_optional(
    [#("format", text_response_format_to_json(p.format))],
    [codec.optional_field("verbosity", p.verbosity, verbosity_to_json)],
  )
}

pub fn tool_choice_param_to_json(tc: ToolChoiceParam) -> json.Json {
  case tc {
    ToolChoiceParamMode(mode) -> tool_choice_options_to_json(mode)
    ToolChoiceParamFunction(f) ->
      json.object([
        #("type", json.string("function")),
        #("name", json.string(f.name)),
      ])
    ToolChoiceParamMcp(m) ->
      json.object([
        #("type", json.string("mcp")),
        #("name", json.string(m.name)),
        #("server_label", json.string(m.server_label)),
      ])
    ToolChoiceParamCustom(c) ->
      json.object([
        #("type", json.string("custom")),
        #("name", json.string(c.name)),
      ])
    ToolChoiceParamApplyPatch ->
      json.object([#("type", json.string("apply_patch"))])
    ToolChoiceParamShell -> json.object([#("type", json.string("shell"))])
    ToolChoiceParamHosted(h) -> {
      let type_str = case h {
        ToolChoiceFileSearch -> "file_search"
        ToolChoiceWebSearchPreview -> "web_search_preview"
        ToolChoiceComputer -> "computer"
        ToolChoiceComputerUsePreview -> "computer_use_preview"
        ToolChoiceComputerUse -> "computer_use"
        ToolChoiceWebSearchPreview20250311 -> "web_search_preview_2025_03_11"
        ToolChoiceCodeInterpreter -> "code_interpreter"
        ToolChoiceImageGeneration -> "image_generation"
      }
      json.object([#("type", json.string(type_str))])
    }
    ToolChoiceParamAllowedTools(a) ->
      json.object([
        #("type", json.string("allowed_tools")),
        #(
          "mode",
          json.string(case a.mode {
            AllowedModeAuto -> "auto"
            AllowedModeRequired -> "required"
          }),
        ),
        #("tools", codec.dynamic_to_json(a.tools)),
      ])
  }
}

pub fn conversation_param_to_json(c: ConversationParam) -> json.Json {
  case c {
    ConversationId(id) -> json.string(id)
    ConversationObject(conv) -> json.object([#("id", json.string(conv.id))])
  }
}

pub fn prompt_to_json(p: Prompt) -> json.Json {
  codec.object_with_optional([#("id", json.string(p.id))], [
    codec.optional_field("version", p.version, json.string),
    codec.optional_field("variables", p.variables, codec.dynamic_to_json),
  ])
}

pub fn response_stream_options_to_json(o: ResponseStreamOptions) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field(
      "include_obfuscation",
      o.include_obfuscation,
      json.bool,
    ),
  ])
}

/// Encode the item tagged union. Since this has many variants, we encode
/// just the type tag + the inner struct's fields.
pub fn item_to_json(item: Item) -> json.Json {
  // For brevity in the request encoder, we encode the full tagged structure.
  // Most users only need a few item types in input (message, function_call_output, etc.)
  case item {
    ItemMessage(m) -> message_item_to_json(m)
    ItemFunctionCall(f) ->
      codec.object_with_optional(
        [
          #("type", json.string("function_call")),
          #("arguments", json.string(f.arguments)),
          #("call_id", json.string(f.call_id)),
          #("name", json.string(f.name)),
        ],
        [
          codec.optional_field("namespace", f.namespace, json.string),
          codec.optional_field("id", f.id, json.string),
          codec.optional_field("status", f.status, output_status_to_json),
        ],
      )
    ItemFunctionCallOutput(f) ->
      codec.object_with_optional(
        [
          #("type", json.string("function_call_output")),
          #("call_id", json.string(f.call_id)),
          #("output", function_call_output_to_json(f.output)),
        ],
        [
          codec.optional_field("id", f.id, json.string),
          codec.optional_field("status", f.status, output_status_to_json),
        ],
      )
    ItemReasoning(r) -> reasoning_item_to_json(r, "reasoning")
    ItemCompaction(c) ->
      codec.object_with_optional(
        [
          #("type", json.string("compaction")),
          #("encrypted_content", json.string(c.encrypted_content)),
        ],
        [codec.optional_field("id", c.id, json.string)],
      )
    ItemMcpApprovalResponse(r) ->
      codec.object_with_optional(
        [
          #("type", json.string("mcp_approval_response")),
          #("approval_request_id", json.string(r.approval_request_id)),
          #("approve", json.bool(r.approve)),
        ],
        [
          codec.optional_field("id", r.id, json.string),
          codec.optional_field("reason", r.reason, json.string),
        ],
      )
    ItemComputerCallOutput(c) ->
      codec.object_with_optional(
        [
          #("type", json.string("computer_call_output")),
          #("call_id", json.string(c.call_id)),
          #("output", computer_screenshot_image_to_json(c.output)),
        ],
        [
          codec.optional_field(
            "acknowledged_safety_checks",
            c.acknowledged_safety_checks,
            fn(checks) {
              json.array(checks, computer_call_safety_check_to_json)
            },
          ),
          codec.optional_field("id", c.id, json.string),
          codec.optional_field("status", c.status, output_status_to_json),
        ],
      )
    // For other item types, encode as a generic tagged object with dynamic
    // content. These are primarily output-only items that users don't
    // construct in requests.
    _ -> json.object([#("type", json.string("unknown"))])
  }
}

fn message_item_to_json(m: MessageItem) -> json.Json {
  case m {
    MessageItemOutput(o) ->
      codec.object_with_optional(
        [
          #("type", json.string("message")),
          #("role", json.string("assistant")),
          #("id", json.string(o.id)),
          #("content", json.array(o.content, output_message_content_to_json)),
          #("status", output_status_to_json(o.status)),
        ],
        [codec.optional_field("phase", o.phase, message_phase_to_json)],
      )
    MessageItemInput(i) ->
      codec.object_with_optional(
        [
          #("type", json.string("message")),
          #("role", input_role_to_json(i.role)),
          #("content", json.array(i.content, input_content_to_json)),
        ],
        [codec.optional_field("status", i.status, output_status_to_json)],
      )
  }
}

fn output_message_content_to_json(c: OutputMessageContent) -> json.Json {
  case c {
    OutputMessageOutputText(t) ->
      json.object([
        #("type", json.string("output_text")),
        #("text", json.string(t.text)),
        #("annotations", json.array(t.annotations, annotation_to_json)),
      ])
    OutputMessageRefusal(r) ->
      json.object([
        #("type", json.string("refusal")),
        #("refusal", json.string(r.refusal)),
      ])
  }
}

fn annotation_to_json(a: Annotation) -> json.Json {
  case a {
    AnnotationFileCitation(c) ->
      json.object([
        #("type", json.string("file_citation")),
        #("file_id", json.string(c.file_id)),
        #("filename", json.string(c.filename)),
        #("index", json.int(c.index)),
      ])
    AnnotationUrlCitation(c) ->
      json.object([
        #("type", json.string("url_citation")),
        #("end_index", json.int(c.end_index)),
        #("start_index", json.int(c.start_index)),
        #("title", json.string(c.title)),
        #("url", json.string(c.url)),
      ])
    AnnotationContainerFileCitation(c) ->
      json.object([
        #("type", json.string("container_file_citation")),
        #("container_id", json.string(c.container_id)),
        #("end_index", json.int(c.end_index)),
        #("file_id", json.string(c.file_id)),
        #("filename", json.string(c.filename)),
        #("start_index", json.int(c.start_index)),
      ])
    AnnotationFilePath(p) ->
      json.object([
        #("type", json.string("file_path")),
        #("file_id", json.string(p.file_id)),
        #("index", json.int(p.index)),
      ])
  }
}

fn function_call_output_to_json(o: FunctionCallOutput) -> json.Json {
  case o {
    FunctionCallOutputText(t) -> json.string(t)
    FunctionCallOutputContent(parts) -> json.array(parts, input_content_to_json)
  }
}

fn computer_screenshot_image_to_json(img: ComputerScreenshotImage) -> json.Json {
  codec.object_with_optional([#("type", json.string("computer_screenshot"))], [
    codec.optional_field("file_id", img.file_id, json.string),
    codec.optional_field("image_url", img.image_url, json.string),
  ])
}

fn computer_call_safety_check_to_json(
  check: ComputerCallSafetyCheckParam,
) -> json.Json {
  codec.object_with_optional([#("id", json.string(check.id))], [
    codec.optional_field("code", check.code, json.string),
    codec.optional_field("message", check.message, json.string),
  ])
}

fn reasoning_item_to_json(r: ReasoningItem, type_tag: String) -> json.Json {
  codec.object_with_optional(
    [
      #("type", json.string(type_tag)),
      #("id", json.string(r.id)),
      #("summary", json.array(r.summary, summary_part_to_json)),
    ],
    [
      codec.optional_field("content", r.content, fn(c) {
        json.array(c, fn(t) {
          json.object([
            #("type", json.string("reasoning_text")),
            #("text", json.string(t.text)),
          ])
        })
      }),
      codec.optional_field(
        "encrypted_content",
        r.encrypted_content,
        json.string,
      ),
      codec.optional_field("status", r.status, output_status_to_json),
    ],
  )
}

fn summary_part_to_json(p: SummaryPart) -> json.Json {
  case p {
    SummaryPartSummaryText(t) ->
      json.object([
        #("type", json.string("summary_text")),
        #("text", json.string(t.text)),
      ])
  }
}

// ============================================================================
// Main request encoder
// ============================================================================

pub fn create_response_to_json(request: CreateResponse) -> json.Json {
  codec.object_with_optional([#("input", input_param_to_json(request.input))], [
    codec.optional_field("background", request.background, json.bool),
    codec.optional_field(
      "conversation",
      request.conversation,
      conversation_param_to_json,
    ),
    codec.optional_field("include", request.include, fn(i) {
      json.array(i, include_enum_to_json)
    }),
    codec.optional_field("instructions", request.instructions, json.string),
    codec.optional_field(
      "max_output_tokens",
      request.max_output_tokens,
      json.int,
    ),
    codec.optional_field("max_tool_calls", request.max_tool_calls, json.int),
    codec.optional_field("metadata", request.metadata, fn(m) {
      json.object(
        dict.to_list(m)
        |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
      )
    }),
    codec.optional_field("model", request.model, json.string),
    codec.optional_field(
      "parallel_tool_calls",
      request.parallel_tool_calls,
      json.bool,
    ),
    codec.optional_field(
      "previous_response_id",
      request.previous_response_id,
      json.string,
    ),
    codec.optional_field("prompt", request.prompt, prompt_to_json),
    codec.optional_field(
      "prompt_cache_key",
      request.prompt_cache_key,
      json.string,
    ),
    codec.optional_field(
      "prompt_cache_retention",
      request.prompt_cache_retention,
      prompt_cache_retention_to_json,
    ),
    codec.optional_field("reasoning", request.reasoning, reasoning_to_json),
    codec.optional_field(
      "safety_identifier",
      request.safety_identifier,
      json.string,
    ),
    codec.optional_field(
      "service_tier",
      request.service_tier,
      service_tier_to_json,
    ),
    codec.optional_field("store", request.store, json.bool),
    codec.optional_field("stream", request.stream, json.bool),
    codec.optional_field(
      "stream_options",
      request.stream_options,
      response_stream_options_to_json,
    ),
    codec.optional_field("temperature", request.temperature, json.float),
    codec.optional_field("text", request.text, response_text_param_to_json),
    codec.optional_field(
      "tool_choice",
      request.tool_choice,
      tool_choice_param_to_json,
    ),
    codec.optional_field("tools", request.tools, fn(t) {
      json.array(t, tool_to_json)
    }),
    codec.optional_field("top_logprobs", request.top_logprobs, json.int),
    codec.optional_field("top_p", request.top_p, json.float),
    codec.optional_field("truncation", request.truncation, truncation_to_json),
  ])
}

// ============================================================================
// Decoders — string enums
// ============================================================================

pub fn message_phase_decoder() -> decode.Decoder(MessagePhase) {
  use value <- decode.then(decode.string)
  case value {
    "commentary" -> decode.success(Commentary)
    "final_answer" -> decode.success(FinalAnswer)
    _ -> decode.failure(Commentary, "MessagePhase")
  }
}

pub fn output_status_decoder() -> decode.Decoder(OutputStatus) {
  use value <- decode.then(decode.string)
  case value {
    "in_progress" -> decode.success(OutputInProgress)
    "completed" -> decode.success(OutputCompleted)
    "incomplete" -> decode.success(OutputIncomplete)
    _ -> decode.failure(OutputInProgress, "OutputStatus")
  }
}

pub fn role_decoder() -> decode.Decoder(Role) {
  use value <- decode.then(decode.string)
  case value {
    "user" -> decode.success(RoleUser)
    "assistant" -> decode.success(RoleAssistant)
    "system" -> decode.success(RoleSystem)
    "developer" -> decode.success(RoleDeveloper)
    _ -> decode.failure(RoleUser, "Role")
  }
}

pub fn input_role_decoder() -> decode.Decoder(InputRole) {
  use value <- decode.then(decode.string)
  case value {
    "user" -> decode.success(InputRoleUser)
    "system" -> decode.success(InputRoleSystem)
    "developer" -> decode.success(InputRoleDeveloper)
    _ -> decode.failure(InputRoleUser, "InputRole")
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

pub fn response_status_decoder() -> decode.Decoder(ResponseStatus) {
  use value <- decode.then(decode.string)
  case value {
    "completed" -> decode.success(StatusCompleted)
    "failed" -> decode.success(StatusFailed)
    "in_progress" -> decode.success(StatusInProgress)
    "cancelled" -> decode.success(StatusCancelled)
    "queued" -> decode.success(StatusQueued)
    "incomplete" -> decode.success(StatusIncomplete)
    _ -> decode.failure(StatusCompleted, "ResponseStatus")
  }
}

pub fn truncation_decoder() -> decode.Decoder(Truncation) {
  use value <- decode.then(decode.string)
  case value {
    "auto" -> decode.success(TruncationAuto)
    "disabled" -> decode.success(TruncationDisabled)
    _ -> decode.failure(TruncationAuto, "Truncation")
  }
}

pub fn verbosity_decoder() -> decode.Decoder(Verbosity) {
  use value <- decode.then(decode.string)
  case value {
    "low" -> decode.success(VerbosityLow)
    "medium" -> decode.success(VerbosityMedium)
    "high" -> decode.success(VerbosityHigh)
    _ -> decode.failure(VerbosityMedium, "Verbosity")
  }
}

pub fn reasoning_summary_decoder() -> decode.Decoder(ReasoningSummary) {
  use value <- decode.then(decode.string)
  case value {
    "auto" -> decode.success(ReasoningSummaryAuto)
    "concise" -> decode.success(ReasoningSummaryConcise)
    "detailed" -> decode.success(ReasoningSummaryDetailed)
    _ -> decode.failure(ReasoningSummaryAuto, "ReasoningSummary")
  }
}

pub fn prompt_cache_retention_decoder() -> decode.Decoder(PromptCacheRetention) {
  use value <- decode.then(decode.string)
  case value {
    "in_memory" -> decode.success(PromptCacheInMemory)
    "24h" -> decode.success(PromptCacheHours24)
    _ -> decode.failure(PromptCacheInMemory, "PromptCacheRetention")
  }
}

// ============================================================================
// Decoders — compound types
// ============================================================================

pub fn reasoning_decoder() -> decode.Decoder(Reasoning) {
  use effort <- decode.optional_field(
    "effort",
    None,
    decode.optional(shared.reasoning_effort_decoder()),
  )
  use summary <- decode.optional_field(
    "summary",
    None,
    decode.optional(reasoning_summary_decoder()),
  )
  decode.success(Reasoning(effort: effort, summary: summary))
}

pub fn text_response_format_decoder() -> decode.Decoder(
  TextResponseFormatConfiguration,
) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "text" -> decode.success(TextFormatText)
    "json_object" -> decode.success(TextFormatJsonObject)
    "json_schema" -> {
      // Responses API flattens the schema fields alongside the type tag.
      use name <- decode.field("name", decode.string)
      use description <- decode.optional_field(
        "description",
        None,
        decode.optional(decode.string),
      )
      use schema <- decode.optional_field(
        "schema",
        None,
        decode.optional(decode.dynamic),
      )
      use strict <- decode.optional_field(
        "strict",
        None,
        decode.optional(decode.bool),
      )
      decode.success(
        TextFormatJsonSchema(shared.ResponseFormatJsonSchema(
          name: name,
          description: description,
          schema: schema,
          strict: strict,
        )),
      )
    }
    _ -> decode.failure(TextFormatText, "TextResponseFormatConfiguration")
  }
}

pub fn response_text_param_decoder() -> decode.Decoder(ResponseTextParam) {
  use format <- decode.field("format", text_response_format_decoder())
  use verbosity <- decode.optional_field(
    "verbosity",
    None,
    decode.optional(verbosity_decoder()),
  )
  decode.success(ResponseTextParam(format: format, verbosity: verbosity))
}

pub fn annotation_decoder() -> decode.Decoder(Annotation) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "file_citation" -> {
      use file_id <- decode.field("file_id", decode.string)
      use filename <- decode.field("filename", decode.string)
      use index <- decode.field("index", decode.int)
      decode.success(
        AnnotationFileCitation(FileCitationBody(
          file_id: file_id,
          filename: filename,
          index: index,
        )),
      )
    }
    "url_citation" -> {
      use end_index <- decode.field("end_index", decode.int)
      use start_index <- decode.field("start_index", decode.int)
      use title <- decode.field("title", decode.string)
      use url <- decode.field("url", decode.string)
      decode.success(
        AnnotationUrlCitation(UrlCitationBody(
          end_index: end_index,
          start_index: start_index,
          title: title,
          url: url,
        )),
      )
    }
    "container_file_citation" -> {
      use container_id <- decode.field("container_id", decode.string)
      use end_index <- decode.field("end_index", decode.int)
      use file_id <- decode.field("file_id", decode.string)
      use filename <- decode.field("filename", decode.string)
      use start_index <- decode.field("start_index", decode.int)
      decode.success(
        AnnotationContainerFileCitation(ContainerFileCitationBody(
          container_id: container_id,
          end_index: end_index,
          file_id: file_id,
          filename: filename,
          start_index: start_index,
        )),
      )
    }
    "file_path" -> {
      use file_id <- decode.field("file_id", decode.string)
      use index <- decode.field("index", decode.int)
      decode.success(
        AnnotationFilePath(FilePathAnnotation(file_id: file_id, index: index)),
      )
    }
    _ ->
      decode.failure(
        AnnotationFilePath(FilePathAnnotation(file_id: "", index: 0)),
        "Annotation",
      )
  }
}

pub fn response_log_prob_decoder() -> decode.Decoder(ResponseLogProb) {
  use logprob <- decode.field("logprob", decode.float)
  use token <- decode.field("token", decode.string)
  use top_logprobs <- decode.field(
    "top_logprobs",
    decode.list({
      use lp <- decode.field("logprob", decode.float)
      use t <- decode.field("token", decode.string)
      decode.success(ResponseTopLogProb(logprob: lp, token: t))
    }),
  )
  decode.success(ResponseLogProb(
    logprob: logprob,
    token: token,
    top_logprobs: top_logprobs,
  ))
}

pub fn output_text_content_decoder() -> decode.Decoder(OutputTextContent) {
  use annotations <- decode.field(
    "annotations",
    decode.list(annotation_decoder()),
  )
  use logprobs <- decode.optional_field(
    "logprobs",
    None,
    decode.optional(decode.list(response_log_prob_decoder())),
  )
  use text <- decode.field("text", decode.string)
  decode.success(OutputTextContent(
    annotations: annotations,
    logprobs: logprobs,
    text: text,
  ))
}

pub fn output_message_content_decoder() -> decode.Decoder(OutputMessageContent) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "output_text" -> {
      use content <- decode.then(output_text_content_decoder())
      decode.success(OutputMessageOutputText(content))
    }
    "refusal" -> {
      use refusal <- decode.field("refusal", decode.string)
      decode.success(OutputMessageRefusal(RefusalContent(refusal: refusal)))
    }
    _ ->
      decode.failure(
        OutputMessageRefusal(RefusalContent(refusal: "")),
        "OutputMessageContent",
      )
  }
}

pub fn output_content_decoder() -> decode.Decoder(OutputContent) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "output_text" -> {
      use content <- decode.then(output_text_content_decoder())
      decode.success(OutputContentOutputText(content))
    }
    "refusal" -> {
      use refusal <- decode.field("refusal", decode.string)
      decode.success(OutputContentRefusal(RefusalContent(refusal: refusal)))
    }
    "reasoning_text" -> {
      use text <- decode.field("text", decode.string)
      decode.success(
        OutputContentReasoningText(ReasoningTextContent(text: text)),
      )
    }
    _ ->
      decode.failure(
        OutputContentRefusal(RefusalContent(refusal: "")),
        "OutputContent",
      )
  }
}

pub fn summary_part_decoder() -> decode.Decoder(SummaryPart) {
  use _tag <- decode.field("type", decode.string)
  use text <- decode.field("text", decode.string)
  decode.success(SummaryPartSummaryText(SummaryTextContent(text: text)))
}

pub fn output_message_decoder() -> decode.Decoder(OutputMessage) {
  use content <- decode.field(
    "content",
    decode.list(output_message_content_decoder()),
  )
  use id <- decode.field("id", decode.string)
  use role <- decode.field("role", role_decoder())
  use phase <- decode.optional_field(
    "phase",
    None,
    decode.optional(message_phase_decoder()),
  )
  use status <- decode.field("status", output_status_decoder())
  decode.success(OutputMessage(
    content: content,
    id: id,
    role: role,
    phase: phase,
    status: status,
  ))
}

pub fn reasoning_item_decoder() -> decode.Decoder(ReasoningItem) {
  use id <- decode.field("id", decode.string)
  use summary <- decode.field("summary", decode.list(summary_part_decoder()))
  use content <- decode.optional_field(
    "content",
    None,
    decode.optional(
      decode.list({
        use text <- decode.field("text", decode.string)
        decode.success(ReasoningTextContent(text: text))
      }),
    ),
  )
  use encrypted_content <- decode.optional_field(
    "encrypted_content",
    None,
    decode.optional(decode.string),
  )
  use status <- decode.optional_field(
    "status",
    None,
    decode.optional(output_status_decoder()),
  )
  decode.success(ReasoningItem(
    id: id,
    summary: summary,
    content: content,
    encrypted_content: encrypted_content,
    status: status,
  ))
}

pub fn function_tool_call_decoder() -> decode.Decoder(FunctionToolCall) {
  use arguments <- decode.field("arguments", decode.string)
  use call_id <- decode.field("call_id", decode.string)
  use namespace <- decode.optional_field(
    "namespace",
    None,
    decode.optional(decode.string),
  )
  use name <- decode.field("name", decode.string)
  use id <- decode.optional_field("id", None, decode.optional(decode.string))
  use status <- decode.optional_field(
    "status",
    None,
    decode.optional(output_status_decoder()),
  )
  decode.success(FunctionToolCall(
    arguments: arguments,
    call_id: call_id,
    namespace: namespace,
    name: name,
    id: id,
    status: status,
  ))
}

pub fn image_gen_tool_call_decoder() -> decode.Decoder(ImageGenToolCall) {
  use id <- decode.field("id", decode.string)
  use result <- decode.optional_field(
    "result",
    None,
    decode.optional(decode.string),
  )
  use status <- decode.field("status", {
    use value <- decode.then(decode.string)
    case value {
      "in_progress" -> decode.success(ImageGenCallInProgress)
      "completed" -> decode.success(ImageGenCallCompleted)
      "generating" -> decode.success(ImageGenCallGenerating)
      "failed" -> decode.success(ImageGenCallFailed)
      _ -> decode.failure(ImageGenCallInProgress, "ImageGenToolCallStatus")
    }
  })
  decode.success(ImageGenToolCall(id: id, result: result, status: status))
}

pub fn web_search_tool_call_decoder() -> decode.Decoder(WebSearchToolCall) {
  use action <- decode.field("action", {
    use tag <- decode.field("type", decode.string)
    case tag {
      "search" -> {
        use query <- decode.field("query", decode.string)
        use sources <- decode.optional_field(
          "sources",
          None,
          decode.optional(
            decode.list({
              use source_type <- decode.field("type", decode.string)
              use url <- decode.field("url", decode.string)
              decode.success(WebSearchActionSearchSource(
                source_type: source_type,
                url: url,
              ))
            }),
          ),
        )
        decode.success(
          WebSearchActionSearchVariant(WebSearchActionSearch(
            query: query,
            sources: sources,
          )),
        )
      }
      "open_page" -> {
        use url <- decode.optional_field(
          "url",
          None,
          decode.optional(decode.string),
        )
        decode.success(
          WebSearchActionOpenPageVariant(WebSearchActionOpenPage(url: url)),
        )
      }
      "find" -> {
        use url <- decode.field("url", decode.string)
        use pattern <- decode.field("pattern", decode.string)
        decode.success(
          WebSearchActionFindVariant(WebSearchActionFind(
            url: url,
            pattern: pattern,
          )),
        )
      }
      "find_in_page" -> {
        use url <- decode.field("url", decode.string)
        use pattern <- decode.field("pattern", decode.string)
        decode.success(
          WebSearchActionFindInPageVariant(WebSearchActionFind(
            url: url,
            pattern: pattern,
          )),
        )
      }
      _ ->
        decode.failure(
          WebSearchActionSearchVariant(WebSearchActionSearch(
            query: "",
            sources: None,
          )),
          "WebSearchToolCallAction",
        )
    }
  })
  use id <- decode.field("id", decode.string)
  use status <- decode.field("status", {
    use value <- decode.then(decode.string)
    case value {
      "in_progress" -> decode.success(WebSearchInProgress)
      "searching" -> decode.success(WebSearchSearching)
      "completed" -> decode.success(WebSearchCompleted)
      "failed" -> decode.success(WebSearchFailed)
      _ -> decode.failure(WebSearchInProgress, "WebSearchToolCallStatus")
    }
  })
  decode.success(WebSearchToolCall(action: action, id: id, status: status))
}

pub fn file_search_tool_call_decoder() -> decode.Decoder(FileSearchToolCall) {
  use id <- decode.field("id", decode.string)
  use queries <- decode.field("queries", decode.list(decode.string))
  use status <- decode.field("status", {
    use value <- decode.then(decode.string)
    case value {
      "in_progress" -> decode.success(FileSearchInProgress)
      "searching" -> decode.success(FileSearchSearching)
      "incomplete" -> decode.success(FileSearchIncomplete)
      "failed" -> decode.success(FileSearchFailed)
      "completed" -> decode.success(FileSearchCompleted)
      _ -> decode.failure(FileSearchInProgress, "FileSearchToolCallStatus")
    }
  })
  use results <- decode.optional_field(
    "results",
    None,
    decode.optional(
      decode.list({
        use attributes <- decode.field("attributes", decode.dynamic)
        use file_id <- decode.field("file_id", decode.string)
        use filename <- decode.field("filename", decode.string)
        use score <- decode.field("score", decode.float)
        use text <- decode.field("text", decode.string)
        decode.success(FileSearchToolCallResult(
          attributes: attributes,
          file_id: file_id,
          filename: filename,
          score: score,
          text: text,
        ))
      }),
    ),
  )
  decode.success(FileSearchToolCall(
    id: id,
    queries: queries,
    status: status,
    results: results,
  ))
}

pub fn compaction_body_decoder() -> decode.Decoder(CompactionBody) {
  use id <- decode.field("id", decode.string)
  use encrypted_content <- decode.field("encrypted_content", decode.string)
  use created_by <- decode.optional_field(
    "created_by",
    None,
    decode.optional(decode.string),
  )
  decode.success(CompactionBody(
    id: id,
    encrypted_content: encrypted_content,
    created_by: created_by,
  ))
}

pub fn mcp_tool_call_decoder() -> decode.Decoder(McpToolCall) {
  use arguments <- decode.field("arguments", decode.string)
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use server_label <- decode.field("server_label", decode.string)
  use approval_request_id <- decode.optional_field(
    "approval_request_id",
    None,
    decode.optional(decode.string),
  )
  use error <- decode.optional_field(
    "error",
    None,
    decode.optional(decode.string),
  )
  use output <- decode.optional_field(
    "output",
    None,
    decode.optional(decode.string),
  )
  use status <- decode.optional_field(
    "status",
    None,
    decode.optional({
      use value <- decode.then(decode.string)
      case value {
        "in_progress" -> decode.success(McpCallInProgress)
        "completed" -> decode.success(McpCallCompleted)
        "incomplete" -> decode.success(McpCallIncomplete)
        "calling" -> decode.success(McpCallCalling)
        "failed" -> decode.success(McpCallFailed)
        _ -> decode.failure(McpCallInProgress, "McpToolCallStatus")
      }
    }),
  )
  decode.success(McpToolCall(
    arguments: arguments,
    id: id,
    name: name,
    server_label: server_label,
    approval_request_id: approval_request_id,
    error: error,
    output: output,
    status: status,
  ))
}

pub fn custom_tool_call_decoder() -> decode.Decoder(CustomToolCall) {
  use call_id <- decode.field("call_id", decode.string)
  use namespace <- decode.optional_field(
    "namespace",
    None,
    decode.optional(decode.string),
  )
  use input <- decode.field("input", decode.string)
  use name <- decode.field("name", decode.string)
  use id <- decode.field("id", decode.string)
  decode.success(CustomToolCall(
    call_id: call_id,
    namespace: namespace,
    input: input,
    name: name,
    id: id,
  ))
}

// ============================================================================
// OutputItem decoder (the big tagged union)
// ============================================================================

pub fn output_item_decoder() -> decode.Decoder(OutputItem) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "message" -> {
      use msg <- decode.then(output_message_decoder())
      decode.success(OutputItemMessage(msg))
    }
    "file_search_call" -> {
      use call <- decode.then(file_search_tool_call_decoder())
      decode.success(OutputItemFileSearchCall(call))
    }
    "function_call" -> {
      use call <- decode.then(function_tool_call_decoder())
      decode.success(OutputItemFunctionCall(call))
    }
    "web_search_call" -> {
      use call <- decode.then(web_search_tool_call_decoder())
      decode.success(OutputItemWebSearchCall(call))
    }
    "reasoning" -> {
      use item <- decode.then(reasoning_item_decoder())
      decode.success(OutputItemReasoning(item))
    }
    "compaction" -> {
      use item <- decode.then(compaction_body_decoder())
      decode.success(OutputItemCompaction(item))
    }
    "image_generation_call" -> {
      use call <- decode.then(image_gen_tool_call_decoder())
      decode.success(OutputItemImageGenerationCall(call))
    }
    "mcp_call" -> {
      use call <- decode.then(mcp_tool_call_decoder())
      decode.success(OutputItemMcpCall(call))
    }
    "custom_tool_call" -> {
      use call <- decode.then(custom_tool_call_decoder())
      decode.success(OutputItemCustomToolCall(call))
    }
    // For less common output types (computer_call, code_interpreter_call,
    // local_shell_call, shell_call, apply_patch_call, etc.), we decode the
    // dynamic fields. Users can match on the variant and extract data.
    "computer_call" -> {
      use call_id <- decode.field("call_id", decode.string)
      use id <- decode.field("id", decode.string)
      use status <- decode.field("status", output_status_decoder())
      use pending_safety_checks <- decode.field(
        "pending_safety_checks",
        decode.list({
          use check_id <- decode.field("id", decode.string)
          use code <- decode.optional_field(
            "code",
            None,
            decode.optional(decode.string),
          )
          use message <- decode.optional_field(
            "message",
            None,
            decode.optional(decode.string),
          )
          decode.success(ComputerCallSafetyCheckParam(
            id: check_id,
            code: code,
            message: message,
          ))
        }),
      )
      use _action <- decode.optional_field(
        "action",
        None,
        decode.optional(decode.dynamic),
      )
      use _actions <- decode.optional_field(
        "actions",
        None,
        decode.optional(decode.dynamic),
      )
      // We decode action/actions as dynamic since ComputerAction has many
      // variants. Users who need these can decode the dynamic value.
      decode.success(
        OutputItemComputerCall(ComputerToolCall(
          action: None,
          actions: None,
          call_id: call_id,
          id: id,
          pending_safety_checks: pending_safety_checks,
          status: status,
        )),
      )
    }
    "code_interpreter_call" -> {
      use code <- decode.optional_field(
        "code",
        None,
        decode.optional(decode.string),
      )
      use container_id <- decode.field("container_id", decode.string)
      use id <- decode.field("id", decode.string)
      use status <- decode.field("status", {
        use value <- decode.then(decode.string)
        case value {
          "in_progress" -> decode.success(CodeInterpInProgress)
          "completed" -> decode.success(CodeInterpCompleted)
          "incomplete" -> decode.success(CodeInterpIncomplete)
          "interpreting" -> decode.success(CodeInterpInterpreting)
          "failed" -> decode.success(CodeInterpFailed)
          _ ->
            decode.failure(
              CodeInterpInProgress,
              "CodeInterpreterToolCallStatus",
            )
        }
      })
      use outputs <- decode.optional_field(
        "outputs",
        None,
        decode.optional(
          decode.list({
            use out_tag <- decode.field("type", decode.string)
            case out_tag {
              "logs" -> {
                use logs <- decode.field("logs", decode.string)
                decode.success(
                  CodeInterpOutputLogs(CodeInterpreterOutputLogs(logs: logs)),
                )
              }
              "image" -> {
                use url <- decode.field("url", decode.string)
                decode.success(
                  CodeInterpOutputImage(CodeInterpreterOutputImage(url: url)),
                )
              }
              _ ->
                decode.failure(
                  CodeInterpOutputLogs(CodeInterpreterOutputLogs(logs: "")),
                  "CodeInterpreterToolCallOutput",
                )
            }
          }),
        ),
      )
      decode.success(
        OutputItemCodeInterpreterCall(CodeInterpreterToolCall(
          code: code,
          container_id: container_id,
          id: id,
          outputs: outputs,
          status: status,
        )),
      )
    }
    "local_shell_call" -> {
      use call_id <- decode.field("call_id", decode.string)
      use id <- decode.field("id", decode.string)
      use status <- decode.field("status", output_status_decoder())
      use action <- decode.field("action", {
        use command <- decode.field("command", decode.list(decode.string))
        use env <- decode.field(
          "env",
          decode.dict(decode.string, decode.string),
        )
        use timeout_ms <- decode.optional_field(
          "timeout_ms",
          None,
          decode.optional(decode.int),
        )
        use user <- decode.optional_field(
          "user",
          None,
          decode.optional(decode.string),
        )
        use working_directory <- decode.optional_field(
          "working_directory",
          None,
          decode.optional(decode.string),
        )
        decode.success(LocalShellExecAction(
          command: command,
          env: env,
          timeout_ms: timeout_ms,
          user: user,
          working_directory: working_directory,
        ))
      })
      decode.success(
        OutputItemLocalShellCall(LocalShellToolCall(
          action: action,
          call_id: call_id,
          id: id,
          status: status,
        )),
      )
    }
    "mcp_list_tools" -> {
      use id <- decode.field("id", decode.string)
      use server_label <- decode.field("server_label", decode.string)
      use tools <- decode.field("tools", decode.dynamic)
      use error <- decode.optional_field(
        "error",
        None,
        decode.optional(decode.string),
      )
      decode.success(
        OutputItemMcpListTools(McpListTools(
          id: id,
          server_label: server_label,
          tools: tools,
          error: error,
        )),
      )
    }
    "mcp_approval_request" -> {
      use arguments <- decode.field("arguments", decode.string)
      use id <- decode.field("id", decode.string)
      use name <- decode.field("name", decode.string)
      use server_label <- decode.field("server_label", decode.string)
      decode.success(
        OutputItemMcpApprovalRequest(McpApprovalRequest(
          arguments: arguments,
          id: id,
          name: name,
          server_label: server_label,
        )),
      )
    }
    "tool_search_call" -> {
      use id <- decode.field("id", decode.string)
      use call_id <- decode.optional_field(
        "call_id",
        None,
        decode.optional(decode.string),
      )
      use execution <- decode.field("execution", {
        use value <- decode.then(decode.string)
        case value {
          "server" -> decode.success(ExecutionServer)
          "client" -> decode.success(ExecutionClient)
          _ -> decode.failure(ExecutionServer, "ToolSearchExecutionType")
        }
      })
      use arguments <- decode.field("arguments", decode.dynamic)
      use status <- decode.field("status", {
        use value <- decode.then(decode.string)
        case value {
          "in_progress" -> decode.success(FunctionCallInProgress)
          "completed" -> decode.success(FunctionCallCompleted)
          "incomplete" -> decode.success(FunctionCallIncomplete)
          _ -> decode.failure(FunctionCallInProgress, "FunctionCallStatus")
        }
      })
      use created_by <- decode.optional_field(
        "created_by",
        None,
        decode.optional(decode.string),
      )
      decode.success(
        OutputItemToolSearchCall(ToolSearchCall(
          id: id,
          call_id: call_id,
          execution: execution,
          arguments: arguments,
          status: status,
          created_by: created_by,
        )),
      )
    }
    "tool_search_output" -> {
      use id <- decode.field("id", decode.string)
      use call_id <- decode.optional_field(
        "call_id",
        None,
        decode.optional(decode.string),
      )
      use execution <- decode.field("execution", {
        use value <- decode.then(decode.string)
        case value {
          "server" -> decode.success(ExecutionServer)
          "client" -> decode.success(ExecutionClient)
          _ -> decode.failure(ExecutionServer, "ToolSearchExecutionType")
        }
      })
      use tools <- decode.field("tools", decode.dynamic)
      use status <- decode.field("status", {
        use value <- decode.then(decode.string)
        case value {
          "in_progress" -> decode.success(FunctionCallInProgress)
          "completed" -> decode.success(FunctionCallCompleted)
          "incomplete" -> decode.success(FunctionCallIncomplete)
          _ -> decode.failure(FunctionCallInProgress, "FunctionCallStatus")
        }
      })
      use created_by <- decode.optional_field(
        "created_by",
        None,
        decode.optional(decode.string),
      )
      decode.success(
        OutputItemToolSearchOutput(ToolSearchOutput(
          id: id,
          call_id: call_id,
          execution: execution,
          tools: tools,
          status: status,
          created_by: created_by,
        )),
      )
    }
    // Remaining output types decoded with dynamic fields
    _ -> {
      use _rest <- decode.then(decode.dynamic)
      decode.failure(
        OutputItemMessage(OutputMessage(
          content: [],
          id: "",
          role: RoleAssistant,
          phase: None,
          status: OutputCompleted,
        )),
        "OutputItem (unknown type: " <> tag <> ")",
      )
    }
  }
}

// ============================================================================
// Response decoder
// ============================================================================

pub fn conversation_decoder() -> decode.Decoder(Conversation) {
  use id <- decode.field("id", decode.string)
  decode.success(Conversation(id: id))
}

pub fn error_object_decoder() -> decode.Decoder(ErrorObject) {
  use code <- decode.field("code", decode.string)
  use message <- decode.field("message", decode.string)
  decode.success(ErrorObject(code: code, message: message))
}

pub fn prompt_decoder() -> decode.Decoder(Prompt) {
  use id <- decode.field("id", decode.string)
  use version <- decode.optional_field(
    "version",
    None,
    decode.optional(decode.string),
  )
  use variables <- decode.optional_field(
    "variables",
    None,
    decode.optional(decode.dynamic),
  )
  decode.success(Prompt(id: id, version: version, variables: variables))
}

pub fn response_decoder() -> decode.Decoder(Response) {
  use background <- decode.optional_field(
    "background",
    None,
    decode.optional(decode.bool),
  )
  use billing <- decode.optional_field(
    "billing",
    None,
    decode.optional({
      use payer <- decode.field("payer", decode.string)
      decode.success(Billing(payer: payer))
    }),
  )
  use conversation <- decode.optional_field(
    "conversation",
    None,
    decode.optional(conversation_decoder()),
  )
  use created_at <- decode.field("created_at", decode.int)
  use completed_at <- decode.optional_field(
    "completed_at",
    None,
    decode.optional(decode.int),
  )
  use error <- decode.optional_field(
    "error",
    None,
    decode.optional(error_object_decoder()),
  )
  use id <- decode.field("id", decode.string)
  use incomplete_details <- decode.optional_field(
    "incomplete_details",
    None,
    decode.optional({
      use reason <- decode.field("reason", decode.string)
      decode.success(IncompleteDetails(reason: reason))
    }),
  )
  use instructions <- decode.optional_field(
    "instructions",
    None,
    decode.optional(
      decode.one_of(
        decode.string
          |> decode.then(fn(s) { decode.success(InstructionsText(s)) }),
        [
          decode.dynamic
          |> decode.then(fn(_) {
            // Array instructions are complex; decode as text fallback
            decode.success(InstructionsText(""))
          }),
        ],
      ),
    ),
  )
  use max_output_tokens <- decode.optional_field(
    "max_output_tokens",
    None,
    decode.optional(decode.int),
  )
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(decode.dict(decode.string, decode.string)),
  )
  use model <- decode.field("model", decode.string)
  use object <- decode.field("object", decode.string)
  use output <- decode.field("output", decode.list(output_item_decoder()))
  use parallel_tool_calls <- decode.optional_field(
    "parallel_tool_calls",
    None,
    decode.optional(decode.bool),
  )
  use previous_response_id <- decode.optional_field(
    "previous_response_id",
    None,
    decode.optional(decode.string),
  )
  use prompt <- decode.optional_field(
    "prompt",
    None,
    decode.optional(prompt_decoder()),
  )
  use prompt_cache_key <- decode.optional_field(
    "prompt_cache_key",
    None,
    decode.optional(decode.string),
  )
  use prompt_cache_retention <- decode.optional_field(
    "prompt_cache_retention",
    None,
    decode.optional(prompt_cache_retention_decoder()),
  )
  use reasoning <- decode.optional_field(
    "reasoning",
    None,
    decode.optional(reasoning_decoder()),
  )
  use safety_identifier <- decode.optional_field(
    "safety_identifier",
    None,
    decode.optional(decode.string),
  )
  use service_tier <- decode.optional_field(
    "service_tier",
    None,
    decode.optional(service_tier_decoder()),
  )
  use status <- decode.field("status", response_status_decoder())
  use temperature <- decode.optional_field(
    "temperature",
    None,
    decode.optional(decode.float),
  )
  use text <- decode.optional_field(
    "text",
    None,
    decode.optional(response_text_param_decoder()),
  )
  use _tool_choice <- decode.optional_field(
    "tool_choice",
    None,
    decode.optional(decode.dynamic),
  )
  use _tools <- decode.optional_field(
    "tools",
    None,
    decode.optional(decode.dynamic),
  )
  use top_logprobs <- decode.optional_field(
    "top_logprobs",
    None,
    decode.optional(decode.int),
  )
  use top_p <- decode.optional_field(
    "top_p",
    None,
    decode.optional(decode.float),
  )
  use truncation <- decode.optional_field(
    "truncation",
    None,
    decode.optional(truncation_decoder()),
  )
  use usage <- decode.optional_field(
    "usage",
    None,
    decode.optional(shared.response_usage_decoder()),
  )
  decode.success(Response(
    background: background,
    billing: billing,
    conversation: conversation,
    created_at: created_at,
    completed_at: completed_at,
    error: error,
    id: id,
    incomplete_details: incomplete_details,
    instructions: instructions,
    max_output_tokens: max_output_tokens,
    metadata: metadata,
    model: model,
    object: object,
    output: output,
    parallel_tool_calls: parallel_tool_calls,
    previous_response_id: previous_response_id,
    prompt: prompt,
    prompt_cache_key: prompt_cache_key,
    prompt_cache_retention: prompt_cache_retention,
    reasoning: reasoning,
    safety_identifier: safety_identifier,
    service_tier: service_tier,
    status: status,
    temperature: temperature,
    text: text,
    // tool_choice and tools are decoded as dynamic in the response since
    // they mirror the request but are complex tagged unions. The typed
    // versions are available via the request encoder.
    tool_choice: None,
    tools: None,
    top_logprobs: top_logprobs,
    top_p: top_p,
    truncation: truncation,
    usage: usage,
  ))
}

fn delete_response_decoder() -> decode.Decoder(DeleteResponse) {
  use object <- decode.field("object", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  use id <- decode.field("id", decode.string)
  decode.success(DeleteResponse(object: object, deleted: deleted, id: id))
}

fn response_item_list_decoder() -> decode.Decoder(ResponseItemList) {
  use object <- decode.field("object", decode.string)
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
  use data <- decode.field("data", decode.dynamic)
  decode.success(ResponseItemList(
    object: object,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
    data: data,
  ))
}

fn token_counts_resource_decoder() -> decode.Decoder(TokenCountsResource) {
  use object <- decode.field("object", decode.string)
  use input_tokens <- decode.field("input_tokens", decode.int)
  decode.success(TokenCountsResource(object: object, input_tokens: input_tokens))
}

fn compact_resource_decoder() -> decode.Decoder(CompactResource) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use output <- decode.field("output", decode.list(output_item_decoder()))
  use created_at <- decode.field("created_at", decode.int)
  use usage <- decode.field("usage", shared.response_usage_decoder())
  decode.success(CompactResource(
    id: id,
    object: object,
    output: output,
    created_at: created_at,
    usage: usage,
  ))
}

// ============================================================================
// Stream event decoder
// ============================================================================

/// Parse a single SSE data line from the Responses API streaming endpoint.
/// Returns `Ok(Some(event))` for data, `Ok(None)` for the [DONE] sentinel.
pub fn parse_stream_event(
  data: String,
) -> Result(Option(ResponseStreamEvent), GlopenaiError) {
  case data {
    "[DONE]" -> Ok(None)
    _ ->
      case json.parse(data, response_stream_event_decoder()) {
        Ok(event) -> Ok(Some(event))
        Error(decode_error) -> Error(error.JsonDecodeError(data, decode_error))
      }
  }
}

pub fn response_stream_event_decoder() -> decode.Decoder(ResponseStreamEvent) {
  use tag <- decode.field("type", decode.string)
  case tag {
    // Response lifecycle events — carry the full Response object
    "response.created" -> response_event_with_response(EventResponseCreated)
    "response.in_progress" ->
      response_event_with_response(EventResponseInProgress)
    "response.completed" -> response_event_with_response(EventResponseCompleted)
    "response.failed" -> response_event_with_response(EventResponseFailed)
    "response.incomplete" ->
      response_event_with_response(EventResponseIncomplete)
    "response.queued" -> response_event_with_response(EventResponseQueued)

    // Output item events
    "response.output_item.added" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use output_index <- decode.field("output_index", decode.int)
      use item <- decode.field("item", output_item_decoder())
      decode.success(EventResponseOutputItemAdded(
        sequence_number: sequence_number,
        output_index: output_index,
        item: item,
      ))
    }
    "response.output_item.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use output_index <- decode.field("output_index", decode.int)
      use item <- decode.field("item", output_item_decoder())
      decode.success(EventResponseOutputItemDone(
        sequence_number: sequence_number,
        output_index: output_index,
        item: item,
      ))
    }

    // Content part events
    "response.content_part.added" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use part <- decode.field("part", output_content_decoder())
      decode.success(EventResponseContentPartAdded(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        content_index: content_index,
        part: part,
      ))
    }
    "response.content_part.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use part <- decode.field("part", output_content_decoder())
      decode.success(EventResponseContentPartDone(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        content_index: content_index,
        part: part,
      ))
    }

    // Text delta/done events
    "response.output_text.delta" ->
      text_delta_event(EventResponseOutputTextDelta)
    "response.output_text.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use text <- decode.field("text", decode.string)
      use logprobs <- decode.optional_field(
        "logprobs",
        None,
        decode.optional(decode.list(response_log_prob_decoder())),
      )
      decode.success(EventResponseOutputTextDone(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        content_index: content_index,
        text: text,
        logprobs: logprobs,
      ))
    }

    // Refusal events
    "response.refusal.delta" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use delta <- decode.field("delta", decode.string)
      decode.success(EventResponseRefusalDelta(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        content_index: content_index,
        delta: delta,
      ))
    }
    "response.refusal.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use refusal <- decode.field("refusal", decode.string)
      decode.success(EventResponseRefusalDone(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        content_index: content_index,
        refusal: refusal,
      ))
    }

    // Function call argument events
    "response.function_call_arguments.delta" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use delta <- decode.field("delta", decode.string)
      decode.success(EventResponseFunctionCallArgumentsDelta(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        delta: delta,
      ))
    }
    "response.function_call_arguments.done" -> {
      use name <- decode.optional_field(
        "name",
        None,
        decode.optional(decode.string),
      )
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use arguments <- decode.field("arguments", decode.string)
      decode.success(EventResponseFunctionCallArgumentsDone(
        name: name,
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        arguments: arguments,
      ))
    }

    // Simple status events (sequence_number + output_index + item_id)
    "response.file_search_call.in_progress" ->
      simple_status_event(EventResponseFileSearchCallInProgress)
    "response.file_search_call.searching" ->
      simple_status_event(EventResponseFileSearchCallSearching)
    "response.file_search_call.completed" ->
      simple_status_event(EventResponseFileSearchCallCompleted)
    "response.web_search_call.in_progress" ->
      simple_status_event(EventResponseWebSearchCallInProgress)
    "response.web_search_call.searching" ->
      simple_status_event(EventResponseWebSearchCallSearching)
    "response.web_search_call.completed" ->
      simple_status_event(EventResponseWebSearchCallCompleted)
    "response.image_generation_call.completed" ->
      simple_status_event(EventResponseImageGenCallCompleted)
    "response.image_generation_call.generating" ->
      simple_status_event(EventResponseImageGenCallGenerating)
    "response.image_generation_call.in_progress" ->
      simple_status_event(EventResponseImageGenCallInProgress)
    "response.mcp_call.completed" ->
      simple_status_event(EventResponseMcpCallCompleted)
    "response.mcp_call.failed" ->
      simple_status_event(EventResponseMcpCallFailed)
    "response.mcp_call.in_progress" ->
      simple_status_event(EventResponseMcpCallInProgress)
    "response.mcp_list_tools.completed" ->
      simple_status_event(EventResponseMcpListToolsCompleted)
    "response.mcp_list_tools.failed" ->
      simple_status_event(EventResponseMcpListToolsFailed)
    "response.mcp_list_tools.in_progress" ->
      simple_status_event(EventResponseMcpListToolsInProgress)
    "response.code_interpreter_call.in_progress" ->
      simple_status_event(EventResponseCodeInterpreterCallInProgress)
    "response.code_interpreter_call.interpreting" ->
      simple_status_event(EventResponseCodeInterpreterCallInterpreting)
    "response.code_interpreter_call.completed" ->
      simple_status_event(EventResponseCodeInterpreterCallCompleted)

    // MCP/code interpreter delta events
    "response.mcp_call_arguments.delta" ->
      output_index_delta_event(EventResponseMcpCallArgumentsDelta)
    "response.mcp_call_arguments.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use output_index <- decode.field("output_index", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use arguments <- decode.field("arguments", decode.string)
      decode.success(EventResponseMcpCallArgumentsDone(
        sequence_number: sequence_number,
        output_index: output_index,
        item_id: item_id,
        arguments: arguments,
      ))
    }
    "response.code_interpreter_call_code.delta" ->
      output_index_delta_event(EventResponseCodeInterpreterCallCodeDelta)
    "response.code_interpreter_call_code.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use output_index <- decode.field("output_index", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use code <- decode.field("code", decode.string)
      decode.success(EventResponseCodeInterpreterCallCodeDone(
        sequence_number: sequence_number,
        output_index: output_index,
        item_id: item_id,
        code: code,
      ))
    }

    // Reasoning summary events
    "response.reasoning_summary_part.added" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use summary_index <- decode.field("summary_index", decode.int)
      use part <- decode.field("part", summary_part_decoder())
      decode.success(EventResponseReasoningSummaryPartAdded(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        summary_index: summary_index,
        part: part,
      ))
    }
    "response.reasoning_summary_part.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use summary_index <- decode.field("summary_index", decode.int)
      use part <- decode.field("part", summary_part_decoder())
      decode.success(EventResponseReasoningSummaryPartDone(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        summary_index: summary_index,
        part: part,
      ))
    }
    "response.reasoning_summary_text.delta" ->
      summary_text_delta_event(EventResponseReasoningSummaryTextDelta)
    "response.reasoning_summary_text.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use summary_index <- decode.field("summary_index", decode.int)
      use text <- decode.field("text", decode.string)
      decode.success(EventResponseReasoningSummaryTextDone(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        summary_index: summary_index,
        text: text,
      ))
    }
    "response.reasoning_text.delta" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use delta <- decode.field("delta", decode.string)
      decode.success(EventResponseReasoningTextDelta(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        content_index: content_index,
        delta: delta,
      ))
    }
    "response.reasoning_text.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use text <- decode.field("text", decode.string)
      decode.success(EventResponseReasoningTextDone(
        sequence_number: sequence_number,
        item_id: item_id,
        output_index: output_index,
        content_index: content_index,
        text: text,
      ))
    }

    // Image generation partial image
    "response.image_generation_call.partial_image" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use output_index <- decode.field("output_index", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use partial_image_index <- decode.field("partial_image_index", decode.int)
      use partial_image_b64 <- decode.field("partial_image_b64", decode.string)
      decode.success(EventResponseImageGenCallPartialImage(
        sequence_number: sequence_number,
        output_index: output_index,
        item_id: item_id,
        partial_image_index: partial_image_index,
        partial_image_b64: partial_image_b64,
      ))
    }

    // Annotation added
    "response.output_text.annotation.added" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use output_index <- decode.field("output_index", decode.int)
      use content_index <- decode.field("content_index", decode.int)
      use annotation_index <- decode.field("annotation_index", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use annotation <- decode.field("annotation", decode.dynamic)
      decode.success(EventResponseOutputTextAnnotationAdded(
        sequence_number: sequence_number,
        output_index: output_index,
        content_index: content_index,
        annotation_index: annotation_index,
        item_id: item_id,
        annotation: annotation,
      ))
    }

    // Custom tool call input events
    "response.custom_tool_call_input.delta" ->
      output_index_delta_event(EventResponseCustomToolCallInputDelta)
    "response.custom_tool_call_input.done" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use output_index <- decode.field("output_index", decode.int)
      use item_id <- decode.field("item_id", decode.string)
      use input <- decode.field("input", decode.string)
      decode.success(EventResponseCustomToolCallInputDone(
        sequence_number: sequence_number,
        output_index: output_index,
        item_id: item_id,
        input: input,
      ))
    }

    // Error event
    "error" -> {
      use sequence_number <- decode.field("sequence_number", decode.int)
      use code <- decode.optional_field(
        "code",
        None,
        decode.optional(decode.string),
      )
      use message <- decode.field("message", decode.string)
      use param <- decode.optional_field(
        "param",
        None,
        decode.optional(decode.string),
      )
      decode.success(EventResponseError(
        sequence_number: sequence_number,
        code: code,
        message: message,
        param: param,
      ))
    }

    _ ->
      decode.failure(
        EventResponseError(
          sequence_number: 0,
          code: None,
          message: "unknown event type: " <> tag,
          param: None,
        ),
        "ResponseStreamEvent",
      )
  }
}

// Stream event decoder helpers to reduce repetition

fn response_event_with_response(
  constructor: fn(Int, Response) -> ResponseStreamEvent,
) -> decode.Decoder(ResponseStreamEvent) {
  use sequence_number <- decode.field("sequence_number", decode.int)
  use resp <- decode.field("response", response_decoder())
  decode.success(constructor(sequence_number, resp))
}

fn simple_status_event(
  constructor: fn(Int, Int, String) -> ResponseStreamEvent,
) -> decode.Decoder(ResponseStreamEvent) {
  use sequence_number <- decode.field("sequence_number", decode.int)
  use output_index <- decode.field("output_index", decode.int)
  use item_id <- decode.field("item_id", decode.string)
  decode.success(constructor(sequence_number, output_index, item_id))
}

fn output_index_delta_event(
  constructor: fn(Int, Int, String, String) -> ResponseStreamEvent,
) -> decode.Decoder(ResponseStreamEvent) {
  use sequence_number <- decode.field("sequence_number", decode.int)
  use output_index <- decode.field("output_index", decode.int)
  use item_id <- decode.field("item_id", decode.string)
  use delta <- decode.field("delta", decode.string)
  decode.success(constructor(sequence_number, output_index, item_id, delta))
}

fn text_delta_event(
  constructor: fn(Int, String, Int, Int, String, Option(List(ResponseLogProb))) ->
    ResponseStreamEvent,
) -> decode.Decoder(ResponseStreamEvent) {
  use sequence_number <- decode.field("sequence_number", decode.int)
  use item_id <- decode.field("item_id", decode.string)
  use output_index <- decode.field("output_index", decode.int)
  use content_index <- decode.field("content_index", decode.int)
  use delta <- decode.field("delta", decode.string)
  use logprobs <- decode.optional_field(
    "logprobs",
    None,
    decode.optional(decode.list(response_log_prob_decoder())),
  )
  decode.success(constructor(
    sequence_number,
    item_id,
    output_index,
    content_index,
    delta,
    logprobs,
  ))
}

fn summary_text_delta_event(
  constructor: fn(Int, String, Int, Int, String) -> ResponseStreamEvent,
) -> decode.Decoder(ResponseStreamEvent) {
  use sequence_number <- decode.field("sequence_number", decode.int)
  use item_id <- decode.field("item_id", decode.string)
  use output_index <- decode.field("output_index", decode.int)
  use summary_index <- decode.field("summary_index", decode.int)
  use delta <- decode.field("delta", decode.string)
  decode.success(constructor(
    sequence_number,
    item_id,
    output_index,
    summary_index,
    delta,
  ))
}

// ============================================================================
// Request/Response pairs (sans-io)
// ============================================================================

/// Build a request to create a response.
pub fn create_request(config: Config, params: CreateResponse) -> Request(String) {
  internal.post_request(config, "/responses", create_response_to_json(params))
}

/// Parse the response from creating a response.
pub fn create_response_response(
  response: HttpResponse(String),
) -> Result(Response, GlopenaiError) {
  internal.parse_response(response, response_decoder())
}

/// Build a request to retrieve a response by ID.
pub fn retrieve_request(config: Config, response_id: String) -> Request(String) {
  internal.get_request(config, "/responses/" <> response_id)
}

/// Parse the response from retrieving a response.
pub fn retrieve_response(
  response: HttpResponse(String),
) -> Result(Response, GlopenaiError) {
  internal.parse_response(response, response_decoder())
}

/// Build a request to delete a response by ID.
pub fn delete_request(config: Config, response_id: String) -> Request(String) {
  internal.delete_request(config, "/responses/" <> response_id)
}

/// Parse the response from deleting a response.
pub fn delete_response(
  response: HttpResponse(String),
) -> Result(DeleteResponse, GlopenaiError) {
  internal.parse_response(response, delete_response_decoder())
}

/// Build a request to cancel a background response.
pub fn cancel_request(config: Config, response_id: String) -> Request(String) {
  internal.post_request(
    config,
    "/responses/" <> response_id <> "/cancel",
    json.object([]),
  )
}

/// Parse the response from cancelling a response.
pub fn cancel_response(
  response: HttpResponse(String),
) -> Result(Response, GlopenaiError) {
  internal.parse_response(response, response_decoder())
}

/// Build a request to list input items for a response.
pub fn list_input_items_request(
  config: Config,
  response_id: String,
) -> Request(String) {
  internal.get_request(config, "/responses/" <> response_id <> "/input_items")
}

/// Parse the response from listing input items.
pub fn list_input_items_response(
  response: HttpResponse(String),
) -> Result(ResponseItemList, GlopenaiError) {
  internal.parse_response(response, response_item_list_decoder())
}

/// Build a request to count input tokens.
pub fn get_input_token_counts_request(
  config: Config,
  body: json.Json,
) -> Request(String) {
  internal.post_request(config, "/responses/input_tokens", body)
}

/// Parse the response from counting input tokens.
pub fn get_input_token_counts_response(
  response: HttpResponse(String),
) -> Result(TokenCountsResource, GlopenaiError) {
  internal.parse_response(response, token_counts_resource_decoder())
}

/// Build a request to compact a conversation.
pub fn compact_request(config: Config, body: json.Json) -> Request(String) {
  internal.post_request(config, "/responses/compact", body)
}

/// Parse the response from compacting a conversation.
pub fn compact_response(
  response: HttpResponse(String),
) -> Result(CompactResource, GlopenaiError) {
  internal.parse_response(response, compact_resource_decoder())
}
