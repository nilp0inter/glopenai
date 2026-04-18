/// Image generation API: create images from text prompts.
/// Edit and variation endpoints require multipart uploads and are deferred.
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glopenai/config.{type Config}
import glopenai/error.{type GlopenaiError}
import glopenai/internal
import glopenai/internal/codec

// --- Types ---

pub type ImageSize {
  SizeAuto
  Size256x256
  Size512x512
  Size1024x1024
  Size1792x1024
  Size1024x1792
  Size1536x1024
  Size1024x1536
}

pub type ImageModel {
  GptImage1
  GptImage1dot5
  GptImage1Mini
  DallE2
  DallE3
  OtherImageModel(String)
}

pub type ImageQuality {
  QualityStandard
  QualityHd
  QualityHigh
  QualityMedium
  QualityLow
  QualityAuto
}

pub type ImageStyle {
  Vivid
  Natural
}

pub type ImageModeration {
  ModerationAuto
  ModerationLow
}

pub type ImageOutputFormat {
  Png
  Jpeg
  Webp
}

pub type ImageResponseFormat {
  Url
  B64Json
}

pub type ImageBackground {
  BackgroundAuto
  BackgroundTransparent
  BackgroundOpaque
}

/// Request to generate images.
pub type CreateImageRequest {
  CreateImageRequest(
    prompt: String,
    model: Option(ImageModel),
    n: Option(Int),
    quality: Option(ImageQuality),
    response_format: Option(ImageResponseFormat),
    output_format: Option(ImageOutputFormat),
    output_compression: Option(Int),
    size: Option(ImageSize),
    moderation: Option(ImageModeration),
    background: Option(ImageBackground),
    style: Option(ImageStyle),
    user: Option(String),
  )
}

/// A generated image, either as a URL or base64-encoded data.
pub type Image {
  ImageUrl(url: String, revised_prompt: Option(String))
  ImageB64Json(b64_json: String, revised_prompt: Option(String))
}

/// Background in the response (transparent vs opaque, without auto).
pub type ImageResponseBackground {
  ResponseTransparent
  ResponseOpaque
}

/// Usage details for image generation input tokens.
pub type ImageGenInputUsageDetails {
  ImageGenInputUsageDetails(text_tokens: Int, image_tokens: Int)
}

/// Usage details for image generation output tokens.
pub type ImageGenOutputTokensDetails {
  ImageGenOutputTokensDetails(text_tokens: Int, image_tokens: Int)
}

/// Token usage for image generation.
pub type ImageGenUsage {
  ImageGenUsage(
    input_tokens: Int,
    output_tokens: Int,
    total_tokens: Int,
    input_tokens_details: ImageGenInputUsageDetails,
    output_token_details: Option(ImageGenOutputTokensDetails),
  )
}

/// Response from creating images.
pub type ImagesResponse {
  ImagesResponse(
    created: Int,
    data: List(Image),
    background: Option(ImageResponseBackground),
    output_format: Option(ImageOutputFormat),
    size: Option(ImageSize),
    quality: Option(ImageQuality),
    usage: Option(ImageGenUsage),
  )
}

// --- Builder ---

/// Create a new image generation request with the required prompt.
pub fn new_create_request(prompt prompt: String) -> CreateImageRequest {
  CreateImageRequest(
    prompt: prompt,
    model: None,
    n: None,
    quality: None,
    response_format: None,
    output_format: None,
    output_compression: None,
    size: None,
    moderation: None,
    background: None,
    style: None,
    user: None,
  )
}

pub fn with_model(
  request: CreateImageRequest,
  model: ImageModel,
) -> CreateImageRequest {
  CreateImageRequest(..request, model: Some(model))
}

pub fn with_n(request: CreateImageRequest, n: Int) -> CreateImageRequest {
  CreateImageRequest(..request, n: Some(n))
}

pub fn with_quality(
  request: CreateImageRequest,
  quality: ImageQuality,
) -> CreateImageRequest {
  CreateImageRequest(..request, quality: Some(quality))
}

pub fn with_response_format(
  request: CreateImageRequest,
  format: ImageResponseFormat,
) -> CreateImageRequest {
  CreateImageRequest(..request, response_format: Some(format))
}

pub fn with_output_format(
  request: CreateImageRequest,
  format: ImageOutputFormat,
) -> CreateImageRequest {
  CreateImageRequest(..request, output_format: Some(format))
}

pub fn with_output_compression(
  request: CreateImageRequest,
  compression: Int,
) -> CreateImageRequest {
  CreateImageRequest(..request, output_compression: Some(compression))
}

pub fn with_size(
  request: CreateImageRequest,
  size: ImageSize,
) -> CreateImageRequest {
  CreateImageRequest(..request, size: Some(size))
}

pub fn with_moderation(
  request: CreateImageRequest,
  moderation: ImageModeration,
) -> CreateImageRequest {
  CreateImageRequest(..request, moderation: Some(moderation))
}

pub fn with_background(
  request: CreateImageRequest,
  background: ImageBackground,
) -> CreateImageRequest {
  CreateImageRequest(..request, background: Some(background))
}

pub fn with_style(
  request: CreateImageRequest,
  style: ImageStyle,
) -> CreateImageRequest {
  CreateImageRequest(..request, style: Some(style))
}

pub fn with_user(
  request: CreateImageRequest,
  user: String,
) -> CreateImageRequest {
  CreateImageRequest(..request, user: Some(user))
}

// --- Encoders ---

pub fn image_size_to_json(size: ImageSize) -> json.Json {
  json.string(case size {
    SizeAuto -> "auto"
    Size256x256 -> "256x256"
    Size512x512 -> "512x512"
    Size1024x1024 -> "1024x1024"
    Size1792x1024 -> "1792x1024"
    Size1024x1792 -> "1024x1792"
    Size1536x1024 -> "1536x1024"
    Size1024x1536 -> "1024x1536"
  })
}

pub fn image_model_to_json(model: ImageModel) -> json.Json {
  json.string(case model {
    GptImage1 -> "gpt-image-1"
    GptImage1dot5 -> "gpt-image-1.5"
    GptImage1Mini -> "gpt-image-1-mini"
    DallE2 -> "dall-e-2"
    DallE3 -> "dall-e-3"
    OtherImageModel(name) -> name
  })
}

pub fn image_quality_to_json(quality: ImageQuality) -> json.Json {
  json.string(case quality {
    QualityStandard -> "standard"
    QualityHd -> "hd"
    QualityHigh -> "high"
    QualityMedium -> "medium"
    QualityLow -> "low"
    QualityAuto -> "auto"
  })
}

pub fn image_style_to_json(style: ImageStyle) -> json.Json {
  json.string(case style {
    Vivid -> "vivid"
    Natural -> "natural"
  })
}

pub fn image_moderation_to_json(moderation: ImageModeration) -> json.Json {
  json.string(case moderation {
    ModerationAuto -> "auto"
    ModerationLow -> "low"
  })
}

pub fn image_output_format_to_json(format: ImageOutputFormat) -> json.Json {
  json.string(case format {
    Png -> "png"
    Jpeg -> "jpeg"
    Webp -> "webp"
  })
}

pub fn image_response_format_to_json(format: ImageResponseFormat) -> json.Json {
  json.string(case format {
    Url -> "url"
    B64Json -> "b64_json"
  })
}

pub fn image_background_to_json(background: ImageBackground) -> json.Json {
  json.string(case background {
    BackgroundAuto -> "auto"
    BackgroundTransparent -> "transparent"
    BackgroundOpaque -> "opaque"
  })
}

pub fn create_image_request_to_json(request: CreateImageRequest) -> json.Json {
  codec.object_with_optional([#("prompt", json.string(request.prompt))], [
    codec.optional_field("model", request.model, image_model_to_json),
    codec.optional_field("n", request.n, json.int),
    codec.optional_field("quality", request.quality, image_quality_to_json),
    codec.optional_field(
      "response_format",
      request.response_format,
      image_response_format_to_json,
    ),
    codec.optional_field(
      "output_format",
      request.output_format,
      image_output_format_to_json,
    ),
    codec.optional_field(
      "output_compression",
      request.output_compression,
      json.int,
    ),
    codec.optional_field("size", request.size, image_size_to_json),
    codec.optional_field(
      "moderation",
      request.moderation,
      image_moderation_to_json,
    ),
    codec.optional_field(
      "background",
      request.background,
      image_background_to_json,
    ),
    codec.optional_field("style", request.style, image_style_to_json),
    codec.optional_field("user", request.user, json.string),
  ])
}

// --- Decoders ---

pub fn image_size_decoder() -> decode.Decoder(ImageSize) {
  use value <- decode.then(decode.string)
  case value {
    "auto" -> decode.success(SizeAuto)
    "256x256" -> decode.success(Size256x256)
    "512x512" -> decode.success(Size512x512)
    "1024x1024" -> decode.success(Size1024x1024)
    "1792x1024" -> decode.success(Size1792x1024)
    "1024x1792" -> decode.success(Size1024x1792)
    "1536x1024" -> decode.success(Size1536x1024)
    "1024x1536" -> decode.success(Size1024x1536)
    _ -> decode.failure(SizeAuto, "ImageSize")
  }
}

pub fn image_model_decoder() -> decode.Decoder(ImageModel) {
  use value <- decode.then(decode.string)
  case value {
    "gpt-image-1" -> decode.success(GptImage1)
    "gpt-image-1.5" -> decode.success(GptImage1dot5)
    "gpt-image-1-mini" -> decode.success(GptImage1Mini)
    "dall-e-2" -> decode.success(DallE2)
    "dall-e-3" -> decode.success(DallE3)
    other -> decode.success(OtherImageModel(other))
  }
}

pub fn image_quality_decoder() -> decode.Decoder(ImageQuality) {
  use value <- decode.then(decode.string)
  case value {
    "standard" -> decode.success(QualityStandard)
    "hd" -> decode.success(QualityHd)
    "high" -> decode.success(QualityHigh)
    "medium" -> decode.success(QualityMedium)
    "low" -> decode.success(QualityLow)
    "auto" -> decode.success(QualityAuto)
    _ -> decode.failure(QualityAuto, "ImageQuality")
  }
}

pub fn image_style_decoder() -> decode.Decoder(ImageStyle) {
  use value <- decode.then(decode.string)
  case value {
    "vivid" -> decode.success(Vivid)
    "natural" -> decode.success(Natural)
    _ -> decode.failure(Vivid, "ImageStyle")
  }
}

pub fn image_output_format_decoder() -> decode.Decoder(ImageOutputFormat) {
  use value <- decode.then(decode.string)
  case value {
    "png" -> decode.success(Png)
    "jpeg" -> decode.success(Jpeg)
    "webp" -> decode.success(Webp)
    _ -> decode.failure(Png, "ImageOutputFormat")
  }
}

pub fn image_response_format_decoder() -> decode.Decoder(ImageResponseFormat) {
  use value <- decode.then(decode.string)
  case value {
    "url" -> decode.success(Url)
    "b64_json" -> decode.success(B64Json)
    _ -> decode.failure(Url, "ImageResponseFormat")
  }
}

pub fn image_response_background_decoder() -> decode.Decoder(
  ImageResponseBackground,
) {
  use value <- decode.then(decode.string)
  case value {
    "transparent" -> decode.success(ResponseTransparent)
    "opaque" -> decode.success(ResponseOpaque)
    _ -> decode.failure(ResponseOpaque, "ImageResponseBackground")
  }
}

/// Decode a generated image. The API returns either a "url" or "b64_json" field
/// depending on the response_format requested. We try URL first, then b64.
pub fn image_decoder() -> decode.Decoder(Image) {
  decode.one_of(
    {
      use url <- decode.field("url", decode.string)
      use revised_prompt <- decode.optional_field(
        "revised_prompt",
        None,
        decode.optional(decode.string),
      )
      decode.success(ImageUrl(url: url, revised_prompt: revised_prompt))
    },
    [
      {
        use b64 <- decode.field("b64_json", decode.string)
        use revised_prompt <- decode.optional_field(
          "revised_prompt",
          None,
          decode.optional(decode.string),
        )
        decode.success(ImageB64Json(
          b64_json: b64,
          revised_prompt: revised_prompt,
        ))
      },
    ],
  )
}

pub fn image_gen_input_usage_details_decoder() -> decode.Decoder(
  ImageGenInputUsageDetails,
) {
  use text_tokens <- decode.field("text_tokens", decode.int)
  use image_tokens <- decode.field("image_tokens", decode.int)
  decode.success(ImageGenInputUsageDetails(
    text_tokens: text_tokens,
    image_tokens: image_tokens,
  ))
}

pub fn image_gen_output_tokens_details_decoder() -> decode.Decoder(
  ImageGenOutputTokensDetails,
) {
  use text_tokens <- decode.field("text_tokens", decode.int)
  use image_tokens <- decode.field("image_tokens", decode.int)
  decode.success(ImageGenOutputTokensDetails(
    text_tokens: text_tokens,
    image_tokens: image_tokens,
  ))
}

pub fn image_gen_usage_decoder() -> decode.Decoder(ImageGenUsage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  use total_tokens <- decode.field("total_tokens", decode.int)
  use input_tokens_details <- decode.field(
    "input_tokens_details",
    image_gen_input_usage_details_decoder(),
  )
  use output_token_details <- decode.optional_field(
    "output_token_details",
    None,
    decode.optional(image_gen_output_tokens_details_decoder()),
  )
  decode.success(ImageGenUsage(
    input_tokens: input_tokens,
    output_tokens: output_tokens,
    total_tokens: total_tokens,
    input_tokens_details: input_tokens_details,
    output_token_details: output_token_details,
  ))
}

fn images_response_decoder() -> decode.Decoder(ImagesResponse) {
  use created <- decode.field("created", decode.int)
  use data <- decode.field("data", decode.list(image_decoder()))
  use background <- decode.optional_field(
    "background",
    None,
    decode.optional(image_response_background_decoder()),
  )
  use output_format <- decode.optional_field(
    "output_format",
    None,
    decode.optional(image_output_format_decoder()),
  )
  use size <- decode.optional_field(
    "size",
    None,
    decode.optional(image_size_decoder()),
  )
  use quality <- decode.optional_field(
    "quality",
    None,
    decode.optional(image_quality_decoder()),
  )
  use usage <- decode.optional_field(
    "usage",
    None,
    decode.optional(image_gen_usage_decoder()),
  )
  decode.success(ImagesResponse(
    created: created,
    data: data,
    background: background,
    output_format: output_format,
    size: size,
    quality: quality,
    usage: usage,
  ))
}

// --- Request/Response pairs (sans-io) ---

/// Build a request to generate images.
pub fn create_request(
  config: Config,
  params: CreateImageRequest,
) -> Request(String) {
  internal.post_request(
    config,
    "/images/generations",
    create_image_request_to_json(params),
  )
}

/// Parse the response from generating images.
pub fn create_response(
  response: Response(String),
) -> Result(ImagesResponse, GlopenaiError) {
  internal.parse_response(response, images_response_decoder())
}
