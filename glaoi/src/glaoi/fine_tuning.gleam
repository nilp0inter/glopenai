/// Fine-tuning API: create, list, retrieve, cancel, pause, resume fine-tuning
/// jobs, and manage events, checkpoints, and checkpoint permissions.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glaoi/config.{type Config}
import glaoi/error.{type GlaoiError}
import glaoi/internal
import glaoi/internal/codec
import glaoi/shared.{type ReasoningEffort}

// ============================================================================
// Hyperparameter "auto or value" enums
// ============================================================================

/// Number of epochs: auto or a specific count.
pub type NEpochs {
  NEpochsAuto
  NEpochs(Int)
}

/// Batch size: auto or a specific size.
pub type BatchSize {
  BatchSizeAuto
  BatchSize(Int)
}

/// Learning rate multiplier: auto or a specific value.
pub type LearningRateMultiplier {
  LearningRateMultiplierAuto
  LearningRateMultiplier(Float)
}

/// Beta parameter for DPO: auto or a specific value.
pub type Beta {
  BetaAuto
  Beta(Float)
}

/// Compute multiplier for reinforcement: auto or a specific value.
pub type ComputeMultiplier {
  ComputeMultiplierAuto
  ComputeMultiplier(Float)
}

/// Evaluation interval: auto or a specific count.
pub type EvalInterval {
  EvalIntervalAuto
  EvalInterval(Int)
}

/// Evaluation samples: auto or a specific count.
pub type EvalSamples {
  EvalSamplesAuto
  EvalSamples(Int)
}

/// Reasoning effort level for reinforcement fine-tuning.
pub type FineTuneReasoningEffort {
  FineTuneReasoningDefault
  FineTuneReasoningLow
  FineTuneReasoningMedium
  FineTuneReasoningHigh
}

// ============================================================================
// Hyperparameter structs
// ============================================================================

pub type FineTuneSupervisedHyperparameters {
  FineTuneSupervisedHyperparameters(
    batch_size: BatchSize,
    learning_rate_multiplier: LearningRateMultiplier,
    n_epochs: NEpochs,
  )
}

pub type FineTuneDpoHyperparameters {
  FineTuneDpoHyperparameters(
    beta: Beta,
    batch_size: BatchSize,
    learning_rate_multiplier: LearningRateMultiplier,
    n_epochs: NEpochs,
  )
}

pub type FineTuneReinforcementHyperparameters {
  FineTuneReinforcementHyperparameters(
    batch_size: BatchSize,
    learning_rate_multiplier: LearningRateMultiplier,
    n_epochs: NEpochs,
    reasoning_effort: FineTuneReasoningEffort,
    compute_multiplier: ComputeMultiplier,
    eval_interval: EvalInterval,
    eval_samples: EvalSamples,
  )
}

/// Hyperparameters as returned in a FineTuningJob response.
pub type Hyperparameters {
  Hyperparameters(
    batch_size: BatchSize,
    learning_rate_multiplier: LearningRateMultiplier,
    n_epochs: NEpochs,
  )
}

// ============================================================================
// Grader types (used in reinforcement learning fine-tuning)
// ============================================================================

pub type GraderStringCheckOperation {
  GraderOpEq
  GraderOpNe
  GraderOpLike
  GraderOpIlike
}

pub type GraderStringCheck {
  GraderStringCheck(
    name: String,
    input: String,
    reference: String,
    operation: GraderStringCheckOperation,
  )
}

pub type GraderTextSimilarityMetric {
  MetricCosine
  MetricFuzzyMatch
  MetricBleu
  MetricGleu
  MetricMeteor
  MetricRouge1
  MetricRouge2
  MetricRouge3
  MetricRouge4
  MetricRouge5
  MetricRougeL
}

pub type GraderTextSimilarity {
  GraderTextSimilarity(
    name: String,
    input: String,
    reference: String,
    evaluation_metric: GraderTextSimilarityMetric,
  )
}

pub type GraderPython {
  GraderPython(
    name: String,
    source: String,
    image_tag: Option(String),
  )
}

pub type GraderScoreModelSamplingParams {
  GraderScoreModelSamplingParams(
    seed: Option(Int),
    top_p: Option(Float),
    temperature: Option(Float),
    max_completion_tokens: Option(Int),
    reasoning_effort: Option(ReasoningEffort),
  )
}

/// An eval item used as input to score model graders.
pub type EvalItem {
  EvalItem(role: String, content: String)
}

pub type GraderScoreModel {
  GraderScoreModel(
    name: String,
    model: String,
    input: List(EvalItem),
    sampling_params: Option(GraderScoreModelSamplingParams),
    range: Option(List(Float)),
  )
}

/// Graders used in reinforcement fine-tuning methods.
/// Tagged by "type" field.
pub type FineTuneGrader {
  StringCheckGrader(GraderStringCheck)
  TextSimilarityGrader(GraderTextSimilarity)
  PythonGrader(GraderPython)
  ScoreModelGrader(GraderScoreModel)
  MultiGrader(name: String, graders: dynamic.Dynamic, calculate_output: String)
}

// ============================================================================
// Fine-tuning method types
// ============================================================================

pub type FineTuneSupervisedMethod {
  FineTuneSupervisedMethod(
    hyperparameters: FineTuneSupervisedHyperparameters,
  )
}

pub type FineTuneDpoMethod {
  FineTuneDpoMethod(hyperparameters: FineTuneDpoHyperparameters)
}

pub type FineTuneReinforcementMethod {
  FineTuneReinforcementMethod(
    grader: FineTuneGrader,
    hyperparameters: FineTuneReinforcementHyperparameters,
  )
}

/// The fine-tuning method to use. Tagged by "type" field.
pub type FineTuneMethod {
  Supervised(supervised: FineTuneSupervisedMethod)
  Dpo(dpo: FineTuneDpoMethod)
  Reinforcement(reinforcement: FineTuneReinforcementMethod)
}

// ============================================================================
// Integration types (Weights & Biases)
// ============================================================================

pub type WandB {
  WandB(
    project: String,
    name: Option(String),
    entity: Option(String),
    tags: Option(List(String)),
  )
}

pub type FineTuningIntegration {
  FineTuningIntegration(wandb: WandB)
}

// ============================================================================
// Job types
// ============================================================================

pub type FineTuningJobStatus {
  ValidatingFiles
  Queued
  Running
  Succeeded
  JobFailed
  JobCancelled
}

pub type FineTuneJobError {
  FineTuneJobError(
    code: String,
    message: String,
    param: Option(String),
  )
}

pub type FineTuningJob {
  FineTuningJob(
    id: String,
    created_at: Int,
    error: Option(FineTuneJobError),
    fine_tuned_model: Option(String),
    finished_at: Option(Int),
    hyperparameters: Hyperparameters,
    model: String,
    object: String,
    organization_id: String,
    result_files: List(String),
    status: FineTuningJobStatus,
    trained_tokens: Option(Int),
    training_file: String,
    validation_file: Option(String),
    integrations: Option(List(FineTuningIntegration)),
    seed: Int,
    estimated_finish: Option(Int),
    method: Option(FineTuneMethod),
    metadata: Option(dynamic.Dynamic),
  )
}

// ============================================================================
// Request type
// ============================================================================

pub type CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(
    model: String,
    training_file: String,
    suffix: Option(String),
    validation_file: Option(String),
    integrations: Option(List(FineTuningIntegration)),
    seed: Option(Int),
    method: Option(FineTuneMethod),
    metadata: Option(dynamic.Dynamic),
  )
}

// ============================================================================
// Event types
// ============================================================================

pub type EventLevel {
  LevelInfo
  LevelWarn
  LevelError
}

pub type FineTuningJobEventType {
  EventMessage
  EventMetrics
}

pub type FineTuningJobEvent {
  FineTuningJobEvent(
    id: String,
    created_at: Int,
    level: EventLevel,
    message: String,
    object: String,
    event_type: Option(FineTuningJobEventType),
    data: Option(dynamic.Dynamic),
  )
}

// ============================================================================
// Checkpoint types
// ============================================================================

pub type FineTuningJobCheckpointMetrics {
  FineTuningJobCheckpointMetrics(
    step: Int,
    train_loss: Float,
    train_mean_token_accuracy: Float,
    valid_loss: Float,
    valid_mean_token_accuracy: Float,
    full_valid_loss: Float,
    full_valid_mean_token_accuracy: Float,
  )
}

pub type FineTuningJobCheckpoint {
  FineTuningJobCheckpoint(
    id: String,
    created_at: Int,
    fine_tuned_model_checkpoint: String,
    step_number: Int,
    metrics: FineTuningJobCheckpointMetrics,
    fine_tuning_job_id: String,
    object: String,
  )
}

// ============================================================================
// Checkpoint permission types
// ============================================================================

pub type FineTuningCheckpointPermission {
  FineTuningCheckpointPermission(
    id: String,
    created_at: Int,
    project_id: String,
    object: String,
  )
}

pub type CreateFineTuningCheckpointPermissionRequest {
  CreateFineTuningCheckpointPermissionRequest(project_ids: List(String))
}

pub type DeleteFineTuningCheckpointPermissionResponse {
  DeleteFineTuningCheckpointPermissionResponse(
    object: String,
    id: String,
    deleted: Bool,
  )
}

// ============================================================================
// Response types
// ============================================================================

pub type ListPaginatedFineTuningJobsResponse {
  ListPaginatedFineTuningJobsResponse(
    data: List(FineTuningJob),
    has_more: Bool,
    object: String,
  )
}

pub type ListFineTuningJobEventsResponse {
  ListFineTuningJobEventsResponse(
    data: List(FineTuningJobEvent),
    object: String,
  )
}

pub type ListFineTuningJobCheckpointsResponse {
  ListFineTuningJobCheckpointsResponse(
    data: List(FineTuningJobCheckpoint),
    object: String,
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

pub type ListFineTuningCheckpointPermissionResponse {
  ListFineTuningCheckpointPermissionResponse(
    data: List(FineTuningCheckpointPermission),
    object: String,
    first_id: Option(String),
    last_id: Option(String),
    has_more: Bool,
  )
}

// ============================================================================
// Request builder
// ============================================================================

/// Create a new fine-tuning job request with required fields.
pub fn new_create_request(
  model model: String,
  training_file training_file: String,
) -> CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(
    model: model,
    training_file: training_file,
    suffix: None,
    validation_file: None,
    integrations: None,
    seed: None,
    method: None,
    metadata: None,
  )
}

pub fn with_suffix(
  request: CreateFineTuningJobRequest,
  suffix: String,
) -> CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(..request, suffix: Some(suffix))
}

pub fn with_validation_file(
  request: CreateFineTuningJobRequest,
  validation_file: String,
) -> CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(
    ..request,
    validation_file: Some(validation_file),
  )
}

pub fn with_integrations(
  request: CreateFineTuningJobRequest,
  integrations: List(FineTuningIntegration),
) -> CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(..request, integrations: Some(integrations))
}

pub fn with_seed(
  request: CreateFineTuningJobRequest,
  seed: Int,
) -> CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(..request, seed: Some(seed))
}

pub fn with_method(
  request: CreateFineTuningJobRequest,
  method: FineTuneMethod,
) -> CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(..request, method: Some(method))
}

pub fn with_metadata(
  request: CreateFineTuningJobRequest,
  metadata: dynamic.Dynamic,
) -> CreateFineTuningJobRequest {
  CreateFineTuningJobRequest(..request, metadata: Some(metadata))
}

// ============================================================================
// Encoders
// ============================================================================

pub fn n_epochs_to_json(value: NEpochs) -> json.Json {
  case value {
    NEpochsAuto -> json.string("auto")
    NEpochs(n) -> json.int(n)
  }
}

pub fn batch_size_to_json(value: BatchSize) -> json.Json {
  case value {
    BatchSizeAuto -> json.string("auto")
    BatchSize(n) -> json.int(n)
  }
}

pub fn learning_rate_multiplier_to_json(
  value: LearningRateMultiplier,
) -> json.Json {
  case value {
    LearningRateMultiplierAuto -> json.string("auto")
    LearningRateMultiplier(f) -> json.float(f)
  }
}

pub fn beta_to_json(value: Beta) -> json.Json {
  case value {
    BetaAuto -> json.string("auto")
    Beta(f) -> json.float(f)
  }
}

pub fn compute_multiplier_to_json(value: ComputeMultiplier) -> json.Json {
  case value {
    ComputeMultiplierAuto -> json.string("auto")
    ComputeMultiplier(f) -> json.float(f)
  }
}

pub fn eval_interval_to_json(value: EvalInterval) -> json.Json {
  case value {
    EvalIntervalAuto -> json.string("auto")
    EvalInterval(n) -> json.int(n)
  }
}

pub fn eval_samples_to_json(value: EvalSamples) -> json.Json {
  case value {
    EvalSamplesAuto -> json.string("auto")
    EvalSamples(n) -> json.int(n)
  }
}

pub fn fine_tune_reasoning_effort_to_json(
  value: FineTuneReasoningEffort,
) -> json.Json {
  json.string(case value {
    FineTuneReasoningDefault -> "default"
    FineTuneReasoningLow -> "low"
    FineTuneReasoningMedium -> "medium"
    FineTuneReasoningHigh -> "high"
  })
}

pub fn supervised_hyperparameters_to_json(
  hp: FineTuneSupervisedHyperparameters,
) -> json.Json {
  json.object([
    #("batch_size", batch_size_to_json(hp.batch_size)),
    #(
      "learning_rate_multiplier",
      learning_rate_multiplier_to_json(hp.learning_rate_multiplier),
    ),
    #("n_epochs", n_epochs_to_json(hp.n_epochs)),
  ])
}

pub fn dpo_hyperparameters_to_json(
  hp: FineTuneDpoHyperparameters,
) -> json.Json {
  json.object([
    #("beta", beta_to_json(hp.beta)),
    #("batch_size", batch_size_to_json(hp.batch_size)),
    #(
      "learning_rate_multiplier",
      learning_rate_multiplier_to_json(hp.learning_rate_multiplier),
    ),
    #("n_epochs", n_epochs_to_json(hp.n_epochs)),
  ])
}

pub fn reinforcement_hyperparameters_to_json(
  hp: FineTuneReinforcementHyperparameters,
) -> json.Json {
  json.object([
    #("batch_size", batch_size_to_json(hp.batch_size)),
    #(
      "learning_rate_multiplier",
      learning_rate_multiplier_to_json(hp.learning_rate_multiplier),
    ),
    #("n_epochs", n_epochs_to_json(hp.n_epochs)),
    #(
      "reasoning_effort",
      fine_tune_reasoning_effort_to_json(hp.reasoning_effort),
    ),
    #(
      "compute_multiplier",
      compute_multiplier_to_json(hp.compute_multiplier),
    ),
    #("eval_interval", eval_interval_to_json(hp.eval_interval)),
    #("eval_samples", eval_samples_to_json(hp.eval_samples)),
  ])
}

pub fn hyperparameters_to_json(hp: Hyperparameters) -> json.Json {
  json.object([
    #("batch_size", batch_size_to_json(hp.batch_size)),
    #(
      "learning_rate_multiplier",
      learning_rate_multiplier_to_json(hp.learning_rate_multiplier),
    ),
    #("n_epochs", n_epochs_to_json(hp.n_epochs)),
  ])
}

pub fn grader_string_check_operation_to_json(
  op: GraderStringCheckOperation,
) -> json.Json {
  json.string(case op {
    GraderOpEq -> "eq"
    GraderOpNe -> "ne"
    GraderOpLike -> "like"
    GraderOpIlike -> "ilike"
  })
}

pub fn grader_text_similarity_metric_to_json(
  metric: GraderTextSimilarityMetric,
) -> json.Json {
  json.string(case metric {
    MetricCosine -> "cosine"
    MetricFuzzyMatch -> "fuzzy_match"
    MetricBleu -> "bleu"
    MetricGleu -> "gleu"
    MetricMeteor -> "meteor"
    MetricRouge1 -> "rouge_1"
    MetricRouge2 -> "rouge_2"
    MetricRouge3 -> "rouge_3"
    MetricRouge4 -> "rouge_4"
    MetricRouge5 -> "rouge_5"
    MetricRougeL -> "rouge_l"
  })
}

pub fn eval_item_to_json(item: EvalItem) -> json.Json {
  json.object([
    #("role", json.string(item.role)),
    #("content", json.string(item.content)),
  ])
}

pub fn grader_score_model_sampling_params_to_json(
  params: GraderScoreModelSamplingParams,
) -> json.Json {
  codec.object_with_optional([], [
    codec.optional_field("seed", params.seed, json.int),
    codec.optional_field("top_p", params.top_p, json.float),
    codec.optional_field("temperature", params.temperature, json.float),
    codec.optional_field(
      "max_completion_tokens",
      params.max_completion_tokens,
      json.int,
    ),
    codec.optional_field(
      "reasoning_effort",
      params.reasoning_effort,
      shared.reasoning_effort_to_json,
    ),
  ])
}

pub fn fine_tune_grader_to_json(grader: FineTuneGrader) -> json.Json {
  case grader {
    StringCheckGrader(g) ->
      json.object([
        #("type", json.string("string_check")),
        #("name", json.string(g.name)),
        #("input", json.string(g.input)),
        #("reference", json.string(g.reference)),
        #("operation", grader_string_check_operation_to_json(g.operation)),
      ])
    TextSimilarityGrader(g) ->
      json.object([
        #("type", json.string("text_similarity")),
        #("name", json.string(g.name)),
        #("input", json.string(g.input)),
        #("reference", json.string(g.reference)),
        #(
          "evaluation_metric",
          grader_text_similarity_metric_to_json(g.evaluation_metric),
        ),
      ])
    PythonGrader(g) ->
      codec.object_with_optional(
        [
          #("type", json.string("python")),
          #("name", json.string(g.name)),
          #("source", json.string(g.source)),
        ],
        [codec.optional_field("image_tag", g.image_tag, json.string)],
      )
    ScoreModelGrader(g) ->
      codec.object_with_optional(
        [
          #("type", json.string("score_model")),
          #("name", json.string(g.name)),
          #("model", json.string(g.model)),
          #("input", json.array(g.input, eval_item_to_json)),
        ],
        [
          codec.optional_field(
            "sampling_params",
            g.sampling_params,
            grader_score_model_sampling_params_to_json,
          ),
          codec.optional_field("range", g.range, fn(r) {
            json.array(r, json.float)
          }),
        ],
      )
    MultiGrader(name, graders, calculate_output) ->
      json.object([
        #("type", json.string("multi")),
        #("name", json.string(name)),
        #("graders", codec.dynamic_to_json(graders)),
        #("calculate_output", json.string(calculate_output)),
      ])
  }
}

pub fn fine_tune_method_to_json(method: FineTuneMethod) -> json.Json {
  case method {
    Supervised(supervised) ->
      json.object([
        #("type", json.string("supervised")),
        #(
          "supervised",
          json.object([
            #(
              "hyperparameters",
              supervised_hyperparameters_to_json(
                supervised.hyperparameters,
              ),
            ),
          ]),
        ),
      ])
    Dpo(dpo) ->
      json.object([
        #("type", json.string("dpo")),
        #(
          "dpo",
          json.object([
            #(
              "hyperparameters",
              dpo_hyperparameters_to_json(dpo.hyperparameters),
            ),
          ]),
        ),
      ])
    Reinforcement(reinforcement) ->
      json.object([
        #("type", json.string("reinforcement")),
        #(
          "reinforcement",
          json.object([
            #("grader", fine_tune_grader_to_json(reinforcement.grader)),
            #(
              "hyperparameters",
              reinforcement_hyperparameters_to_json(
                reinforcement.hyperparameters,
              ),
            ),
          ]),
        ),
      ])
  }
}

pub fn wandb_to_json(wandb: WandB) -> json.Json {
  codec.object_with_optional(
    [#("project", json.string(wandb.project))],
    [
      codec.optional_field("name", wandb.name, json.string),
      codec.optional_field("entity", wandb.entity, json.string),
      codec.optional_field("tags", wandb.tags, fn(t) {
        json.array(t, json.string)
      }),
    ],
  )
}

pub fn fine_tuning_integration_to_json(
  integration: FineTuningIntegration,
) -> json.Json {
  json.object([
    #("type", json.string("wandb")),
    #("wandb", wandb_to_json(integration.wandb)),
  ])
}

pub fn fine_tuning_job_status_to_json(
  status: FineTuningJobStatus,
) -> json.Json {
  json.string(case status {
    ValidatingFiles -> "validating_files"
    Queued -> "queued"
    Running -> "running"
    Succeeded -> "succeeded"
    JobFailed -> "failed"
    JobCancelled -> "cancelled"
  })
}

pub fn event_level_to_json(level: EventLevel) -> json.Json {
  json.string(case level {
    LevelInfo -> "info"
    LevelWarn -> "warn"
    LevelError -> "error"
  })
}

pub fn create_fine_tuning_job_request_to_json(
  request: CreateFineTuningJobRequest,
) -> json.Json {
  codec.object_with_optional(
    [
      #("model", json.string(request.model)),
      #("training_file", json.string(request.training_file)),
    ],
    [
      codec.optional_field("suffix", request.suffix, json.string),
      codec.optional_field(
        "validation_file",
        request.validation_file,
        json.string,
      ),
      codec.optional_field("integrations", request.integrations, fn(i) {
        json.array(i, fine_tuning_integration_to_json)
      }),
      codec.optional_field("seed", request.seed, json.int),
      codec.optional_field("method", request.method, fine_tune_method_to_json),
      codec.optional_field(
        "metadata",
        request.metadata,
        codec.dynamic_to_json,
      ),
    ],
  )
}

pub fn create_checkpoint_permission_request_to_json(
  request: CreateFineTuningCheckpointPermissionRequest,
) -> json.Json {
  json.object([
    #("project_ids", json.array(request.project_ids, json.string)),
  ])
}

// ============================================================================
// Decoders
// ============================================================================

pub fn n_epochs_decoder() -> decode.Decoder(NEpochs) {
  decode.one_of(decode.string |> decode.then(fn(s) {
    case s {
      "auto" -> decode.success(NEpochsAuto)
      _ -> decode.failure(NEpochsAuto, "NEpochs")
    }
  }), [decode.int |> decode.then(fn(n) { decode.success(NEpochs(n)) })],
  )
}

pub fn batch_size_decoder() -> decode.Decoder(BatchSize) {
  decode.one_of(decode.string |> decode.then(fn(s) {
    case s {
      "auto" -> decode.success(BatchSizeAuto)
      _ -> decode.failure(BatchSizeAuto, "BatchSize")
    }
  }), [decode.int |> decode.then(fn(n) { decode.success(BatchSize(n)) })],
  )
}

pub fn learning_rate_multiplier_decoder() -> decode.Decoder(
  LearningRateMultiplier,
) {
  decode.one_of(decode.string |> decode.then(fn(s) {
    case s {
      "auto" -> decode.success(LearningRateMultiplierAuto)
      _ -> decode.failure(LearningRateMultiplierAuto, "LearningRateMultiplier")
    }
  }), [
    decode.float
    |> decode.then(fn(f) {
      decode.success(LearningRateMultiplier(f))
    }),
  ])
}

pub fn beta_decoder() -> decode.Decoder(Beta) {
  decode.one_of(decode.string |> decode.then(fn(s) {
    case s {
      "auto" -> decode.success(BetaAuto)
      _ -> decode.failure(BetaAuto, "Beta")
    }
  }), [decode.float |> decode.then(fn(f) { decode.success(Beta(f)) })],
  )
}

pub fn compute_multiplier_decoder() -> decode.Decoder(ComputeMultiplier) {
  decode.one_of(decode.string |> decode.then(fn(s) {
    case s {
      "auto" -> decode.success(ComputeMultiplierAuto)
      _ -> decode.failure(ComputeMultiplierAuto, "ComputeMultiplier")
    }
  }), [
    decode.float
    |> decode.then(fn(f) { decode.success(ComputeMultiplier(f)) }),
  ])
}

pub fn eval_interval_decoder() -> decode.Decoder(EvalInterval) {
  decode.one_of(decode.string |> decode.then(fn(s) {
    case s {
      "auto" -> decode.success(EvalIntervalAuto)
      _ -> decode.failure(EvalIntervalAuto, "EvalInterval")
    }
  }), [
    decode.int |> decode.then(fn(n) { decode.success(EvalInterval(n)) }),
  ])
}

pub fn eval_samples_decoder() -> decode.Decoder(EvalSamples) {
  decode.one_of(decode.string |> decode.then(fn(s) {
    case s {
      "auto" -> decode.success(EvalSamplesAuto)
      _ -> decode.failure(EvalSamplesAuto, "EvalSamples")
    }
  }), [
    decode.int |> decode.then(fn(n) { decode.success(EvalSamples(n)) }),
  ])
}

pub fn fine_tune_reasoning_effort_decoder() -> decode.Decoder(
  FineTuneReasoningEffort,
) {
  use value <- decode.then(decode.string)
  case value {
    "default" -> decode.success(FineTuneReasoningDefault)
    "low" -> decode.success(FineTuneReasoningLow)
    "medium" -> decode.success(FineTuneReasoningMedium)
    "high" -> decode.success(FineTuneReasoningHigh)
    _ -> decode.failure(FineTuneReasoningDefault, "FineTuneReasoningEffort")
  }
}

pub fn supervised_hyperparameters_decoder() -> decode.Decoder(
  FineTuneSupervisedHyperparameters,
) {
  use batch_size <- decode.field("batch_size", batch_size_decoder())
  use learning_rate_multiplier <- decode.field(
    "learning_rate_multiplier",
    learning_rate_multiplier_decoder(),
  )
  use n_epochs <- decode.field("n_epochs", n_epochs_decoder())
  decode.success(FineTuneSupervisedHyperparameters(
    batch_size: batch_size,
    learning_rate_multiplier: learning_rate_multiplier,
    n_epochs: n_epochs,
  ))
}

pub fn dpo_hyperparameters_decoder() -> decode.Decoder(
  FineTuneDpoHyperparameters,
) {
  use beta <- decode.field("beta", beta_decoder())
  use batch_size <- decode.field("batch_size", batch_size_decoder())
  use learning_rate_multiplier <- decode.field(
    "learning_rate_multiplier",
    learning_rate_multiplier_decoder(),
  )
  use n_epochs <- decode.field("n_epochs", n_epochs_decoder())
  decode.success(FineTuneDpoHyperparameters(
    beta: beta,
    batch_size: batch_size,
    learning_rate_multiplier: learning_rate_multiplier,
    n_epochs: n_epochs,
  ))
}

pub fn reinforcement_hyperparameters_decoder() -> decode.Decoder(
  FineTuneReinforcementHyperparameters,
) {
  use batch_size <- decode.field("batch_size", batch_size_decoder())
  use learning_rate_multiplier <- decode.field(
    "learning_rate_multiplier",
    learning_rate_multiplier_decoder(),
  )
  use n_epochs <- decode.field("n_epochs", n_epochs_decoder())
  use reasoning_effort <- decode.field(
    "reasoning_effort",
    fine_tune_reasoning_effort_decoder(),
  )
  use compute_multiplier <- decode.field(
    "compute_multiplier",
    compute_multiplier_decoder(),
  )
  use eval_interval <- decode.field(
    "eval_interval",
    eval_interval_decoder(),
  )
  use eval_samples <- decode.field("eval_samples", eval_samples_decoder())
  decode.success(FineTuneReinforcementHyperparameters(
    batch_size: batch_size,
    learning_rate_multiplier: learning_rate_multiplier,
    n_epochs: n_epochs,
    reasoning_effort: reasoning_effort,
    compute_multiplier: compute_multiplier,
    eval_interval: eval_interval,
    eval_samples: eval_samples,
  ))
}

pub fn hyperparameters_decoder() -> decode.Decoder(Hyperparameters) {
  use batch_size <- decode.field("batch_size", batch_size_decoder())
  use learning_rate_multiplier <- decode.field(
    "learning_rate_multiplier",
    learning_rate_multiplier_decoder(),
  )
  use n_epochs <- decode.field("n_epochs", n_epochs_decoder())
  decode.success(Hyperparameters(
    batch_size: batch_size,
    learning_rate_multiplier: learning_rate_multiplier,
    n_epochs: n_epochs,
  ))
}

pub fn grader_string_check_operation_decoder() -> decode.Decoder(
  GraderStringCheckOperation,
) {
  use value <- decode.then(decode.string)
  case value {
    "eq" -> decode.success(GraderOpEq)
    "ne" -> decode.success(GraderOpNe)
    "like" -> decode.success(GraderOpLike)
    "ilike" -> decode.success(GraderOpIlike)
    _ -> decode.failure(GraderOpEq, "GraderStringCheckOperation")
  }
}

pub fn grader_text_similarity_metric_decoder() -> decode.Decoder(
  GraderTextSimilarityMetric,
) {
  use value <- decode.then(decode.string)
  case value {
    "cosine" -> decode.success(MetricCosine)
    "fuzzy_match" -> decode.success(MetricFuzzyMatch)
    "bleu" -> decode.success(MetricBleu)
    "gleu" -> decode.success(MetricGleu)
    "meteor" -> decode.success(MetricMeteor)
    "rouge_1" -> decode.success(MetricRouge1)
    "rouge_2" -> decode.success(MetricRouge2)
    "rouge_3" -> decode.success(MetricRouge3)
    "rouge_4" -> decode.success(MetricRouge4)
    "rouge_5" -> decode.success(MetricRouge5)
    "rouge_l" -> decode.success(MetricRougeL)
    _ -> decode.failure(MetricCosine, "GraderTextSimilarityMetric")
  }
}

pub fn eval_item_decoder() -> decode.Decoder(EvalItem) {
  use role <- decode.field("role", decode.string)
  use content <- decode.field("content", decode.string)
  decode.success(EvalItem(role: role, content: content))
}

pub fn grader_score_model_sampling_params_decoder() -> decode.Decoder(
  GraderScoreModelSamplingParams,
) {
  use seed <- decode.optional_field(
    "seed",
    None,
    decode.optional(decode.int),
  )
  use top_p <- decode.optional_field(
    "top_p",
    None,
    decode.optional(decode.float),
  )
  use temperature <- decode.optional_field(
    "temperature",
    None,
    decode.optional(decode.float),
  )
  use max_completion_tokens <- decode.optional_field(
    "max_completion_tokens",
    None,
    decode.optional(decode.int),
  )
  use reasoning_effort <- decode.optional_field(
    "reasoning_effort",
    None,
    decode.optional(shared.reasoning_effort_decoder()),
  )
  decode.success(GraderScoreModelSamplingParams(
    seed: seed,
    top_p: top_p,
    temperature: temperature,
    max_completion_tokens: max_completion_tokens,
    reasoning_effort: reasoning_effort,
  ))
}

pub fn fine_tune_grader_decoder() -> decode.Decoder(FineTuneGrader) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "string_check" -> {
      use name <- decode.field("name", decode.string)
      use input <- decode.field("input", decode.string)
      use reference <- decode.field("reference", decode.string)
      use operation <- decode.field(
        "operation",
        grader_string_check_operation_decoder(),
      )
      decode.success(StringCheckGrader(GraderStringCheck(
        name: name,
        input: input,
        reference: reference,
        operation: operation,
      )))
    }
    "text_similarity" -> {
      use name <- decode.field("name", decode.string)
      use input <- decode.field("input", decode.string)
      use reference <- decode.field("reference", decode.string)
      use evaluation_metric <- decode.field(
        "evaluation_metric",
        grader_text_similarity_metric_decoder(),
      )
      decode.success(TextSimilarityGrader(GraderTextSimilarity(
        name: name,
        input: input,
        reference: reference,
        evaluation_metric: evaluation_metric,
      )))
    }
    "python" -> {
      use name <- decode.field("name", decode.string)
      use source <- decode.field("source", decode.string)
      use image_tag <- decode.optional_field(
        "image_tag",
        None,
        decode.optional(decode.string),
      )
      decode.success(PythonGrader(GraderPython(
        name: name,
        source: source,
        image_tag: image_tag,
      )))
    }
    "score_model" -> {
      use name <- decode.field("name", decode.string)
      use model <- decode.field("model", decode.string)
      use input <- decode.field("input", decode.list(eval_item_decoder()))
      use sampling_params <- decode.optional_field(
        "sampling_params",
        None,
        decode.optional(grader_score_model_sampling_params_decoder()),
      )
      use range <- decode.optional_field(
        "range",
        None,
        decode.optional(decode.list(decode.float)),
      )
      decode.success(ScoreModelGrader(GraderScoreModel(
        name: name,
        model: model,
        input: input,
        sampling_params: sampling_params,
        range: range,
      )))
    }
    "multi" -> {
      use name <- decode.field("name", decode.string)
      use graders <- decode.field("graders", decode.dynamic)
      use calculate_output <- decode.field(
        "calculate_output",
        decode.string,
      )
      decode.success(MultiGrader(
        name: name,
        graders: graders,
        calculate_output: calculate_output,
      ))
    }
    _ -> decode.failure(PythonGrader(GraderPython(
      name: "",
      source: "",
      image_tag: None,
    )), "FineTuneGrader")
  }
}

pub fn fine_tune_method_decoder() -> decode.Decoder(FineTuneMethod) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "supervised" -> {
      use supervised <- decode.field(
        "supervised",
        fine_tune_supervised_method_decoder(),
      )
      decode.success(Supervised(supervised: supervised))
    }
    "dpo" -> {
      use dpo <- decode.field("dpo", fine_tune_dpo_method_decoder())
      decode.success(Dpo(dpo: dpo))
    }
    "reinforcement" -> {
      use reinforcement <- decode.field(
        "reinforcement",
        fine_tune_reinforcement_method_decoder(),
      )
      decode.success(Reinforcement(reinforcement: reinforcement))
    }
    _ -> decode.failure(Supervised(
      supervised: FineTuneSupervisedMethod(
        hyperparameters: FineTuneSupervisedHyperparameters(
          batch_size: BatchSizeAuto,
          learning_rate_multiplier: LearningRateMultiplierAuto,
          n_epochs: NEpochsAuto,
        ),
      ),
    ), "FineTuneMethod")
  }
}

fn fine_tune_supervised_method_decoder() -> decode.Decoder(
  FineTuneSupervisedMethod,
) {
  use hyperparameters <- decode.field(
    "hyperparameters",
    supervised_hyperparameters_decoder(),
  )
  decode.success(FineTuneSupervisedMethod(hyperparameters: hyperparameters))
}

fn fine_tune_dpo_method_decoder() -> decode.Decoder(FineTuneDpoMethod) {
  use hyperparameters <- decode.field(
    "hyperparameters",
    dpo_hyperparameters_decoder(),
  )
  decode.success(FineTuneDpoMethod(hyperparameters: hyperparameters))
}

fn fine_tune_reinforcement_method_decoder() -> decode.Decoder(
  FineTuneReinforcementMethod,
) {
  use grader <- decode.field("grader", fine_tune_grader_decoder())
  use hyperparameters <- decode.field(
    "hyperparameters",
    reinforcement_hyperparameters_decoder(),
  )
  decode.success(FineTuneReinforcementMethod(
    grader: grader,
    hyperparameters: hyperparameters,
  ))
}

pub fn wandb_decoder() -> decode.Decoder(WandB) {
  use project <- decode.field("project", decode.string)
  use name <- decode.optional_field(
    "name",
    None,
    decode.optional(decode.string),
  )
  use entity <- decode.optional_field(
    "entity",
    None,
    decode.optional(decode.string),
  )
  use tags <- decode.optional_field(
    "tags",
    None,
    decode.optional(decode.list(decode.string)),
  )
  decode.success(WandB(
    project: project,
    name: name,
    entity: entity,
    tags: tags,
  ))
}

pub fn fine_tuning_integration_decoder() -> decode.Decoder(
  FineTuningIntegration,
) {
  use wandb <- decode.field("wandb", wandb_decoder())
  decode.success(FineTuningIntegration(wandb: wandb))
}

pub fn fine_tuning_job_status_decoder() -> decode.Decoder(
  FineTuningJobStatus,
) {
  use value <- decode.then(decode.string)
  case value {
    "validating_files" -> decode.success(ValidatingFiles)
    "queued" -> decode.success(Queued)
    "running" -> decode.success(Running)
    "succeeded" -> decode.success(Succeeded)
    "failed" -> decode.success(JobFailed)
    "cancelled" -> decode.success(JobCancelled)
    _ -> decode.failure(Queued, "FineTuningJobStatus")
  }
}

pub fn fine_tune_job_error_decoder() -> decode.Decoder(FineTuneJobError) {
  use code <- decode.field("code", decode.string)
  use message <- decode.field("message", decode.string)
  use param <- decode.optional_field(
    "param",
    None,
    decode.optional(decode.string),
  )
  decode.success(FineTuneJobError(
    code: code,
    message: message,
    param: param,
  ))
}

pub fn fine_tuning_job_decoder() -> decode.Decoder(FineTuningJob) {
  use id <- decode.field("id", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use error <- decode.optional_field(
    "error",
    None,
    decode.optional(fine_tune_job_error_decoder()),
  )
  use fine_tuned_model <- decode.optional_field(
    "fine_tuned_model",
    None,
    decode.optional(decode.string),
  )
  use finished_at <- decode.optional_field(
    "finished_at",
    None,
    decode.optional(decode.int),
  )
  use hyperparameters <- decode.field(
    "hyperparameters",
    hyperparameters_decoder(),
  )
  use model <- decode.field("model", decode.string)
  use object <- decode.field("object", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use result_files <- decode.field(
    "result_files",
    decode.list(decode.string),
  )
  use status <- decode.field("status", fine_tuning_job_status_decoder())
  use trained_tokens <- decode.optional_field(
    "trained_tokens",
    None,
    decode.optional(decode.int),
  )
  use training_file <- decode.field("training_file", decode.string)
  use validation_file <- decode.optional_field(
    "validation_file",
    None,
    decode.optional(decode.string),
  )
  use integrations <- decode.optional_field(
    "integrations",
    None,
    decode.optional(decode.list(fine_tuning_integration_decoder())),
  )
  use seed <- decode.field("seed", decode.int)
  use estimated_finish <- decode.optional_field(
    "estimated_finish",
    None,
    decode.optional(decode.int),
  )
  use method <- decode.optional_field(
    "method",
    None,
    decode.optional(fine_tune_method_decoder()),
  )
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(decode.dynamic),
  )
  decode.success(FineTuningJob(
    id: id,
    created_at: created_at,
    error: error,
    fine_tuned_model: fine_tuned_model,
    finished_at: finished_at,
    hyperparameters: hyperparameters,
    model: model,
    object: object,
    organization_id: organization_id,
    result_files: result_files,
    status: status,
    trained_tokens: trained_tokens,
    training_file: training_file,
    validation_file: validation_file,
    integrations: integrations,
    seed: seed,
    estimated_finish: estimated_finish,
    method: method,
    metadata: metadata,
  ))
}

pub fn event_level_decoder() -> decode.Decoder(EventLevel) {
  use value <- decode.then(decode.string)
  case value {
    "info" -> decode.success(LevelInfo)
    "warn" -> decode.success(LevelWarn)
    "error" -> decode.success(LevelError)
    _ -> decode.failure(LevelInfo, "EventLevel")
  }
}

pub fn fine_tuning_job_event_type_decoder() -> decode.Decoder(
  FineTuningJobEventType,
) {
  use value <- decode.then(decode.string)
  case value {
    "message" -> decode.success(EventMessage)
    "metrics" -> decode.success(EventMetrics)
    _ -> decode.failure(EventMessage, "FineTuningJobEventType")
  }
}

pub fn fine_tuning_job_event_decoder() -> decode.Decoder(
  FineTuningJobEvent,
) {
  use id <- decode.field("id", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use level <- decode.field("level", event_level_decoder())
  use message <- decode.field("message", decode.string)
  use object <- decode.field("object", decode.string)
  use event_type <- decode.optional_field(
    "type",
    None,
    decode.optional(fine_tuning_job_event_type_decoder()),
  )
  use data <- decode.optional_field(
    "data",
    None,
    decode.optional(decode.dynamic),
  )
  decode.success(FineTuningJobEvent(
    id: id,
    created_at: created_at,
    level: level,
    message: message,
    object: object,
    event_type: event_type,
    data: data,
  ))
}

pub fn fine_tuning_job_checkpoint_metrics_decoder() -> decode.Decoder(
  FineTuningJobCheckpointMetrics,
) {
  use step <- decode.field("step", decode.int)
  use train_loss <- decode.field("train_loss", decode.float)
  use train_mean_token_accuracy <- decode.field(
    "train_mean_token_accuracy",
    decode.float,
  )
  use valid_loss <- decode.field("valid_loss", decode.float)
  use valid_mean_token_accuracy <- decode.field(
    "valid_mean_token_accuracy",
    decode.float,
  )
  use full_valid_loss <- decode.field("full_valid_loss", decode.float)
  use full_valid_mean_token_accuracy <- decode.field(
    "full_valid_mean_token_accuracy",
    decode.float,
  )
  decode.success(FineTuningJobCheckpointMetrics(
    step: step,
    train_loss: train_loss,
    train_mean_token_accuracy: train_mean_token_accuracy,
    valid_loss: valid_loss,
    valid_mean_token_accuracy: valid_mean_token_accuracy,
    full_valid_loss: full_valid_loss,
    full_valid_mean_token_accuracy: full_valid_mean_token_accuracy,
  ))
}

pub fn fine_tuning_job_checkpoint_decoder() -> decode.Decoder(
  FineTuningJobCheckpoint,
) {
  use id <- decode.field("id", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use fine_tuned_model_checkpoint <- decode.field(
    "fine_tuned_model_checkpoint",
    decode.string,
  )
  use step_number <- decode.field("step_number", decode.int)
  use metrics <- decode.field(
    "metrics",
    fine_tuning_job_checkpoint_metrics_decoder(),
  )
  use fine_tuning_job_id <- decode.field(
    "fine_tuning_job_id",
    decode.string,
  )
  use object <- decode.field("object", decode.string)
  decode.success(FineTuningJobCheckpoint(
    id: id,
    created_at: created_at,
    fine_tuned_model_checkpoint: fine_tuned_model_checkpoint,
    step_number: step_number,
    metrics: metrics,
    fine_tuning_job_id: fine_tuning_job_id,
    object: object,
  ))
}

pub fn fine_tuning_checkpoint_permission_decoder() -> decode.Decoder(
  FineTuningCheckpointPermission,
) {
  use id <- decode.field("id", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use project_id <- decode.field("project_id", decode.string)
  use object <- decode.field("object", decode.string)
  decode.success(FineTuningCheckpointPermission(
    id: id,
    created_at: created_at,
    project_id: project_id,
    object: object,
  ))
}

fn list_paginated_fine_tuning_jobs_response_decoder() -> decode.Decoder(
  ListPaginatedFineTuningJobsResponse,
) {
  use data <- decode.field(
    "data",
    decode.list(fine_tuning_job_decoder()),
  )
  use has_more <- decode.field("has_more", decode.bool)
  use object <- decode.field("object", decode.string)
  decode.success(ListPaginatedFineTuningJobsResponse(
    data: data,
    has_more: has_more,
    object: object,
  ))
}

fn list_fine_tuning_job_events_response_decoder() -> decode.Decoder(
  ListFineTuningJobEventsResponse,
) {
  use data <- decode.field(
    "data",
    decode.list(fine_tuning_job_event_decoder()),
  )
  use object <- decode.field("object", decode.string)
  decode.success(ListFineTuningJobEventsResponse(
    data: data,
    object: object,
  ))
}

fn list_fine_tuning_job_checkpoints_response_decoder() -> decode.Decoder(
  ListFineTuningJobCheckpointsResponse,
) {
  use data <- decode.field(
    "data",
    decode.list(fine_tuning_job_checkpoint_decoder()),
  )
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
  decode.success(ListFineTuningJobCheckpointsResponse(
    data: data,
    object: object,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

fn list_fine_tuning_checkpoint_permission_response_decoder() -> decode.Decoder(
  ListFineTuningCheckpointPermissionResponse,
) {
  use data <- decode.field(
    "data",
    decode.list(fine_tuning_checkpoint_permission_decoder()),
  )
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
  decode.success(ListFineTuningCheckpointPermissionResponse(
    data: data,
    object: object,
    first_id: first_id,
    last_id: last_id,
    has_more: has_more,
  ))
}

fn delete_fine_tuning_checkpoint_permission_response_decoder() -> decode.Decoder(
  DeleteFineTuningCheckpointPermissionResponse,
) {
  use object <- decode.field("object", decode.string)
  use id <- decode.field("id", decode.string)
  use deleted <- decode.field("deleted", decode.bool)
  decode.success(DeleteFineTuningCheckpointPermissionResponse(
    object: object,
    id: id,
    deleted: deleted,
  ))
}

// ============================================================================
// Request/Response pairs (sans-io)
// ============================================================================

/// Build a request to create a fine-tuning job.
pub fn create_request(
  config: Config,
  params: CreateFineTuningJobRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/fine_tuning/jobs",
    create_fine_tuning_job_request_to_json(params),
  )
}

/// Parse the response from creating a fine-tuning job.
pub fn create_response(
  response: Response(String),
) -> Result(FineTuningJob, GlaoiError) {
  internal.parse_response(response, fine_tuning_job_decoder())
}

/// Build a request to list fine-tuning jobs.
pub fn list_request(config: Config) -> Request(String) {
  internal.get_request(config, "/fine_tuning/jobs")
}

/// Parse the response from listing fine-tuning jobs.
pub fn list_response(
  response: Response(String),
) -> Result(ListPaginatedFineTuningJobsResponse, GlaoiError) {
  internal.parse_response(
    response,
    list_paginated_fine_tuning_jobs_response_decoder(),
  )
}

/// Build a request to retrieve a fine-tuning job.
pub fn retrieve_request(
  config: Config,
  fine_tuning_job_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/fine_tuning/jobs/" <> fine_tuning_job_id,
  )
}

/// Parse the response from retrieving a fine-tuning job.
pub fn retrieve_response(
  response: Response(String),
) -> Result(FineTuningJob, GlaoiError) {
  internal.parse_response(response, fine_tuning_job_decoder())
}

/// Build a request to cancel a fine-tuning job.
pub fn cancel_request(
  config: Config,
  fine_tuning_job_id: String,
) -> Request(String) {
  internal.post_request(
    config,
    "/fine_tuning/jobs/" <> fine_tuning_job_id <> "/cancel",
    json.object([]),
  )
}

/// Parse the response from cancelling a fine-tuning job.
pub fn cancel_response(
  response: Response(String),
) -> Result(FineTuningJob, GlaoiError) {
  internal.parse_response(response, fine_tuning_job_decoder())
}

/// Build a request to pause a fine-tuning job.
pub fn pause_request(
  config: Config,
  fine_tuning_job_id: String,
) -> Request(String) {
  internal.post_request(
    config,
    "/fine_tuning/jobs/" <> fine_tuning_job_id <> "/pause",
    json.object([]),
  )
}

/// Parse the response from pausing a fine-tuning job.
pub fn pause_response(
  response: Response(String),
) -> Result(FineTuningJob, GlaoiError) {
  internal.parse_response(response, fine_tuning_job_decoder())
}

/// Build a request to resume a fine-tuning job.
pub fn resume_request(
  config: Config,
  fine_tuning_job_id: String,
) -> Request(String) {
  internal.post_request(
    config,
    "/fine_tuning/jobs/" <> fine_tuning_job_id <> "/resume",
    json.object([]),
  )
}

/// Parse the response from resuming a fine-tuning job.
pub fn resume_response(
  response: Response(String),
) -> Result(FineTuningJob, GlaoiError) {
  internal.parse_response(response, fine_tuning_job_decoder())
}

/// Build a request to list events for a fine-tuning job.
pub fn list_events_request(
  config: Config,
  fine_tuning_job_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/fine_tuning/jobs/" <> fine_tuning_job_id <> "/events",
  )
}

/// Parse the response from listing fine-tuning job events.
pub fn list_events_response(
  response: Response(String),
) -> Result(ListFineTuningJobEventsResponse, GlaoiError) {
  internal.parse_response(
    response,
    list_fine_tuning_job_events_response_decoder(),
  )
}

/// Build a request to list checkpoints for a fine-tuning job.
pub fn list_checkpoints_request(
  config: Config,
  fine_tuning_job_id: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/fine_tuning/jobs/" <> fine_tuning_job_id <> "/checkpoints",
  )
}

/// Parse the response from listing fine-tuning job checkpoints.
pub fn list_checkpoints_response(
  response: Response(String),
) -> Result(ListFineTuningJobCheckpointsResponse, GlaoiError) {
  internal.parse_response(
    response,
    list_fine_tuning_job_checkpoints_response_decoder(),
  )
}

/// Build a request to create checkpoint permissions.
pub fn create_checkpoint_permission_request(
  config: Config,
  fine_tuned_model_checkpoint: String,
  params: CreateFineTuningCheckpointPermissionRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/fine_tuning/checkpoints/"
      <> fine_tuned_model_checkpoint
      <> "/permissions",
    create_checkpoint_permission_request_to_json(params),
  )
}

/// Parse the response from creating checkpoint permissions.
pub fn create_checkpoint_permission_response(
  response: Response(String),
) -> Result(ListFineTuningCheckpointPermissionResponse, GlaoiError) {
  internal.parse_response(
    response,
    list_fine_tuning_checkpoint_permission_response_decoder(),
  )
}

/// Build a request to list checkpoint permissions.
pub fn list_checkpoint_permissions_request(
  config: Config,
  fine_tuned_model_checkpoint: String,
) -> Request(String) {
  internal.get_request(
    config,
    "/fine_tuning/checkpoints/"
      <> fine_tuned_model_checkpoint
      <> "/permissions",
  )
}

/// Parse the response from listing checkpoint permissions.
pub fn list_checkpoint_permissions_response(
  response: Response(String),
) -> Result(ListFineTuningCheckpointPermissionResponse, GlaoiError) {
  internal.parse_response(
    response,
    list_fine_tuning_checkpoint_permission_response_decoder(),
  )
}

/// Build a request to delete a checkpoint permission.
pub fn delete_checkpoint_permission_request(
  config: Config,
  fine_tuned_model_checkpoint: String,
  permission_id: String,
) -> Request(String) {
  internal.delete_request(
    config,
    "/fine_tuning/checkpoints/"
      <> fine_tuned_model_checkpoint
      <> "/permissions/"
      <> permission_id,
  )
}

/// Parse the response from deleting a checkpoint permission.
pub fn delete_checkpoint_permission_response(
  response: Response(String),
) -> Result(DeleteFineTuningCheckpointPermissionResponse, GlaoiError) {
  internal.parse_response(
    response,
    delete_fine_tuning_checkpoint_permission_response_decoder(),
  )
}
