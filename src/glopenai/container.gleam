/// Containers API: create, list, retrieve, and delete containers used by the
/// Code Interpreter tool, plus the container-scoped files sub-resource.
///
/// Endpoints:
///
/// - `create_request`   — `POST   /containers`
/// - `list_request`     — `GET    /containers`       (+ `list_request_with_query`)
/// - `retrieve_request` — `GET    /containers/{id}`
/// - `delete_request`   — `DELETE /containers/{id}`
///
/// File sub-resource (scoped to a container id):
///
/// - `file_create_request`   — `POST   /containers/{id}/files`  (multipart)
/// - `file_list_request`     — `GET    /containers/{id}/files`  (+ `file_list_request_with_query`)
/// - `file_retrieve_request` — `GET    /containers/{id}/files/{file_id}`
/// - `file_delete_request`   — `DELETE /containers/{id}/files/{file_id}`
/// - `file_content_request`  — `GET    /containers/{id}/files/{file_id}/content` — returns raw bytes
import gleam/dynamic/decode
import gleam/http
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
// Types
// =============================================================================

/// Memory limit for a container. The wire values are `1g`, `4g`, `16g`, `64g`
/// (the API's own naming; they are not human-friendly Gleam identifiers, so
/// the variants carry the size as a word).
pub type MemoryLimit {
  OneGigabyte
  FourGigabytes
  SixteenGigabytes
  SixtyFourGigabytes
}

pub fn memory_limit_to_json(limit: MemoryLimit) -> json.Json {
  json.string(case limit {
    OneGigabyte -> "1g"
    FourGigabytes -> "4g"
    SixteenGigabytes -> "16g"
    SixtyFourGigabytes -> "64g"
  })
}

pub fn memory_limit_decoder() -> decode.Decoder(MemoryLimit) {
  use value <- decode.then(decode.string)
  case value {
    "1g" -> decode.success(OneGigabyte)
    "4g" -> decode.success(FourGigabytes)
    "16g" -> decode.success(SixteenGigabytes)
    "64g" -> decode.success(SixtyFourGigabytes)
    _ -> decode.failure(OneGigabyte, "MemoryLimit")
  }
}

/// Anchor for container expiration. The API currently only defines
/// `last_active_at`; modelled as an enum so any future values slot in without
/// breaking callers.
pub type ContainerExpiresAfterAnchor {
  LastActiveAt
}

pub fn container_expires_after_anchor_to_json(
  anchor: ContainerExpiresAfterAnchor,
) -> json.Json {
  json.string(case anchor {
    LastActiveAt -> "last_active_at"
  })
}

pub fn container_expires_after_anchor_decoder() -> decode.Decoder(
  ContainerExpiresAfterAnchor,
) {
  use value <- decode.then(decode.string)
  case value {
    "last_active_at" -> decode.success(LastActiveAt)
    _ -> decode.failure(LastActiveAt, "ContainerExpiresAfterAnchor")
  }
}

/// Expiration policy for a container.
pub type ContainerExpiresAfter {
  ContainerExpiresAfter(anchor: ContainerExpiresAfterAnchor, minutes: Int)
}

pub fn container_expires_after_to_json(
  expires: ContainerExpiresAfter,
) -> json.Json {
  json.object([
    #("anchor", container_expires_after_anchor_to_json(expires.anchor)),
    #("minutes", json.int(expires.minutes)),
  ])
}

pub fn container_expires_after_decoder() -> decode.Decoder(
  ContainerExpiresAfter,
) {
  use anchor <- decode.field("anchor", container_expires_after_anchor_decoder())
  use minutes <- decode.field("minutes", decode.int)
  decode.success(ContainerExpiresAfter(anchor: anchor, minutes: minutes))
}

/// A container. `status` is a free-form string today (e.g. `"active"`,
/// `"deleted"`); leaving it as a string avoids breaking callers when OpenAI
/// adds new lifecycle states.
pub type ContainerResource {
  ContainerResource(
    id: String,
    object: String,
    name: String,
    created_at: Int,
    status: String,
    expires_after: Option(ContainerExpiresAfter),
    last_active_at: Option(Int),
    memory_limit: MemoryLimit,
  )
}

pub fn container_resource_decoder() -> decode.Decoder(ContainerResource) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use name <- decode.field("name", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use status <- decode.field("status", decode.string)
  use expires_after <- decode.optional_field(
    "expires_after",
    None,
    decode.optional(container_expires_after_decoder()),
  )
  use last_active_at <- decode.optional_field(
    "last_active_at",
    None,
    decode.optional(decode.int),
  )
  use memory_limit <- decode.field("memory_limit", memory_limit_decoder())
  decode.success(ContainerResource(
    id: id,
    object: object,
    name: name,
    created_at: created_at,
    status: status,
    expires_after: expires_after,
    last_active_at: last_active_at,
    memory_limit: memory_limit,
  ))
}

/// Paginated list of containers.
pub type ContainerListResource {
  ContainerListResource(
    object: String,
    data: List(ContainerResource),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

fn container_list_resource_decoder() -> decode.Decoder(ContainerListResource) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field("data", decode.list(container_resource_decoder()))
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
  decode.success(ContainerListResource(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

pub type DeleteContainerResponse {
  DeleteContainerResponse(id: String, object: String, deleted: Bool)
}

fn delete_container_response_decoder() -> decode.Decoder(
  DeleteContainerResponse,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeleteContainerResponse(
    id: id,
    object: object,
    deleted: deleted,
  ))
}

// --- Container files ---

pub type ContainerFileResource {
  ContainerFileResource(
    id: String,
    object: String,
    container_id: String,
    created_at: Int,
    bytes: Int,
    path: String,
    source: String,
  )
}

pub fn container_file_resource_decoder() -> decode.Decoder(
  ContainerFileResource,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use container_id <- decode.field("container_id", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use bytes <- decode.field("bytes", decode.int)
  use path <- decode.field("path", decode.string)
  use source <- decode.field("source", decode.string)
  decode.success(ContainerFileResource(
    id: id,
    object: object,
    container_id: container_id,
    created_at: created_at,
    bytes: bytes,
    path: path,
    source: source,
  ))
}

pub type ContainerFileListResource {
  ContainerFileListResource(
    object: String,
    data: List(ContainerFileResource),
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

fn container_file_list_resource_decoder() -> decode.Decoder(
  ContainerFileListResource,
) {
  use object <- decode.field("object", decode.string)
  use data <- decode.field(
    "data",
    decode.list(container_file_resource_decoder()),
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
  decode.success(ContainerFileListResource(
    object: object,
    data: data,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

pub type DeleteContainerFileResponse {
  DeleteContainerFileResponse(id: String, object: String, deleted: Bool)
}

fn delete_container_file_response_decoder() -> decode.Decoder(
  DeleteContainerFileResponse,
) {
  use id <- decode.field("id", decode.string)
  use object <- decode.field("object", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeleteContainerFileResponse(
    id: id,
    object: object,
    deleted: deleted,
  ))
}

// =============================================================================
// Request bodies + builders
// =============================================================================

// --- CreateContainerRequest (JSON body) ---

pub type CreateContainerRequest {
  CreateContainerRequest(
    name: String,
    file_ids: Option(List(String)),
    expires_after: Option(ContainerExpiresAfter),
    memory_limit: Option(MemoryLimit),
  )
}

pub fn new_create_request(name: String) -> CreateContainerRequest {
  CreateContainerRequest(
    name: name,
    file_ids: None,
    expires_after: None,
    memory_limit: None,
  )
}

pub fn with_file_ids(
  request: CreateContainerRequest,
  file_ids: List(String),
) -> CreateContainerRequest {
  CreateContainerRequest(..request, file_ids: Some(file_ids))
}

pub fn with_expires_after(
  request: CreateContainerRequest,
  expires_after: ContainerExpiresAfter,
) -> CreateContainerRequest {
  CreateContainerRequest(..request, expires_after: Some(expires_after))
}

pub fn with_memory_limit(
  request: CreateContainerRequest,
  memory_limit: MemoryLimit,
) -> CreateContainerRequest {
  CreateContainerRequest(..request, memory_limit: Some(memory_limit))
}

pub fn create_container_request_to_json(
  request: CreateContainerRequest,
) -> json.Json {
  codec.object_with_optional([#("name", json.string(request.name))], [
    codec.optional_field("file_ids", request.file_ids, fn(ids) {
      json.array(ids, json.string)
    }),
    codec.optional_field(
      "expires_after",
      request.expires_after,
      container_expires_after_to_json,
    ),
    codec.optional_field(
      "memory_limit",
      request.memory_limit,
      memory_limit_to_json,
    ),
  ])
}

// --- CreateContainerFileRequest (multipart body) ---

/// Two mutually exclusive ways to add a file to a container:
///
/// - `UploadBytes` — upload a new file inline. The caller provides the raw
///   bytes, the filename that should appear in the container, and the
///   content type for the multipart part.
/// - `UploadByFileId` — reference an already-uploaded file by id. No bytes
///   are sent, only the `file_id` form field.
///
/// Modelled as a sum type so the two shapes cannot collide.
pub type ContainerFileUpload {
  UploadBytes(filename: String, content_type: String, data: BitArray)
  UploadByFileId(file_id: String)
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

pub type ListContainersQuery {
  ListContainersQuery(
    limit: Option(Int),
    order: Option(ListOrder),
    after: Option(String),
  )
}

pub fn empty_list_containers_query() -> ListContainersQuery {
  ListContainersQuery(limit: None, order: None, after: None)
}

fn list_containers_query_pairs(
  query: ListContainersQuery,
) -> List(#(String, String)) {
  list.flatten([
    optional_string_pair("limit", query.limit, int.to_string),
    optional_string_pair("order", query.order, order_to_string),
    optional_string_pair("after", query.after, fn(s) { s }),
  ])
}

pub type ListContainerFilesQuery {
  ListContainerFilesQuery(
    limit: Option(Int),
    order: Option(ListOrder),
    after: Option(String),
  )
}

pub fn empty_list_container_files_query() -> ListContainerFilesQuery {
  ListContainerFilesQuery(limit: None, order: None, after: None)
}

fn list_container_files_query_pairs(
  query: ListContainerFilesQuery,
) -> List(#(String, String)) {
  list.flatten([
    optional_string_pair("limit", query.limit, int.to_string),
    optional_string_pair("order", query.order, order_to_string),
    optional_string_pair("after", query.after, fn(s) { s }),
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
// Endpoints — containers
// =============================================================================

pub fn create_request(
  config: Config,
  request: CreateContainerRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/containers",
    create_container_request_to_json(request),
  )
}

pub fn create_response(
  response: Response(String),
) -> Result(ContainerResource, GlopenaiError) {
  internal.parse_response(response, container_resource_decoder())
}

pub fn list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/containers")
}

pub fn list_request_with_query(
  config: Config,
  query: ListContainersQuery,
) -> Request(String) {
  internal.get_request(config, "/containers")
  |> request.set_query(list_containers_query_pairs(query))
}

pub fn list_response(
  response: Response(String),
) -> Result(ContainerListResource, GlopenaiError) {
  internal.parse_response(response, container_list_resource_decoder())
}

pub fn retrieve_request(config: Config, container_id: String) -> Request(String) {
  internal.get_request(config, "/containers/" <> container_id)
}

pub fn retrieve_response(
  response: Response(String),
) -> Result(ContainerResource, GlopenaiError) {
  internal.parse_response(response, container_resource_decoder())
}

pub fn delete_request(config: Config, container_id: String) -> Request(String) {
  internal.delete_request(config, "/containers/" <> container_id)
}

pub fn delete_response(
  response: Response(String),
) -> Result(DeleteContainerResponse, GlopenaiError) {
  internal.parse_response(response, delete_container_response_decoder())
}

// =============================================================================
// Endpoints — container files
// =============================================================================

/// Build a multipart `POST /containers/{container_id}/files` request.
///
/// When uploading raw bytes, the caller supplies `boundary` explicitly — it
/// must not appear inside `data`. The `file_id` variant still goes through
/// multipart (matching the Rust client) but carries only a single text field.
pub fn file_create_request(
  config: Config,
  container_id: String,
  upload: ContainerFileUpload,
  boundary: String,
) -> Request(BitArray) {
  let parts = case upload {
    UploadBytes(filename, content_type, data) -> [
      internal.FilePart(
        name: "file",
        filename: filename,
        content_type: content_type,
        data: data,
      ),
    ]
    UploadByFileId(file_id) -> [
      internal.FieldPart(name: "file_id", value: file_id),
    ]
  }
  internal.multipart_request(
    config,
    http.Post,
    "/containers/" <> container_id <> "/files",
    parts,
    boundary,
  )
}

pub fn file_create_response(
  response: Response(String),
) -> Result(ContainerFileResource, GlopenaiError) {
  internal.parse_response(response, container_file_resource_decoder())
}

pub fn file_list_request(
  config: Config,
  container_id: String,
) -> Request(String) {
  internal.get_request(config, "/containers/" <> container_id <> "/files")
}

pub fn file_list_request_with_query(
  config: Config,
  container_id: String,
  query: ListContainerFilesQuery,
) -> Request(String) {
  internal.get_request(config, "/containers/" <> container_id <> "/files")
  |> request.set_query(list_container_files_query_pairs(query))
}

pub fn file_list_response(
  response: Response(String),
) -> Result(ContainerFileListResource, GlopenaiError) {
  internal.parse_response(response, container_file_list_resource_decoder())
}

pub fn file_retrieve_request(
  config: Config,
  container_id: String,
  file_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/containers/" <> container_id <> "/files/" <> file_id,
  )
}

pub fn file_retrieve_response(
  response: Response(String),
) -> Result(ContainerFileResource, GlopenaiError) {
  internal.parse_response(response, container_file_resource_decoder())
}

pub fn file_delete_request(
  config: Config,
  container_id: String,
  file_id: String,
) -> Request(String) {
  internal.delete_request(
    config,
    "/containers/" <> container_id <> "/files/" <> file_id,
  )
}

pub fn file_delete_response(
  response: Response(String),
) -> Result(DeleteContainerFileResponse, GlopenaiError) {
  internal.parse_response(response, delete_container_file_response_decoder())
}

/// Build a request for the raw file content. The body is returned as bytes
/// (typed as `String` to keep the sans-IO signature uniform; clients that
/// need strict binary handling should use `httpc.send_bits` and decode).
pub fn file_content_request(
  config: Config,
  container_id: String,
  file_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/containers/" <> container_id <> "/files/" <> file_id <> "/content",
  )
}

/// Parse a file-content response. On 2xx returns the raw body string.
/// On non-2xx attempts to decode an API error, falling back to
/// `UnexpectedResponse`.
pub fn file_content_response(
  response: Response(String),
) -> Result(String, GlopenaiError) {
  case response.status >= 200 && response.status < 300 {
    True -> Ok(response.body)
    False ->
      case json.parse(response.body, error.wrapped_error_decoder()) {
        Ok(api_error) ->
          Error(error.ApiResponseError(response.status, api_error))
        Error(_) ->
          Error(error.UnexpectedResponse(response.status, response.body))
      }
  }
}
