/// Vector Stores API: create, list, retrieve, update, delete, and search
/// vector stores; manage attached files; manage file batches.
///
/// Three logical groups in one module:
///
/// 1. **Vector store** CRUD + search (`create_request`, `list_request`,
///    `retrieve_request`, `update_request`, `delete_request`, `search_request`)
/// 2. **Vector store files** (`file_create_request`, `file_list_request`,
///    `file_retrieve_request`, `file_delete_request`, `file_update_request`,
///    `file_content_request`)
/// 3. **Vector store file batches** (`batch_create_request`,
///    `batch_retrieve_request`, `batch_cancel_request`,
///    `batch_list_files_request`)

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
// Shared building blocks
// =============================================================================

/// Static chunking strategy. Mirrors Rust's `StaticChunkingStrategy`.
pub type StaticChunkingStrategy {
  StaticChunkingStrategy(max_chunk_size_tokens: Int, chunk_overlap_tokens: Int)
}

pub fn static_chunking_strategy_to_json(
  strategy: StaticChunkingStrategy,
) -> json.Json {
  json.object([
    #("max_chunk_size_tokens", json.int(strategy.max_chunk_size_tokens)),
    #("chunk_overlap_tokens", json.int(strategy.chunk_overlap_tokens)),
  ])
}

pub fn static_chunking_strategy_decoder() -> decode.Decoder(
  StaticChunkingStrategy,
) {
  use max_chunk_size_tokens <- decode.field(
    "max_chunk_size_tokens",
    decode.int,
  )
  use chunk_overlap_tokens <- decode.field("chunk_overlap_tokens", decode.int)
  decode.success(StaticChunkingStrategy(
    max_chunk_size_tokens: max_chunk_size_tokens,
    chunk_overlap_tokens: chunk_overlap_tokens,
  ))
}

// --- Filter (used by VectorStoreSearchRequest.filters) ---

/// A vector-store search filter. Untagged in JSON: a `ComparisonFilter` or a
/// `CompoundFilter`.
pub type Filter {
  ComparisonFilter(filter: ComparisonFilterRecord)
  CompoundFilter(filter: CompoundFilterRecord)
}

pub type ComparisonFilterRecord {
  ComparisonFilterRecord(
    comparison_type: ComparisonType,
    key: String,
    /// Value to compare against. Carry as Dynamic so callers can pass a
    /// string, number, or boolean.
    value: Dynamic,
  )
}

pub type ComparisonType {
  Equals
  NotEquals
  GreaterThan
  GreaterThanOrEqual
  LessThan
  LessThanOrEqual
  In
  NotIn
}

pub type CompoundFilterRecord {
  CompoundFilterRecord(compound_type: CompoundType, filters: List(Filter))
}

pub type CompoundType {
  And
  Or
}

pub fn comparison_type_to_json(comparison_type: ComparisonType) -> json.Json {
  json.string(case comparison_type {
    Equals -> "eq"
    NotEquals -> "ne"
    GreaterThan -> "gt"
    GreaterThanOrEqual -> "gte"
    LessThan -> "lt"
    LessThanOrEqual -> "lte"
    In -> "in"
    NotIn -> "nin"
  })
}

pub fn comparison_type_decoder() -> decode.Decoder(ComparisonType) {
  use value <- decode.then(decode.string)
  case value {
    "eq" -> decode.success(Equals)
    "ne" -> decode.success(NotEquals)
    "gt" -> decode.success(GreaterThan)
    "gte" -> decode.success(GreaterThanOrEqual)
    "lt" -> decode.success(LessThan)
    "lte" -> decode.success(LessThanOrEqual)
    "in" -> decode.success(In)
    "nin" -> decode.success(NotIn)
    _ -> decode.failure(Equals, "ComparisonType")
  }
}

pub fn compound_type_to_json(compound_type: CompoundType) -> json.Json {
  json.string(case compound_type {
    And -> "and"
    Or -> "or"
  })
}

pub fn compound_type_decoder() -> decode.Decoder(CompoundType) {
  use value <- decode.then(decode.string)
  case value {
    "and" -> decode.success(And)
    "or" -> decode.success(Or)
    _ -> decode.failure(And, "CompoundType")
  }
}

pub fn filter_to_json(filter: Filter) -> json.Json {
  case filter {
    ComparisonFilter(record) ->
      json.object([
        #("type", comparison_type_to_json(record.comparison_type)),
        #("key", json.string(record.key)),
        #("value", codec.dynamic_to_json(record.value)),
      ])
    CompoundFilter(record) ->
      json.object([
        #("type", compound_type_to_json(record.compound_type)),
        #("filters", json.array(record.filters, filter_to_json)),
      ])
  }
}

pub fn filter_decoder() -> decode.Decoder(Filter) {
  decode.one_of(compound_filter_decoder(), or: [comparison_filter_decoder()])
}

fn comparison_filter_decoder() -> decode.Decoder(Filter) {
  use comparison_type <- decode.field("type", comparison_type_decoder())
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", decode.dynamic)
  decode.success(
    ComparisonFilter(ComparisonFilterRecord(
      comparison_type: comparison_type,
      key: key,
      value: value,
    )),
  )
}

fn compound_filter_decoder() -> decode.Decoder(Filter) {
  use compound_type <- decode.field("type", compound_type_decoder())
  use filters <- decode.field("filters", decode.list(filter_decoder()))
  decode.success(
    CompoundFilter(CompoundFilterRecord(
      compound_type: compound_type,
      filters: filters,
    )),
  )
}

// =============================================================================
// Vector store core types
// =============================================================================

pub type VectorStoreStatus {
  StoreExpired
  StoreInProgress
  StoreCompleted
}

pub fn vector_store_status_to_json(status: VectorStoreStatus) -> json.Json {
  json.string(case status {
    StoreExpired -> "expired"
    StoreInProgress -> "in_progress"
    StoreCompleted -> "completed"
  })
}

pub fn vector_store_status_decoder() -> decode.Decoder(VectorStoreStatus) {
  use value <- decode.then(decode.string)
  case value {
    "expired" -> decode.success(StoreExpired)
    "in_progress" -> decode.success(StoreInProgress)
    "completed" -> decode.success(StoreCompleted)
    _ -> decode.failure(StoreInProgress, "VectorStoreStatus")
  }
}

pub type VectorStoreFileCounts {
  VectorStoreFileCounts(
    in_progress: Int,
    completed: Int,
    failed: Int,
    cancelled: Int,
    total: Int,
  )
}

pub fn vector_store_file_counts_to_json(
  counts: VectorStoreFileCounts,
) -> json.Json {
  json.object([
    #("in_progress", json.int(counts.in_progress)),
    #("completed", json.int(counts.completed)),
    #("failed", json.int(counts.failed)),
    #("cancelled", json.int(counts.cancelled)),
    #("total", json.int(counts.total)),
  ])
}

pub fn vector_store_file_counts_decoder() -> decode.Decoder(
  VectorStoreFileCounts,
) {
  use in_progress <- decode.field("in_progress", decode.int)
  use completed <- decode.field("completed", decode.int)
  use failed <- decode.field("failed", decode.int)
  use cancelled <- decode.field("cancelled", decode.int)
  use total <- decode.field("total", decode.int)
  decode.success(VectorStoreFileCounts(
    in_progress: in_progress,
    completed: completed,
    failed: failed,
    cancelled: cancelled,
    total: total,
  ))
}

/// Expiration policy for vector stores or chat sessions.
pub type VectorStoreExpirationAfter {
  VectorStoreExpirationAfter(anchor: String, days: Int)
}

pub fn vector_store_expiration_after_to_json(
  expiration: VectorStoreExpirationAfter,
) -> json.Json {
  json.object([
    #("anchor", json.string(expiration.anchor)),
    #("days", json.int(expiration.days)),
  ])
}

pub fn vector_store_expiration_after_decoder() -> decode.Decoder(
  VectorStoreExpirationAfter,
) {
  use anchor <- decode.field("anchor", decode.string)
  use days <- decode.field("days", decode.int)
  decode.success(VectorStoreExpirationAfter(anchor: anchor, days: days))
}

pub type VectorStoreObject {
  VectorStoreObject(
    id: String,
    object: String,
    created_at: Int,
    name: Option(String),
    usage_bytes: Int,
    file_counts: VectorStoreFileCounts,
    status: VectorStoreStatus,
    expires_after: Option(VectorStoreExpirationAfter),
    expires_at: Option(Int),
    last_active_at: Option(Int),
    metadata: Option(Dict(String, String)),
  )
}

pub fn vector_store_object_decoder() -> decode.Decoder(VectorStoreObject) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use name <- decode.optional_field(
    "name",
    None,
    decode.optional(decode.string),
  )
  use usage_bytes <- decode.field("usage_bytes", decode.int)
  use file_counts <- decode.field(
    "file_counts",
    vector_store_file_counts_decoder(),
  )
  use status <- decode.field("status", vector_store_status_decoder())
  use expires_after <- decode.optional_field(
    "expires_after",
    None,
    decode.optional(vector_store_expiration_after_decoder()),
  )
  use expires_at <- decode.optional_field(
    "expires_at",
    None,
    decode.optional(decode.int),
  )
  use last_active_at <- decode.optional_field(
    "last_active_at",
    None,
    decode.optional(decode.int),
  )
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(decode.dict(decode.string, decode.string)),
  )
  decode.success(VectorStoreObject(
    id: id,
    object: object,
    created_at: created_at,
    name: name,
    usage_bytes: usage_bytes,
    file_counts: file_counts,
    status: status,
    expires_after: expires_after,
    expires_at: expires_at,
    last_active_at: last_active_at,
    metadata: metadata,
  ))
}

pub type ListVectorStoresResponse {
  ListVectorStoresResponse(
    object: String,
    data: List(VectorStoreObject),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

fn list_vector_stores_response_decoder() -> decode.Decoder(
  ListVectorStoresResponse,
) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field("data", decode.list(vector_store_object_decoder()))
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
  decode.success(ListVectorStoresResponse(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

pub type DeleteVectorStoreResponse {
  DeleteVectorStoreResponse(id: String, object: String, deleted: Bool)
}

fn delete_vector_store_response_decoder() -> decode.Decoder(
  DeleteVectorStoreResponse,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeleteVectorStoreResponse(
    id: id,
    object: object,
    deleted: deleted,
  ))
}

// --- ChunkingStrategy types ---

/// Tagged: `auto` or `static` with a nested `static` config.
pub type ChunkingStrategyRequestParam {
  AutoChunking
  StaticChunking(config: StaticChunkingStrategy)
}

pub fn chunking_strategy_request_param_to_json(
  strategy: ChunkingStrategyRequestParam,
) -> json.Json {
  case strategy {
    AutoChunking -> json.object([#("type", json.string("auto"))])
    StaticChunking(config) ->
      json.object([
        #("type", json.string("static")),
        #("static", static_chunking_strategy_to_json(config)),
      ])
  }
}

pub fn chunking_strategy_request_param_decoder() -> decode.Decoder(
  ChunkingStrategyRequestParam,
) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "auto" -> decode.success(AutoChunking)
    "static" -> {
      use config <- decode.field("static", static_chunking_strategy_decoder())
      decode.success(StaticChunking(config: config))
    }
    _ -> decode.failure(AutoChunking, "ChunkingStrategyRequestParam")
  }
}

/// Returned on `VectorStoreFileObject.chunking_strategy`. Includes an `Other`
/// variant for files indexed before the strategy concept existed.
pub type ChunkingStrategyResponse {
  OtherChunking
  StaticChunkingResponse(config: StaticChunkingStrategy)
}

pub fn chunking_strategy_response_to_json(
  strategy: ChunkingStrategyResponse,
) -> json.Json {
  case strategy {
    OtherChunking -> json.object([#("type", json.string("other"))])
    StaticChunkingResponse(config) ->
      json.object([
        #("type", json.string("static")),
        #("static", static_chunking_strategy_to_json(config)),
      ])
  }
}

pub fn chunking_strategy_response_decoder() -> decode.Decoder(
  ChunkingStrategyResponse,
) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "other" -> decode.success(OtherChunking)
    "static" -> {
      use config <- decode.field("static", static_chunking_strategy_decoder())
      decode.success(StaticChunkingResponse(config: config))
    }
    _ -> decode.failure(OtherChunking, "ChunkingStrategyResponse")
  }
}

// --- VectorStoreFile types ---

pub type VectorStoreFileStatus {
  FileInProgress
  FileCompleted
  FileCancelled
  FileFailed
}

pub fn vector_store_file_status_to_json(
  status: VectorStoreFileStatus,
) -> json.Json {
  json.string(case status {
    FileInProgress -> "in_progress"
    FileCompleted -> "completed"
    FileCancelled -> "cancelled"
    FileFailed -> "failed"
  })
}

pub fn vector_store_file_status_decoder() -> decode.Decoder(
  VectorStoreFileStatus,
) {
  use value <- decode.then(decode.string)
  case value {
    "in_progress" -> decode.success(FileInProgress)
    "completed" -> decode.success(FileCompleted)
    "cancelled" -> decode.success(FileCancelled)
    "failed" -> decode.success(FileFailed)
    _ -> decode.failure(FileInProgress, "VectorStoreFileStatus")
  }
}

pub type VectorStoreFileErrorCode {
  ServerError
  UnsupportedFile
  InvalidFile
}

pub fn vector_store_file_error_code_decoder() -> decode.Decoder(
  VectorStoreFileErrorCode,
) {
  use value <- decode.then(decode.string)
  case value {
    "server_error" -> decode.success(ServerError)
    "unsupported_file" -> decode.success(UnsupportedFile)
    "invalid_file" -> decode.success(InvalidFile)
    _ -> decode.failure(ServerError, "VectorStoreFileErrorCode")
  }
}

pub type VectorStoreFileError {
  VectorStoreFileError(code: VectorStoreFileErrorCode, message: String)
}

fn vector_store_file_error_decoder() -> decode.Decoder(VectorStoreFileError) {
  use code <- decode.field("code", vector_store_file_error_code_decoder())
  use message <- decode.field("message", decode.string)
  decode.success(VectorStoreFileError(code: code, message: message))
}

/// File attribute value: untagged String / Number / Boolean.
pub type AttributeValue {
  AttributeString(value: String)
  AttributeNumber(value: Int)
  AttributeBoolean(value: Bool)
}

pub fn attribute_value_to_json(value: AttributeValue) -> json.Json {
  case value {
    AttributeString(s) -> json.string(s)
    AttributeNumber(n) -> json.int(n)
    AttributeBoolean(b) -> json.bool(b)
  }
}

pub fn attribute_value_decoder() -> decode.Decoder(AttributeValue) {
  decode.one_of(
    {
      use s <- decode.then(decode.string)
      decode.success(AttributeString(s))
    },
    or: [
      {
        use n <- decode.then(decode.int)
        decode.success(AttributeNumber(n))
      },
      {
        use b <- decode.then(decode.bool)
        decode.success(AttributeBoolean(b))
      },
    ],
  )
}

/// VectorStoreFileAttributes is a transparent newtype around `Dict` in Rust;
/// in Gleam we just use `Dict(String, AttributeValue)` directly.
pub type VectorStoreFileAttributes =
  Dict(String, AttributeValue)

pub fn vector_store_file_attributes_to_json(
  attributes: VectorStoreFileAttributes,
) -> json.Json {
  json.object(
    dict.to_list(attributes)
    |> list.map(fn(pair) { #(pair.0, attribute_value_to_json(pair.1)) }),
  )
}

pub fn vector_store_file_attributes_decoder() -> decode.Decoder(
  VectorStoreFileAttributes,
) {
  decode.dict(decode.string, attribute_value_decoder())
}

pub type VectorStoreFileObject {
  VectorStoreFileObject(
    id: String,
    object: String,
    usage_bytes: Int,
    created_at: Int,
    vector_store_id: String,
    status: VectorStoreFileStatus,
    last_error: Option(VectorStoreFileError),
    chunking_strategy: Option(ChunkingStrategyResponse),
    attributes: Option(VectorStoreFileAttributes),
  )
}

pub fn vector_store_file_object_decoder() -> decode.Decoder(
  VectorStoreFileObject,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use usage_bytes <- decode.field("usage_bytes", decode.int)
  use created_at <- decode.field("created_at", decode.int)
  use vector_store_id <- decode.field("vector_store_id", decode.string)
  use status <- decode.field("status", vector_store_file_status_decoder())
  use last_error <- decode.optional_field(
    "last_error",
    None,
    decode.optional(vector_store_file_error_decoder()),
  )
  use chunking_strategy <- decode.optional_field(
    "chunking_strategy",
    None,
    decode.optional(chunking_strategy_response_decoder()),
  )
  use attributes <- decode.optional_field(
    "attributes",
    None,
    decode.optional(vector_store_file_attributes_decoder()),
  )
  decode.success(VectorStoreFileObject(
    id: id,
    object: object,
    usage_bytes: usage_bytes,
    created_at: created_at,
    vector_store_id: vector_store_id,
    status: status,
    last_error: last_error,
    chunking_strategy: chunking_strategy,
    attributes: attributes,
  ))
}

pub type ListVectorStoreFilesResponse {
  ListVectorStoreFilesResponse(
    object: String,
    data: List(VectorStoreFileObject),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

fn list_vector_store_files_response_decoder() -> decode.Decoder(
  ListVectorStoreFilesResponse,
) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field(
    "data",
    decode.list(vector_store_file_object_decoder()),
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
  decode.success(ListVectorStoreFilesResponse(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

pub type DeleteVectorStoreFileResponse {
  DeleteVectorStoreFileResponse(id: String, object: String, deleted: Bool)
}

fn delete_vector_store_file_response_decoder() -> decode.Decoder(
  DeleteVectorStoreFileResponse,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeleteVectorStoreFileResponse(
    id: id,
    object: object,
    deleted: deleted,
  ))
}

// --- File batch types ---

pub type VectorStoreFileBatchStatus {
  BatchInProgress
  BatchCompleted
  BatchCancelled
  BatchFailed
}

pub fn vector_store_file_batch_status_decoder() -> decode.Decoder(
  VectorStoreFileBatchStatus,
) {
  use value <- decode.then(decode.string)
  case value {
    "in_progress" -> decode.success(BatchInProgress)
    "completed" -> decode.success(BatchCompleted)
    "cancelled" -> decode.success(BatchCancelled)
    "failed" -> decode.success(BatchFailed)
    _ -> decode.failure(BatchInProgress, "VectorStoreFileBatchStatus")
  }
}

pub type VectorStoreFileBatchCounts {
  VectorStoreFileBatchCounts(
    in_progress: Int,
    completed: Int,
    failed: Int,
    cancelled: Int,
    total: Int,
  )
}

fn vector_store_file_batch_counts_decoder() -> decode.Decoder(
  VectorStoreFileBatchCounts,
) {
  use in_progress <- decode.field("in_progress", decode.int)
  use completed <- decode.field("completed", decode.int)
  use failed <- decode.field("failed", decode.int)
  use cancelled <- decode.field("cancelled", decode.int)
  use total <- decode.field("total", decode.int)
  decode.success(VectorStoreFileBatchCounts(
    in_progress: in_progress,
    completed: completed,
    failed: failed,
    cancelled: cancelled,
    total: total,
  ))
}

pub type VectorStoreFileBatchObject {
  VectorStoreFileBatchObject(
    id: String,
    object: String,
    created_at: Int,
    vector_store_id: String,
    status: VectorStoreFileBatchStatus,
    file_counts: VectorStoreFileBatchCounts,
  )
}

fn vector_store_file_batch_object_decoder() -> decode.Decoder(
  VectorStoreFileBatchObject,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use vector_store_id <- decode.field("vector_store_id", decode.string)
  use status <- decode.field(
    "status",
    vector_store_file_batch_status_decoder(),
  )
  use file_counts <- decode.field(
    "file_counts",
    vector_store_file_batch_counts_decoder(),
  )
  decode.success(VectorStoreFileBatchObject(
    id: id,
    object: object,
    created_at: created_at,
    vector_store_id: vector_store_id,
    status: status,
    file_counts: file_counts,
  ))
}

// --- File content types ---

pub type VectorStoreFileContentObject {
  VectorStoreFileContentObject(content_type: String, text: String)
}

fn vector_store_file_content_object_decoder() -> decode.Decoder(
  VectorStoreFileContentObject,
) {
  use content_type <- decode.field("type", decode.string)
  use text <- decode.field("text", decode.string)
  decode.success(VectorStoreFileContentObject(
    content_type: content_type,
    text: text,
  ))
}

pub type VectorStoreFileContentResponse {
  VectorStoreFileContentResponse(
    object: String,
    data: List(VectorStoreFileContentObject),
    has_more: Bool,
    next_page: Option(String),
  )
}

fn vector_store_file_content_response_decoder() -> decode.Decoder(
  VectorStoreFileContentResponse,
) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field(
    "data",
    decode.list(vector_store_file_content_object_decoder()),
  )
  use has_more <- decode.field("has_more", decode.bool)
  use next_page <- decode.optional_field(
    "next_page",
    None,
    decode.optional(decode.string),
  )
  decode.success(VectorStoreFileContentResponse(
    object: object,
    data: data,
    has_more: has_more,
    next_page: next_page,
  ))
}

// --- Search types ---

/// Untagged: `Text(String)` or `Array(List(String))`.
pub type VectorStoreSearchQuery {
  TextQuery(query: String)
  ArrayQuery(queries: List(String))
}

pub fn vector_store_search_query_to_json(
  query: VectorStoreSearchQuery,
) -> json.Json {
  case query {
    TextQuery(q) -> json.string(q)
    ArrayQuery(qs) -> json.array(qs, json.string)
  }
}

pub type Ranker {
  RankerNone
  RankerAuto
  RankerDefault20241115
}

pub fn ranker_to_json(ranker: Ranker) -> json.Json {
  json.string(case ranker {
    RankerNone -> "none"
    RankerAuto -> "auto"
    RankerDefault20241115 -> "default-2024-11-15"
  })
}

pub fn ranker_decoder() -> decode.Decoder(Ranker) {
  use value <- decode.then(decode.string)
  case value {
    "none" -> decode.success(RankerNone)
    "auto" -> decode.success(RankerAuto)
    "default-2024-11-15" -> decode.success(RankerDefault20241115)
    _ -> decode.failure(RankerAuto, "Ranker")
  }
}

pub type RankingOptions {
  RankingOptions(ranker: Option(Ranker), score_threshold: Option(Float))
}

pub fn ranking_options_to_json(options: RankingOptions) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field("ranker", options.ranker, ranker_to_json),
      codec.optional_field(
        "score_threshold",
        options.score_threshold,
        json.float,
      ),
    ],
  )
}

pub fn ranking_options_decoder() -> decode.Decoder(RankingOptions) {
  use ranker <- decode.optional_field(
    "ranker",
    None,
    decode.optional(ranker_decoder()),
  )
  use score_threshold <- decode.optional_field(
    "score_threshold",
    None,
    decode.optional(decode.float),
  )
  decode.success(RankingOptions(
    ranker: ranker,
    score_threshold: score_threshold,
  ))
}

pub type VectorStoreSearchResultContentObject {
  VectorStoreSearchResultContentObject(content_type: String, text: String)
}

fn vector_store_search_result_content_object_decoder() -> decode.Decoder(
  VectorStoreSearchResultContentObject,
) {
  use content_type <- decode.field("type", decode.string)
  use text <- decode.field("text", decode.string)
  decode.success(VectorStoreSearchResultContentObject(
    content_type: content_type,
    text: text,
  ))
}

pub type VectorStoreSearchResultItem {
  VectorStoreSearchResultItem(
    file_id: String,
    filename: String,
    score: Float,
    attributes: VectorStoreFileAttributes,
    content: List(VectorStoreSearchResultContentObject),
  )
}

fn vector_store_search_result_item_decoder() -> decode.Decoder(
  VectorStoreSearchResultItem,
) {
  use file_id <- decode.field("file_id", decode.string)
  use filename <- decode.field("filename", decode.string)
  use score <- decode.field("score", decode.float)
  use attributes <- decode.field(
    "attributes",
    vector_store_file_attributes_decoder(),
  )
  use content <- decode.field(
    "content",
    decode.list(vector_store_search_result_content_object_decoder()),
  )
  decode.success(VectorStoreSearchResultItem(
    file_id: file_id,
    filename: filename,
    score: score,
    attributes: attributes,
    content: content,
  ))
}

pub type VectorStoreSearchResultsPage {
  VectorStoreSearchResultsPage(
    object: String,
    search_query: List(String),
    data: List(VectorStoreSearchResultItem),
    has_more: Bool,
    next_page: Option(String),
  )
}

fn vector_store_search_results_page_decoder() -> decode.Decoder(
  VectorStoreSearchResultsPage,
) {
  use object <- decode.field("object", decode.string)
  use search_query <- decode.field("search_query", decode.list(decode.string))
  use data <- decode.field(
    "data",
    decode.list(vector_store_search_result_item_decoder()),
  )
  use has_more <- decode.field("has_more", decode.bool)
  use next_page <- decode.optional_field(
    "next_page",
    None,
    decode.optional(decode.string),
  )
  decode.success(VectorStoreSearchResultsPage(
    object: object,
    search_query: search_query,
    data: data,
    has_more: has_more,
    next_page: next_page,
  ))
}

// =============================================================================
// Request bodies + builders
// =============================================================================

// --- CreateVectorStoreRequest ---

pub type CreateVectorStoreRequest {
  CreateVectorStoreRequest(
    file_ids: Option(List(String)),
    name: Option(String),
    description: Option(String),
    expires_after: Option(VectorStoreExpirationAfter),
    chunking_strategy: Option(ChunkingStrategyRequestParam),
    metadata: Option(Dict(String, String)),
  )
}

pub fn new_create_request() -> CreateVectorStoreRequest {
  CreateVectorStoreRequest(
    file_ids: None,
    name: None,
    description: None,
    expires_after: None,
    chunking_strategy: None,
    metadata: None,
  )
}

pub fn with_file_ids(
  request: CreateVectorStoreRequest,
  file_ids: List(String),
) -> CreateVectorStoreRequest {
  CreateVectorStoreRequest(..request, file_ids: Some(file_ids))
}

pub fn with_name(
  request: CreateVectorStoreRequest,
  name: String,
) -> CreateVectorStoreRequest {
  CreateVectorStoreRequest(..request, name: Some(name))
}

pub fn with_description(
  request: CreateVectorStoreRequest,
  description: String,
) -> CreateVectorStoreRequest {
  CreateVectorStoreRequest(..request, description: Some(description))
}

pub fn with_expires_after(
  request: CreateVectorStoreRequest,
  expires_after: VectorStoreExpirationAfter,
) -> CreateVectorStoreRequest {
  CreateVectorStoreRequest(..request, expires_after: Some(expires_after))
}

pub fn with_chunking_strategy(
  request: CreateVectorStoreRequest,
  chunking_strategy: ChunkingStrategyRequestParam,
) -> CreateVectorStoreRequest {
  CreateVectorStoreRequest(..request, chunking_strategy: Some(chunking_strategy))
}

pub fn with_metadata(
  request: CreateVectorStoreRequest,
  metadata: Dict(String, String),
) -> CreateVectorStoreRequest {
  CreateVectorStoreRequest(..request, metadata: Some(metadata))
}

pub fn create_vector_store_request_to_json(
  request: CreateVectorStoreRequest,
) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field("file_ids", request.file_ids, fn(ids) {
        json.array(ids, json.string)
      }),
      codec.optional_field("name", request.name, json.string),
      codec.optional_field("description", request.description, json.string),
      codec.optional_field(
        "expires_after",
        request.expires_after,
        vector_store_expiration_after_to_json,
      ),
      codec.optional_field(
        "chunking_strategy",
        request.chunking_strategy,
        chunking_strategy_request_param_to_json,
      ),
      codec.optional_field("metadata", request.metadata, fn(metadata) {
        json.object(
          dict.to_list(metadata)
          |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
        )
      }),
    ],
  )
}

// --- UpdateVectorStoreRequest ---

pub type UpdateVectorStoreRequest {
  UpdateVectorStoreRequest(
    name: Option(String),
    expires_after: Option(VectorStoreExpirationAfter),
    metadata: Option(Dict(String, String)),
  )
}

pub fn new_update_request() -> UpdateVectorStoreRequest {
  UpdateVectorStoreRequest(name: None, expires_after: None, metadata: None)
}

pub fn update_with_name(
  request: UpdateVectorStoreRequest,
  name: String,
) -> UpdateVectorStoreRequest {
  UpdateVectorStoreRequest(..request, name: Some(name))
}

pub fn update_with_expires_after(
  request: UpdateVectorStoreRequest,
  expires_after: VectorStoreExpirationAfter,
) -> UpdateVectorStoreRequest {
  UpdateVectorStoreRequest(..request, expires_after: Some(expires_after))
}

pub fn update_with_metadata(
  request: UpdateVectorStoreRequest,
  metadata: Dict(String, String),
) -> UpdateVectorStoreRequest {
  UpdateVectorStoreRequest(..request, metadata: Some(metadata))
}

pub fn update_vector_store_request_to_json(
  request: UpdateVectorStoreRequest,
) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field("name", request.name, json.string),
      codec.optional_field(
        "expires_after",
        request.expires_after,
        vector_store_expiration_after_to_json,
      ),
      codec.optional_field("metadata", request.metadata, fn(metadata) {
        json.object(
          dict.to_list(metadata)
          |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
        )
      }),
    ],
  )
}

// --- CreateVectorStoreFileRequest ---

pub type CreateVectorStoreFileRequest {
  CreateVectorStoreFileRequest(
    file_id: String,
    chunking_strategy: Option(ChunkingStrategyRequestParam),
    attributes: Option(VectorStoreFileAttributes),
  )
}

pub fn new_create_file_request(
  file_id: String,
) -> CreateVectorStoreFileRequest {
  CreateVectorStoreFileRequest(
    file_id: file_id,
    chunking_strategy: None,
    attributes: None,
  )
}

pub fn file_with_chunking_strategy(
  request: CreateVectorStoreFileRequest,
  chunking_strategy: ChunkingStrategyRequestParam,
) -> CreateVectorStoreFileRequest {
  CreateVectorStoreFileRequest(
    ..request,
    chunking_strategy: Some(chunking_strategy),
  )
}

pub fn file_with_attributes(
  request: CreateVectorStoreFileRequest,
  attributes: VectorStoreFileAttributes,
) -> CreateVectorStoreFileRequest {
  CreateVectorStoreFileRequest(..request, attributes: Some(attributes))
}

pub fn create_vector_store_file_request_to_json(
  request: CreateVectorStoreFileRequest,
) -> json.Json {
  codec.object_with_optional(
    [#("file_id", json.string(request.file_id))],
    [
      codec.optional_field(
        "chunking_strategy",
        request.chunking_strategy,
        chunking_strategy_request_param_to_json,
      ),
      codec.optional_field(
        "attributes",
        request.attributes,
        vector_store_file_attributes_to_json,
      ),
    ],
  )
}

// --- UpdateVectorStoreFileAttributesRequest ---

pub type UpdateVectorStoreFileAttributesRequest {
  UpdateVectorStoreFileAttributesRequest(attributes: VectorStoreFileAttributes)
}

pub fn update_vector_store_file_attributes_request_to_json(
  request: UpdateVectorStoreFileAttributesRequest,
) -> json.Json {
  json.object([
    #("attributes", vector_store_file_attributes_to_json(request.attributes)),
  ])
}

// --- CreateVectorStoreFileBatchRequest ---

pub type CreateVectorStoreFileBatchRequest {
  CreateVectorStoreFileBatchRequest(
    file_ids: Option(List(String)),
    files: Option(List(CreateVectorStoreFileRequest)),
    chunking_strategy: Option(ChunkingStrategyRequestParam),
    attributes: Option(VectorStoreFileAttributes),
  )
}

pub fn new_create_file_batch_request() -> CreateVectorStoreFileBatchRequest {
  CreateVectorStoreFileBatchRequest(
    file_ids: None,
    files: None,
    chunking_strategy: None,
    attributes: None,
  )
}

pub fn batch_with_file_ids(
  request: CreateVectorStoreFileBatchRequest,
  file_ids: List(String),
) -> CreateVectorStoreFileBatchRequest {
  CreateVectorStoreFileBatchRequest(..request, file_ids: Some(file_ids))
}

pub fn batch_with_files(
  request: CreateVectorStoreFileBatchRequest,
  files: List(CreateVectorStoreFileRequest),
) -> CreateVectorStoreFileBatchRequest {
  CreateVectorStoreFileBatchRequest(..request, files: Some(files))
}

pub fn batch_with_chunking_strategy(
  request: CreateVectorStoreFileBatchRequest,
  chunking_strategy: ChunkingStrategyRequestParam,
) -> CreateVectorStoreFileBatchRequest {
  CreateVectorStoreFileBatchRequest(
    ..request,
    chunking_strategy: Some(chunking_strategy),
  )
}

pub fn batch_with_attributes(
  request: CreateVectorStoreFileBatchRequest,
  attributes: VectorStoreFileAttributes,
) -> CreateVectorStoreFileBatchRequest {
  CreateVectorStoreFileBatchRequest(..request, attributes: Some(attributes))
}

pub fn create_vector_store_file_batch_request_to_json(
  request: CreateVectorStoreFileBatchRequest,
) -> json.Json {
  codec.object_with_optional(
    [],
    [
      codec.optional_field("file_ids", request.file_ids, fn(ids) {
        json.array(ids, json.string)
      }),
      codec.optional_field("files", request.files, fn(files) {
        json.array(files, create_vector_store_file_request_to_json)
      }),
      codec.optional_field(
        "chunking_strategy",
        request.chunking_strategy,
        chunking_strategy_request_param_to_json,
      ),
      codec.optional_field(
        "attributes",
        request.attributes,
        vector_store_file_attributes_to_json,
      ),
    ],
  )
}

// --- VectorStoreSearchRequest ---

pub type VectorStoreSearchRequest {
  VectorStoreSearchRequest(
    query: VectorStoreSearchQuery,
    rewrite_query: Option(Bool),
    max_num_results: Option(Int),
    filters: Option(Filter),
    ranking_options: Option(RankingOptions),
  )
}

pub fn new_search_request(
  query: VectorStoreSearchQuery,
) -> VectorStoreSearchRequest {
  VectorStoreSearchRequest(
    query: query,
    rewrite_query: None,
    max_num_results: None,
    filters: None,
    ranking_options: None,
  )
}

pub fn search_with_rewrite_query(
  request: VectorStoreSearchRequest,
  rewrite_query: Bool,
) -> VectorStoreSearchRequest {
  VectorStoreSearchRequest(..request, rewrite_query: Some(rewrite_query))
}

pub fn search_with_max_num_results(
  request: VectorStoreSearchRequest,
  max_num_results: Int,
) -> VectorStoreSearchRequest {
  VectorStoreSearchRequest(..request, max_num_results: Some(max_num_results))
}

pub fn search_with_filters(
  request: VectorStoreSearchRequest,
  filters: Filter,
) -> VectorStoreSearchRequest {
  VectorStoreSearchRequest(..request, filters: Some(filters))
}

pub fn search_with_ranking_options(
  request: VectorStoreSearchRequest,
  ranking_options: RankingOptions,
) -> VectorStoreSearchRequest {
  VectorStoreSearchRequest(..request, ranking_options: Some(ranking_options))
}

pub fn vector_store_search_request_to_json(
  request: VectorStoreSearchRequest,
) -> json.Json {
  codec.object_with_optional(
    [#("query", vector_store_search_query_to_json(request.query))],
    [
      codec.optional_field(
        "rewrite_query",
        request.rewrite_query,
        json.bool,
      ),
      codec.optional_field(
        "max_num_results",
        request.max_num_results,
        json.int,
      ),
      codec.optional_field("filters", request.filters, filter_to_json),
      codec.optional_field(
        "ranking_options",
        request.ranking_options,
        ranking_options_to_json,
      ),
    ],
  )
}

// =============================================================================
// Pagination query types (used with `*_request_with_query`)
// =============================================================================

pub type ListOrder {
  Asc
  Desc
}

fn order_to_string(order: ListOrder) -> String {
  case order {
    Asc -> "asc"
    Desc -> "desc"
  }
}

pub type ListVectorStoresQuery {
  ListVectorStoresQuery(
    limit: Option(Int),
    order: Option(ListOrder),
    after: Option(String),
    before: Option(String),
  )
}

pub fn empty_list_vector_stores_query() -> ListVectorStoresQuery {
  ListVectorStoresQuery(limit: None, order: None, after: None, before: None)
}

fn list_vector_stores_query_pairs(
  query: ListVectorStoresQuery,
) -> List(#(String, String)) {
  list.flatten([
    optional_string_pair("limit", query.limit, int.to_string),
    optional_string_pair("order", query.order, order_to_string),
    optional_string_pair("after", query.after, fn(s) { s }),
    optional_string_pair("before", query.before, fn(s) { s }),
  ])
}

/// File status filter used by both `ListVectorStoreFilesQuery` and
/// `ListFilesInVectorStoreBatchQuery`.
pub type ListFilesFilter {
  FilterInProgress
  FilterCompleted
  FilterFailed
  FilterCancelled
}

fn list_files_filter_to_string(filter: ListFilesFilter) -> String {
  case filter {
    FilterInProgress -> "in_progress"
    FilterCompleted -> "completed"
    FilterFailed -> "failed"
    FilterCancelled -> "cancelled"
  }
}

pub type ListVectorStoreFilesQuery {
  ListVectorStoreFilesQuery(
    limit: Option(Int),
    order: Option(ListOrder),
    after: Option(String),
    before: Option(String),
    filter: Option(ListFilesFilter),
  )
}

pub fn empty_list_vector_store_files_query() -> ListVectorStoreFilesQuery {
  ListVectorStoreFilesQuery(
    limit: None,
    order: None,
    after: None,
    before: None,
    filter: None,
  )
}

fn list_vector_store_files_query_pairs(
  query: ListVectorStoreFilesQuery,
) -> List(#(String, String)) {
  list.flatten([
    optional_string_pair("limit", query.limit, int.to_string),
    optional_string_pair("order", query.order, order_to_string),
    optional_string_pair("after", query.after, fn(s) { s }),
    optional_string_pair("before", query.before, fn(s) { s }),
    optional_string_pair("filter", query.filter, list_files_filter_to_string),
  ])
}

pub type ListFilesInVectorStoreBatchQuery {
  ListFilesInVectorStoreBatchQuery(
    limit: Option(Int),
    order: Option(ListOrder),
    after: Option(String),
    before: Option(String),
    filter: Option(ListFilesFilter),
  )
}

pub fn empty_list_files_in_vector_store_batch_query() -> ListFilesInVectorStoreBatchQuery {
  ListFilesInVectorStoreBatchQuery(
    limit: None,
    order: None,
    after: None,
    before: None,
    filter: None,
  )
}

fn list_files_in_vector_store_batch_query_pairs(
  query: ListFilesInVectorStoreBatchQuery,
) -> List(#(String, String)) {
  list.flatten([
    optional_string_pair("limit", query.limit, int.to_string),
    optional_string_pair("order", query.order, order_to_string),
    optional_string_pair("after", query.after, fn(s) { s }),
    optional_string_pair("before", query.before, fn(s) { s }),
    optional_string_pair("filter", query.filter, list_files_filter_to_string),
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
// Endpoint request/response pairs
// =============================================================================

// --- Vector store CRUD ---

pub fn create_request(
  config: Config,
  request: CreateVectorStoreRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/vector_stores",
    create_vector_store_request_to_json(request),
  )
}

pub fn create_response(
  response: Response(String),
) -> Result(VectorStoreObject, GlopenaiError) {
  internal.parse_response(response, vector_store_object_decoder())
}

pub fn retrieve_request(
  config: Config,
  vector_store_id: String,
) -> Request(String) {
  internal.get_request(config, "/vector_stores/" <> vector_store_id)
}

pub fn retrieve_response(
  response: Response(String),
) -> Result(VectorStoreObject, GlopenaiError) {
  internal.parse_response(response, vector_store_object_decoder())
}

pub fn list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/vector_stores")
}

pub fn list_request_with_query(
  config: Config,
  query: ListVectorStoresQuery,
) -> Request(String) {
  internal.get_request(config, "/vector_stores")
  |> request.set_query(list_vector_stores_query_pairs(query))
}

pub fn list_response(
  response: Response(String),
) -> Result(ListVectorStoresResponse, GlopenaiError) {
  internal.parse_response(response, list_vector_stores_response_decoder())
}

pub fn delete_request(
  config: Config,
  vector_store_id: String,
) -> Request(String) {
  internal.delete_request(config, "/vector_stores/" <> vector_store_id)
}

pub fn delete_response(
  response: Response(String),
) -> Result(DeleteVectorStoreResponse, GlopenaiError) {
  internal.parse_response(response, delete_vector_store_response_decoder())
}

pub fn update_request(
  config: Config,
  vector_store_id: String,
  request: UpdateVectorStoreRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/vector_stores/" <> vector_store_id,
    update_vector_store_request_to_json(request),
  )
}

pub fn update_response(
  response: Response(String),
) -> Result(VectorStoreObject, GlopenaiError) {
  internal.parse_response(response, vector_store_object_decoder())
}

pub fn search_request(
  config: Config,
  vector_store_id: String,
  request: VectorStoreSearchRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/search",
    vector_store_search_request_to_json(request),
  )
}

pub fn search_response(
  response: Response(String),
) -> Result(VectorStoreSearchResultsPage, GlopenaiError) {
  internal.parse_response(response, vector_store_search_results_page_decoder())
}

// --- Vector store files ---

pub fn file_create_request(
  config: Config,
  vector_store_id: String,
  request: CreateVectorStoreFileRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/files",
    create_vector_store_file_request_to_json(request),
  )
}

pub fn file_create_response(
  response: Response(String),
) -> Result(VectorStoreFileObject, GlopenaiError) {
  internal.parse_response(response, vector_store_file_object_decoder())
}

pub fn file_retrieve_request(
  config: Config,
  vector_store_id: String,
  file_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/files/" <> file_id,
  )
}

pub fn file_retrieve_response(
  response: Response(String),
) -> Result(VectorStoreFileObject, GlopenaiError) {
  internal.parse_response(response, vector_store_file_object_decoder())
}

pub fn file_delete_request(
  config: Config,
  vector_store_id: String,
  file_id: String,
) -> Request(String) {
  internal.delete_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/files/" <> file_id,
  )
}

pub fn file_delete_response(
  response: Response(String),
) -> Result(DeleteVectorStoreFileResponse, GlopenaiError) {
  internal.parse_response(
    response,
    delete_vector_store_file_response_decoder(),
  )
}

pub fn file_list_request(
  config: Config,
  vector_store_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/files",
  )
}

pub fn file_list_request_with_query(
  config: Config,
  vector_store_id: String,
  query: ListVectorStoreFilesQuery,
) -> Request(String) {
  internal.get_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/files",
  )
  |> request.set_query(list_vector_store_files_query_pairs(query))
}

pub fn file_list_response(
  response: Response(String),
) -> Result(ListVectorStoreFilesResponse, GlopenaiError) {
  internal.parse_response(response, list_vector_store_files_response_decoder())
}

pub fn file_update_request(
  config: Config,
  vector_store_id: String,
  file_id: String,
  request: UpdateVectorStoreFileAttributesRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/files/" <> file_id,
    update_vector_store_file_attributes_request_to_json(request),
  )
}

pub fn file_update_response(
  response: Response(String),
) -> Result(VectorStoreFileObject, GlopenaiError) {
  internal.parse_response(response, vector_store_file_object_decoder())
}

pub fn file_content_request(
  config: Config,
  vector_store_id: String,
  file_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/files/" <> file_id <> "/content",
  )
}

pub fn file_content_response(
  response: Response(String),
) -> Result(VectorStoreFileContentResponse, GlopenaiError) {
  internal.parse_response(
    response,
    vector_store_file_content_response_decoder(),
  )
}

// --- Vector store file batches ---

pub fn batch_create_request(
  config: Config,
  vector_store_id: String,
  request: CreateVectorStoreFileBatchRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/file_batches",
    create_vector_store_file_batch_request_to_json(request),
  )
}

pub fn batch_create_response(
  response: Response(String),
) -> Result(VectorStoreFileBatchObject, GlopenaiError) {
  internal.parse_response(response, vector_store_file_batch_object_decoder())
}

pub fn batch_retrieve_request(
  config: Config,
  vector_store_id: String,
  batch_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/vector_stores/" <> vector_store_id <> "/file_batches/" <> batch_id,
  )
}

pub fn batch_retrieve_response(
  response: Response(String),
) -> Result(VectorStoreFileBatchObject, GlopenaiError) {
  internal.parse_response(response, vector_store_file_batch_object_decoder())
}

pub fn batch_cancel_request(
  config: Config,
  vector_store_id: String,
  batch_id: String,
) -> Request(String) {
  internal.post_request(
    config,
    "/vector_stores/"
      <> vector_store_id
      <> "/file_batches/"
      <> batch_id
      <> "/cancel",
    json.object([]),
  )
}

pub fn batch_cancel_response(
  response: Response(String),
) -> Result(VectorStoreFileBatchObject, GlopenaiError) {
  internal.parse_response(response, vector_store_file_batch_object_decoder())
}

pub fn batch_list_files_request(
  config: Config,
  vector_store_id: String,
  batch_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/vector_stores/"
      <> vector_store_id
      <> "/file_batches/"
      <> batch_id
      <> "/files",
  )
}

pub fn batch_list_files_request_with_query(
  config: Config,
  vector_store_id: String,
  batch_id: String,
  query: ListFilesInVectorStoreBatchQuery,
) -> Request(String) {
  internal.get_request(
    config,
    "/vector_stores/"
      <> vector_store_id
      <> "/file_batches/"
      <> batch_id
      <> "/files",
  )
  |> request.set_query(list_files_in_vector_store_batch_query_pairs(query))
}

pub fn batch_list_files_response(
  response: Response(String),
) -> Result(ListVectorStoreFilesResponse, GlopenaiError) {
  internal.parse_response(response, list_vector_store_files_response_decoder())
}
