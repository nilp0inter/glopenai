import gleam/http
import gleam/http/response
import gleam/json
import gleam/option.{Some}
import gleam/string
import glopenai/config
import glopenai/error
import glopenai/fine_tuning

pub fn request_encoding_test() {
  let request =
    fine_tuning.new_create_request(
      model: "gpt-4o-mini-2024-07-18",
      training_file: "file-abc",
    )
    |> fine_tuning.with_suffix("my-model")

  let encoded =
    fine_tuning.create_fine_tuning_job_request_to_json(request)
    |> json.to_string

  let assert True =
    string.contains(encoded, "\"model\":\"gpt-4o-mini-2024-07-18\"")
  let assert True = string.contains(encoded, "\"training_file\":\"file-abc\"")
  let assert True = string.contains(encoded, "\"suffix\":\"my-model\"")
}

pub fn request_building_test() {
  let cfg = config.new("test-key")
  let request =
    fine_tuning.new_create_request(
      model: "gpt-4o-mini-2024-07-18",
      training_file: "file-abc",
    )
  let http_req = fine_tuning.create_request(cfg, request)

  assert http_req.method == http.Post
  let assert True = string.contains(http_req.path, "/fine_tuning/jobs")
}

pub fn retrieve_request_building_test() {
  let cfg = config.new("test-key")
  let http_req = fine_tuning.retrieve_request(cfg, "ftjob-abc")

  assert http_req.method == http.Get
  let assert True =
    string.contains(http_req.path, "/fine_tuning/jobs/ftjob-abc")
}

pub fn cancel_request_building_test() {
  let cfg = config.new("test-key")
  let http_req = fine_tuning.cancel_request(cfg, "ftjob-abc")

  assert http_req.method == http.Post
  let assert True =
    string.contains(http_req.path, "/fine_tuning/jobs/ftjob-abc/cancel")
}

pub fn job_response_decoding_test() {
  let body =
    "{\"id\":\"ftjob-abc\",\"created_at\":1700000000,\"error\":null,\"fine_tuned_model\":null,\"finished_at\":null,\"hyperparameters\":{\"batch_size\":\"auto\",\"learning_rate_multiplier\":\"auto\",\"n_epochs\":\"auto\"},\"model\":\"gpt-4o-mini-2024-07-18\",\"object\":\"fine_tuning.job\",\"organization_id\":\"org-123\",\"result_files\":[],\"status\":\"queued\",\"trained_tokens\":null,\"training_file\":\"file-abc\",\"validation_file\":null,\"seed\":42}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = fine_tuning.create_response(resp)
  assert result.id == "ftjob-abc"
  assert result.model == "gpt-4o-mini-2024-07-18"
  assert result.status == fine_tuning.Queued
  assert result.seed == 42
  assert result.hyperparameters.batch_size == fine_tuning.BatchSizeAuto
  assert result.hyperparameters.n_epochs == fine_tuning.NEpochsAuto
}

pub fn job_with_method_decoding_test() {
  let body =
    "{\"id\":\"ftjob-abc\",\"created_at\":1700000000,\"error\":null,\"fine_tuned_model\":\"ft:gpt-4o-mini:org:suffix:id\",\"finished_at\":1700001000,\"hyperparameters\":{\"batch_size\":4,\"learning_rate_multiplier\":1.5,\"n_epochs\":3},\"model\":\"gpt-4o-mini-2024-07-18\",\"object\":\"fine_tuning.job\",\"organization_id\":\"org-123\",\"result_files\":[\"file-result\"],\"status\":\"succeeded\",\"trained_tokens\":5000,\"training_file\":\"file-abc\",\"validation_file\":\"file-val\",\"seed\":42,\"method\":{\"type\":\"supervised\",\"supervised\":{\"hyperparameters\":{\"batch_size\":\"auto\",\"learning_rate_multiplier\":\"auto\",\"n_epochs\":\"auto\"}}}}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = fine_tuning.create_response(resp)
  assert result.status == fine_tuning.Succeeded
  assert result.fine_tuned_model == Some("ft:gpt-4o-mini:org:suffix:id")
  assert result.trained_tokens == Some(5000)
  assert result.hyperparameters.batch_size == fine_tuning.BatchSize(4)
  assert result.hyperparameters.n_epochs == fine_tuning.NEpochs(3)
  let assert Some(fine_tuning.Supervised(method)) = result.method
  assert method.hyperparameters.batch_size == fine_tuning.BatchSizeAuto
}

pub fn list_jobs_response_decoding_test() {
  let body =
    "{\"data\":[{\"id\":\"ftjob-1\",\"created_at\":1700000000,\"error\":null,\"fine_tuned_model\":null,\"finished_at\":null,\"hyperparameters\":{\"batch_size\":\"auto\",\"learning_rate_multiplier\":\"auto\",\"n_epochs\":\"auto\"},\"model\":\"gpt-4o-mini\",\"object\":\"fine_tuning.job\",\"organization_id\":\"org-1\",\"result_files\":[],\"status\":\"running\",\"trained_tokens\":null,\"training_file\":\"file-1\",\"validation_file\":null,\"seed\":1}],\"has_more\":true,\"object\":\"list\"}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = fine_tuning.list_response(resp)
  assert result.has_more == True
  let assert [job] = result.data
  assert job.id == "ftjob-1"
  assert job.status == fine_tuning.Running
}

pub fn events_response_decoding_test() {
  let body =
    "{\"data\":[{\"id\":\"fte-abc\",\"created_at\":1700000000,\"level\":\"info\",\"message\":\"Job started\",\"object\":\"fine_tuning.job.event\"}],\"object\":\"list\"}"
  let resp = response.new(200) |> response.set_body(body)

  let assert Ok(result) = fine_tuning.list_events_response(resp)
  let assert [event] = result.data
  assert event.id == "fte-abc"
  assert event.level == fine_tuning.LevelInfo
  assert event.message == "Job started"
}

pub fn api_error_response_test() {
  let body =
    "{\"error\":{\"message\":\"Not found\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":\"not_found\"}}"
  let resp = response.new(404) |> response.set_body(body)

  let assert Error(error.ApiResponseError(status, _)) =
    fine_tuning.create_response(resp)
  assert status == 404
}

pub fn method_encoding_test() {
  let method =
    fine_tuning.Supervised(
      supervised: fine_tuning.FineTuneSupervisedMethod(
        hyperparameters: fine_tuning.FineTuneSupervisedHyperparameters(
          batch_size: fine_tuning.BatchSize(8),
          learning_rate_multiplier: fine_tuning.LearningRateMultiplierAuto,
          n_epochs: fine_tuning.NEpochs(3),
        ),
      ),
    )

  let encoded = fine_tuning.fine_tune_method_to_json(method) |> json.to_string

  let assert True = string.contains(encoded, "\"type\":\"supervised\"")
  let assert True = string.contains(encoded, "\"batch_size\":8")
  let assert True = string.contains(encoded, "\"n_epochs\":3")
}

pub fn checkpoint_permission_request_test() {
  let cfg = config.new("test-key")
  let http_req =
    fine_tuning.delete_checkpoint_permission_request(
      cfg,
      "ft:checkpoint:123",
      "perm-abc",
    )

  assert http_req.method == http.Delete
  let assert True =
    string.contains(
      http_req.path,
      "/fine_tuning/checkpoints/ft:checkpoint:123/permissions/perm-abc",
    )
}
