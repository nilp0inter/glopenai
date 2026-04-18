import gleam/http/response
import glopenai/error
import glopenai/model

pub fn list_response_decodes_test() {
  let body =
    "{\"object\":\"list\",\"data\":[{\"id\":\"gpt-4o\",\"object\":\"model\",\"created\":1715367049,\"owned_by\":\"system\"}]}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = model.list_response(resp)
  assert result.object == "list"
  let assert [m] = result.data
  assert m.id == "gpt-4o"
  assert m.object == "model"
  assert m.created == 1_715_367_049
  assert m.owned_by == "system"
}

pub fn retrieve_response_decodes_test() {
  let body =
    "{\"id\":\"gpt-4o\",\"object\":\"model\",\"created\":1715367049,\"owned_by\":\"system\"}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = model.retrieve_response(resp)
  assert result.id == "gpt-4o"
}

pub fn delete_response_decodes_test() {
  let body = "{\"id\":\"ft-abc\",\"object\":\"model\",\"deleted\":true}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = model.delete_response(resp)
  assert result.id == "ft-abc"
  assert result.deleted == True
}

pub fn api_error_response_test() {
  let body =
    "{\"error\":{\"message\":\"Invalid API key\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":\"invalid_api_key\"}}"
  let resp = response.new(401) |> response.set_body(body)

  let assert Error(error.ApiResponseError(status, api_error)) =
    model.list_response(resp)
  assert status == 401
  assert api_error.message == "Invalid API key"
}

pub fn unexpected_response_test() {
  let resp = response.new(500) |> response.set_body("Internal Server Error")

  let assert Error(error.UnexpectedResponse(status, body)) =
    model.list_response(resp)
  assert status == 500
  assert body == "Internal Server Error"
}
