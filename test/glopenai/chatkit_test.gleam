import gleam/dict
import gleam/dynamic
import gleam/http
import gleam/http/response
import gleam/option.{None, Some}
import gleam/string
import glopenai/chatkit
import glopenai/config

// --- Sessions ---

pub fn session_create_request_minimal_test() {
  let cfg = config.new("test-key")
  let body =
    chatkit.new_create_chat_session_body(
      chatkit.new_workflow_param("wf_1"),
      "user_1",
    )
  let req = chatkit.session_create_request(cfg, body)
  assert req.method == http.Post
  let assert True = string.contains(req.path, "/chatkit/sessions")
  let assert True = string.contains(req.body, "\"workflow\":")
  let assert True = string.contains(req.body, "\"id\":\"wf_1\"")
  let assert True = string.contains(req.body, "\"user\":\"user_1\"")
}

pub fn session_create_request_with_options_test() {
  let cfg = config.new("test-key")
  let workflow =
    chatkit.new_workflow_param("wf_1")
    |> chatkit.workflow_param_with_version("v2")
    |> chatkit.workflow_param_with_state_variables(
      dict.from_list([#("locale", dynamic.string("en"))]),
    )
    |> chatkit.workflow_param_with_tracing(
      chatkit.WorkflowTracingParam(enabled: Some(False)),
    )
  let body =
    chatkit.new_create_chat_session_body(workflow, "user_1")
    |> chatkit.with_expires_after(chatkit.new_expires_after_param(900))
    |> chatkit.with_rate_limits(
      chatkit.RateLimitsParam(max_requests_per_1_minute: Some(30)),
    )
    |> chatkit.with_chatkit_configuration(chatkit.ChatkitConfigurationParam(
      automatic_thread_titling: Some(
        chatkit.AutomaticThreadTitlingParam(enabled: Some(True)),
      ),
      file_upload: Some(chatkit.FileUploadParam(
        enabled: Some(True),
        max_file_size: Some(50),
        max_files: Some(5),
      )),
      history: None,
    ))
  let req = chatkit.session_create_request(cfg, body)
  let assert True = string.contains(req.body, "\"version\":\"v2\"")
  let assert True = string.contains(req.body, "\"locale\":\"en\"")
  let assert True = string.contains(req.body, "\"enabled\":false")
  let assert True = string.contains(req.body, "\"anchor\":\"created_at\"")
  let assert True = string.contains(req.body, "\"seconds\":900")
  let assert True =
    string.contains(req.body, "\"max_requests_per_1_minute\":30")
  let assert True = string.contains(req.body, "\"max_file_size\":50")
}

pub fn session_create_response_decodes_test() {
  let body =
    "{\"id\":\"sess_1\",\"object\":\"chatkit.session\",\"expires_at\":1700001000,\"client_secret\":\"secret\",\"workflow\":{\"id\":\"wf_1\",\"tracing\":{\"enabled\":true}},\"user\":\"user_1\",\"rate_limits\":{\"max_requests_per_1_minute\":10},\"max_requests_per_1_minute\":10,\"status\":\"active\",\"chatkit_configuration\":{\"automatic_thread_titling\":{\"enabled\":true},\"file_upload\":{\"enabled\":false},\"history\":{\"enabled\":true}}}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(session) = chatkit.session_create_response(resp)
  assert session.id == "sess_1"
  assert session.client_secret == "secret"
  assert session.status == chatkit.SessionActive
  assert session.workflow.id == "wf_1"
  assert session.workflow.tracing.enabled == True
  assert session.chatkit_configuration.automatic_thread_titling.enabled == True
  assert session.chatkit_configuration.file_upload.enabled == False
  assert session.chatkit_configuration.history.recent_threads == None
}

pub fn session_cancel_request_builds_test() {
  let cfg = config.new("test-key")
  let req = chatkit.session_cancel_request(cfg, "sess_1")
  assert req.method == http.Post
  let assert True = string.contains(req.path, "/chatkit/sessions/sess_1/cancel")
  // Empty body for POST cancel
  assert req.body == "{}"
}

// --- Threads ---

pub fn thread_list_request_with_query_test() {
  let cfg = config.new("test-key")
  let req =
    chatkit.thread_list_request_with_query(
      cfg,
      chatkit.ListChatKitThreadsQuery(
        limit: Some(20),
        order: Some(chatkit.ThreadsDesc),
        after: Some("th_99"),
        before: None,
        user: Some("user_42"),
      ),
    )
  assert req.method == http.Get
  let assert True = string.contains(req.path, "/chatkit/threads")
  let assert Some(qs) = req.query
  let assert True = string.contains(qs, "limit=20")
  let assert True = string.contains(qs, "order=desc")
  let assert True = string.contains(qs, "after=th_99")
  let assert True = string.contains(qs, "user=user_42")
}

pub fn thread_list_response_decodes_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"id\":\"th_1\",\"object\":\"chatkit.thread\",\"created_at\":1700000000,\"title\":\"hi\",\"type\":\"active\",\"user\":\"user_1\"}],\"first_id\":\"th_1\",\"last_id\":\"th_1\",\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = chatkit.thread_list_response(resp)
  assert result.has_more == False
  let assert [thread] = result.data
  assert thread.id == "th_1"
  assert thread.title == Some("hi")
  assert thread.status == chatkit.ThreadActive
  assert thread.user == "user_1"
}

pub fn thread_retrieve_response_with_locked_status_test() {
  let body =
    "{\"id\":\"th_1\",\"object\":\"chatkit.thread\",\"created_at\":1,\"title\":null,\"type\":\"locked\",\"reason\":\"manual\",\"user\":\"user_1\"}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(thread) = chatkit.thread_retrieve_response(resp)
  assert thread.title == None
  let assert chatkit.ThreadLocked(reason) = thread.status
  assert reason == Some("manual")
}

pub fn thread_retrieve_response_with_closed_no_reason_test() {
  let body =
    "{\"id\":\"th_2\",\"object\":\"chatkit.thread\",\"created_at\":1,\"title\":null,\"type\":\"closed\",\"user\":\"user_1\"}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(thread) = chatkit.thread_retrieve_response(resp)
  let assert chatkit.ThreadClosed(reason) = thread.status
  assert reason == None
}

pub fn thread_delete_request_builds_test() {
  let cfg = config.new("test-key")
  let req = chatkit.thread_delete_request(cfg, "th_42")
  assert req.method == http.Delete
  let assert True = string.contains(req.path, "/chatkit/threads/th_42")
}

pub fn thread_delete_response_decodes_test() {
  let body =
    "{\"id\":\"th_42\",\"object\":\"chatkit.thread.deleted\",\"deleted\":true}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = chatkit.thread_delete_response(resp)
  assert result.id == "th_42"
  assert result.deleted == True
}

// --- Thread items ---

pub fn thread_items_list_user_message_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"type\":\"chatkit.user_message\",\"id\":\"item_1\",\"object\":\"chatkit.thread_item\",\"created_at\":1,\"thread_id\":\"th_1\",\"content\":[{\"type\":\"input_text\",\"text\":\"hello\"},{\"type\":\"quoted_text\",\"text\":\"prior\"}],\"attachments\":[]}],\"first_id\":\"item_1\",\"last_id\":\"item_1\",\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = chatkit.thread_items_list_response(resp)
  let assert [item] = result.data
  let assert chatkit.UserMessageItem(_, _, _, _, content, _, _) = item
  let assert [first, second] = content
  assert first == chatkit.InputTextContent("hello")
  assert second == chatkit.QuotedTextContent("prior")
}

pub fn thread_items_list_assistant_message_with_annotations_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"type\":\"chatkit.assistant_message\",\"id\":\"item_2\",\"object\":\"chatkit.thread_item\",\"created_at\":1,\"thread_id\":\"th_1\",\"content\":[{\"type\":\"output_text\",\"text\":\"see [doc]\",\"annotations\":[{\"type\":\"file\",\"source\":{\"type\":\"file\",\"filename\":\"doc.pdf\"}},{\"type\":\"url\",\"source\":{\"type\":\"url\",\"url\":\"https://example.com\"}}]}]}],\"first_id\":null,\"last_id\":null,\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = chatkit.thread_items_list_response(resp)
  let assert [chatkit.AssistantMessageItem(_, _, _, _, content)] = result.data
  let assert [output] = content
  assert output.text == "see [doc]"
  let assert [chatkit.FileAnnotation(file_src), chatkit.UrlAnnotation(url_src)] =
    output.annotations
  assert file_src.filename == "doc.pdf"
  assert url_src.url == "https://example.com"
}

pub fn thread_items_list_widget_and_tool_call_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"type\":\"chatkit.widget\",\"id\":\"item_3\",\"object\":\"chatkit.thread_item\",\"created_at\":1,\"thread_id\":\"th_1\",\"widget\":\"<json>\"},{\"type\":\"chatkit.client_tool_call\",\"id\":\"item_4\",\"object\":\"chatkit.thread_item\",\"created_at\":2,\"thread_id\":\"th_1\",\"status\":\"completed\",\"call_id\":\"call_1\",\"name\":\"do\",\"arguments\":\"{}\",\"output\":\"ok\"}],\"first_id\":null,\"last_id\":null,\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = chatkit.thread_items_list_response(resp)
  let assert [widget, tool] = result.data
  let assert chatkit.WidgetMessageItem(_, _, _, _, w) = widget
  assert w == "<json>"
  let assert chatkit.ClientToolCallItem(_, _, _, _, status, _, _, _, output) =
    tool
  assert status == chatkit.ClientToolCompleted
  assert output == Some("ok")
}

pub fn thread_items_list_task_and_task_group_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"type\":\"chatkit.task\",\"id\":\"item_5\",\"object\":\"chatkit.thread_item\",\"created_at\":1,\"thread_id\":\"th_1\",\"task_type\":\"thought\",\"heading\":\"thinking\",\"summary\":null},{\"type\":\"chatkit.task_group\",\"id\":\"item_6\",\"object\":\"chatkit.thread_item\",\"created_at\":2,\"thread_id\":\"th_1\",\"tasks\":[{\"task_type\":\"custom\",\"heading\":\"step\",\"summary\":null}]}],\"first_id\":null,\"last_id\":null,\"has_more\":false}"
  let resp = response.new(200) |> response.set_body(body)
  let assert Ok(result) = chatkit.thread_items_list_response(resp)
  let assert [task, group] = result.data
  let assert chatkit.TaskItem(_, _, _, _, task_type, heading, _) = task
  assert task_type == chatkit.TaskThought
  assert heading == Some("thinking")
  let assert chatkit.TaskGroupItem(_, _, _, _, tasks) = group
  let assert [first] = tasks
  assert first.task_type == chatkit.TaskCustom
  assert first.heading == Some("step")
}

pub fn thread_items_list_request_with_query_test() {
  let cfg = config.new("test-key")
  let req =
    chatkit.thread_items_list_request_with_query(
      cfg,
      "th_1",
      chatkit.ListChatKitThreadItemsQuery(
        limit: Some(5),
        order: Some(chatkit.ItemsAsc),
        after: None,
        before: None,
      ),
    )
  let assert True = string.contains(req.path, "/chatkit/threads/th_1/items")
  let assert Some(qs) = req.query
  let assert True = string.contains(qs, "limit=5")
  let assert True = string.contains(qs, "order=asc")
}

// --- API error ---

pub fn session_create_response_api_error_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid workflow id\",\"type\":\"invalid_request_error\",\"param\":\"workflow.id\",\"code\":null}}"
  let resp = response.new(400) |> response.set_body(body)
  let assert Error(_) = chatkit.session_create_response(resp)
}
