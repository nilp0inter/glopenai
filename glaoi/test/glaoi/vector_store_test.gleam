import gleam/dict
import gleam/dynamic
import gleam/http
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glaoi/config
import glaoi/vector_store as vs

// --- Vector store CRUD ---

pub fn create_request_minimal_test() {
  let cfg = config.new("test-key")
  let req = vs.create_request(cfg, vs.new_create_request())
  assert req.method == http.Post
  let assert True = string.contains(req.path, "/vector_stores")
  // Empty request body should serialize to {}.
  assert req.body == "{}"
}

pub fn create_request_with_options_test() {
  let cfg = config.new("test-key")
  let request =
    vs.new_create_request()
    |> vs.with_name("docs")
    |> vs.with_file_ids(["file_1", "file_2"])
    |> vs.with_chunking_strategy(vs.AutoChunking)
    |> vs.with_metadata(dict.from_list([#("env", "prod")]))
  let req = vs.create_request(cfg, request)

  let assert True = string.contains(req.body, "\"name\":\"docs\"")
  let assert True = string.contains(req.body, "\"file_1\"")
  let assert True = string.contains(req.body, "\"file_2\"")
  let assert True = string.contains(req.body, "\"chunking_strategy\":")
  let assert True = string.contains(req.body, "\"type\":\"auto\"")
  let assert True = string.contains(req.body, "\"metadata\":")
  let assert True = string.contains(req.body, "\"env\":\"prod\"")
}

pub fn create_request_static_chunking_test() {
  let cfg = config.new("test-key")
  let request =
    vs.new_create_request()
    |> vs.with_chunking_strategy(
      vs.StaticChunking(vs.StaticChunkingStrategy(800, 400)),
    )
  let req = vs.create_request(cfg, request)
  let assert True = string.contains(req.body, "\"type\":\"static\"")
  let assert True =
    string.contains(req.body, "\"max_chunk_size_tokens\":800")
  let assert True = string.contains(req.body, "\"chunk_overlap_tokens\":400")
}

pub fn create_response_decodes_test() {
  let body =
    "{\"id\":\"vs_123\",\"object\":\"vector_store\",\"created_at\":1700000000,\"name\":\"docs\",\"usage_bytes\":4096,\"file_counts\":{\"in_progress\":0,\"completed\":2,\"failed\":0,\"cancelled\":0,\"total\":2},\"status\":\"completed\"}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(store) = vs.create_response(resp)
  assert store.id == "vs_123"
  assert store.usage_bytes == 4096
  assert store.name == Some("docs")
  assert store.status == vs.StoreCompleted
  assert store.file_counts.completed == 2
  assert store.expires_after == None
}

pub fn list_request_with_query_test() {
  let cfg = config.new("test-key")
  let query =
    vs.ListVectorStoresQuery(
      limit: Some(20),
      order: Some(vs.Desc),
      after: Some("vs_99"),
      before: None,
    )
  let req = vs.list_request_with_query(cfg, query)
  let assert True = string.contains(req.path, "/vector_stores")
  let assert Some(qs) = req.query
  let assert True = string.contains(qs, "limit=20")
  let assert True = string.contains(qs, "order=desc")
  let assert True = string.contains(qs, "after=vs_99")
}

pub fn list_response_decodes_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"id\":\"vs_1\",\"object\":\"vector_store\",\"created_at\":1,\"name\":null,\"usage_bytes\":0,\"file_counts\":{\"in_progress\":0,\"completed\":0,\"failed\":0,\"cancelled\":0,\"total\":0},\"status\":\"in_progress\"}],\"first_id\":\"vs_1\",\"last_id\":\"vs_1\",\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = vs.list_response(resp)
  assert result.object == "list"
  assert result.has_more == False
  let assert [store] = result.data
  assert store.id == "vs_1"
  assert store.name == None
  assert store.status == vs.StoreInProgress
}

pub fn delete_request_builds_test() {
  let cfg = config.new("test-key")
  let req = vs.delete_request(cfg, "vs_42")
  assert req.method == http.Delete
  let assert True = string.contains(req.path, "/vector_stores/vs_42")
}

pub fn delete_response_decodes_test() {
  let body = "{\"id\":\"vs_42\",\"object\":\"vector_store.deleted\",\"deleted\":true}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = vs.delete_response(resp)
  assert result.id == "vs_42"
  assert result.deleted == True
}

pub fn update_request_builds_test() {
  let cfg = config.new("test-key")
  let req =
    vs.update_request(
      cfg,
      "vs_42",
      vs.new_update_request() |> vs.update_with_name("renamed"),
    )
  assert req.method == http.Post
  let assert True = string.contains(req.path, "/vector_stores/vs_42")
  let assert True = string.contains(req.body, "\"name\":\"renamed\"")
}

// --- Search ---

pub fn search_request_text_query_test() {
  let cfg = config.new("test-key")
  let req =
    vs.search_request(
      cfg,
      "vs_42",
      vs.new_search_request(vs.TextQuery("hello"))
        |> vs.search_with_max_num_results(10)
        |> vs.search_with_rewrite_query(True),
    )
  let assert True = string.contains(req.path, "/vector_stores/vs_42/search")
  let assert True = string.contains(req.body, "\"query\":\"hello\"")
  let assert True = string.contains(req.body, "\"max_num_results\":10")
  let assert True = string.contains(req.body, "\"rewrite_query\":true")
}

pub fn search_request_array_query_test() {
  let cfg = config.new("test-key")
  let req =
    vs.search_request(
      cfg,
      "vs_42",
      vs.new_search_request(vs.ArrayQuery(["a", "b"])),
    )
  let assert True = string.contains(req.body, "\"query\":[\"a\",\"b\"]")
}

pub fn search_request_with_filter_test() {
  let cfg = config.new("test-key")
  let filter =
    vs.CompoundFilter(vs.CompoundFilterRecord(
      compound_type: vs.And,
      filters: [
        vs.ComparisonFilter(vs.ComparisonFilterRecord(
          comparison_type: vs.Equals,
          key: "kind",
          value: dynamic.string("doc"),
        )),
      ],
    ))
  let req =
    vs.search_request(
      cfg,
      "vs_42",
      vs.new_search_request(vs.TextQuery("x"))
        |> vs.search_with_filters(filter),
    )
  let assert True = string.contains(req.body, "\"type\":\"and\"")
  let assert True = string.contains(req.body, "\"filters\":")
  let assert True = string.contains(req.body, "\"key\":\"kind\"")
}

pub fn search_response_decodes_test() {
  let body =
    "{\"object\":\"vector_store.search_results.page\",\"search_query\":[\"hello\"],\"data\":[{\"file_id\":\"file_1\",\"filename\":\"a.txt\",\"score\":0.92,\"attributes\":{\"k\":\"v\"},\"content\":[{\"type\":\"text\",\"text\":\"hello world\"}]}],\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(page) = vs.search_response(resp)
  assert page.has_more == False
  assert page.next_page == None
  let assert [item] = page.data
  assert item.file_id == "file_1"
  assert item.score == 0.92
  let assert [chunk] = item.content
  assert chunk.text == "hello world"
}

// --- Files ---

pub fn file_create_request_builds_test() {
  let cfg = config.new("test-key")
  let req =
    vs.file_create_request(
      cfg,
      "vs_1",
      vs.new_create_file_request("file_1")
        |> vs.file_with_attributes(
          dict.from_list([
            #("k", vs.AttributeString("v")),
            #("n", vs.AttributeNumber(1)),
            #("flag", vs.AttributeBoolean(True)),
          ]),
        ),
    )
  assert req.method == http.Post
  let assert True = string.contains(req.path, "/vector_stores/vs_1/files")
  let assert True = string.contains(req.body, "\"file_id\":\"file_1\"")
  let assert True = string.contains(req.body, "\"k\":\"v\"")
  let assert True = string.contains(req.body, "\"n\":1")
  let assert True = string.contains(req.body, "\"flag\":true")
}

pub fn file_retrieve_request_builds_test() {
  let cfg = config.new("test-key")
  let req = vs.file_retrieve_request(cfg, "vs_1", "file_1")
  assert req.method == http.Get
  let assert True =
    string.contains(req.path, "/vector_stores/vs_1/files/file_1")
}

pub fn file_list_with_query_filter_test() {
  let cfg = config.new("test-key")
  let req =
    vs.file_list_request_with_query(
      cfg,
      "vs_1",
      vs.empty_list_vector_store_files_query()
        |> fn(q) {
          vs.ListVectorStoreFilesQuery(
            ..q,
            limit: Some(50),
            filter: Some(vs.FilterCompleted),
          )
        },
    )
  let assert Some(qs) = req.query
  let assert True = string.contains(qs, "limit=50")
  let assert True = string.contains(qs, "filter=completed")
}

pub fn file_response_decodes_with_static_chunking_test() {
  let body =
    "{\"id\":\"file_1\",\"object\":\"vector_store.file\",\"usage_bytes\":1024,\"created_at\":1700000000,\"vector_store_id\":\"vs_1\",\"status\":\"completed\",\"chunking_strategy\":{\"type\":\"static\",\"static\":{\"max_chunk_size_tokens\":800,\"chunk_overlap_tokens\":400}},\"attributes\":{\"src\":\"manual\"}}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(file) = vs.file_retrieve_response(resp)
  assert file.id == "file_1"
  assert file.status == vs.FileCompleted
  let assert Some(vs.StaticChunkingResponse(cfg)) = file.chunking_strategy
  assert cfg.max_chunk_size_tokens == 800
  let assert Some(attrs) = file.attributes
  let assert Ok(vs.AttributeString("manual")) = dict.get(attrs, "src")
}

pub fn file_response_decodes_with_other_chunking_test() {
  let body =
    "{\"id\":\"file_2\",\"object\":\"vector_store.file\",\"usage_bytes\":0,\"created_at\":1,\"vector_store_id\":\"vs_1\",\"status\":\"failed\",\"chunking_strategy\":{\"type\":\"other\"},\"last_error\":{\"code\":\"invalid_file\",\"message\":\"bad\"}}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(file) = vs.file_retrieve_response(resp)
  assert file.status == vs.FileFailed
  assert file.chunking_strategy == Some(vs.OtherChunking)
  let assert Some(err) = file.last_error
  assert err.code == vs.InvalidFile
  assert err.message == "bad"
}

pub fn file_content_response_decodes_test() {
  let body =
    "{\"object\":\"vector_store.file_content.page\",\"data\":[{\"type\":\"text\",\"text\":\"chunk 1\"},{\"type\":\"text\",\"text\":\"chunk 2\"}],\"has_more\":true,\"next_page\":\"page_2\"}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(content) = vs.file_content_response(resp)
  assert content.has_more == True
  assert content.next_page == Some("page_2")
  let assert [first, _] = content.data
  assert first.text == "chunk 1"
  assert list.length(content.data) == 2
}

pub fn file_update_attributes_request_builds_test() {
  let cfg = config.new("test-key")
  let req =
    vs.file_update_request(
      cfg,
      "vs_1",
      "file_1",
      vs.UpdateVectorStoreFileAttributesRequest(
        attributes: dict.from_list([#("k", vs.AttributeString("v"))]),
      ),
    )
  assert req.method == http.Post
  let assert True = string.contains(req.body, "\"k\":\"v\"")
}

pub fn file_delete_request_builds_test() {
  let cfg = config.new("test-key")
  let req = vs.file_delete_request(cfg, "vs_1", "file_1")
  assert req.method == http.Delete
}

// --- Batches ---

pub fn batch_create_request_builds_test() {
  let cfg = config.new("test-key")
  let req =
    vs.batch_create_request(
      cfg,
      "vs_1",
      vs.new_create_file_batch_request()
        |> vs.batch_with_file_ids(["file_a", "file_b"]),
    )
  assert req.method == http.Post
  let assert True =
    string.contains(req.path, "/vector_stores/vs_1/file_batches")
  let assert True =
    string.contains(req.body, "\"file_ids\":[\"file_a\",\"file_b\"]")
}

pub fn batch_response_decodes_test() {
  let body =
    "{\"id\":\"batch_1\",\"object\":\"vector_store.files_batch\",\"created_at\":1700000000,\"vector_store_id\":\"vs_1\",\"status\":\"in_progress\",\"file_counts\":{\"in_progress\":1,\"completed\":0,\"failed\":0,\"cancelled\":0,\"total\":1}}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(batch) = vs.batch_create_response(resp)
  assert batch.id == "batch_1"
  assert batch.status == vs.BatchInProgress
  assert batch.file_counts.in_progress == 1
}

pub fn batch_cancel_request_builds_test() {
  let cfg = config.new("test-key")
  let req = vs.batch_cancel_request(cfg, "vs_1", "batch_1")
  assert req.method == http.Post
  let assert True =
    string.contains(req.path, "/file_batches/batch_1/cancel")
  // POST cancel must carry an empty JSON body.
  assert req.body == "{}"
}

pub fn batch_list_files_with_query_test() {
  let cfg = config.new("test-key")
  let req =
    vs.batch_list_files_request_with_query(
      cfg,
      "vs_1",
      "batch_1",
      vs.ListFilesInVectorStoreBatchQuery(
        limit: Some(10),
        order: Some(vs.Asc),
        after: None,
        before: None,
        filter: Some(vs.FilterFailed),
      ),
    )
  let assert True =
    string.contains(req.path, "/file_batches/batch_1/files")
  let assert Some(qs) = req.query
  let assert True = string.contains(qs, "limit=10")
  let assert True = string.contains(qs, "order=asc")
  let assert True = string.contains(qs, "filter=failed")
}

// --- Filter encoding ---

pub fn filter_encoding_round_trips_test() {
  let comparison_json =
    json.to_string(
      vs.filter_to_json(
        vs.ComparisonFilter(vs.ComparisonFilterRecord(
          comparison_type: vs.GreaterThan,
          key: "score",
          value: dynamic.float(0.5),
        )),
      ),
    )
  let assert True = string.contains(comparison_json, "\"type\":\"gt\"")
  let assert True = string.contains(comparison_json, "\"key\":\"score\"")
  let assert True = string.contains(comparison_json, "\"value\":0.5")
}

pub fn filter_decoder_recognises_compound_test() {
  let body =
    "{\"type\":\"or\",\"filters\":[{\"type\":\"eq\",\"key\":\"a\",\"value\":\"x\"},{\"type\":\"in\",\"key\":\"b\",\"value\":[1,2]}]}"
  let assert Ok(filter) = json.parse(body, vs.filter_decoder())
  let assert vs.CompoundFilter(record) = filter
  assert record.compound_type == vs.Or
  assert list.length(record.filters) == 2
}

// --- API error ---

pub fn create_response_api_error_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid file_id\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":null}}"
  let resp = response.new(400) |> response.set_body(body)
  let assert Error(_) = vs.create_response(resp)
}
