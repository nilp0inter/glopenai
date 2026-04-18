// Port of: examples/image-generate/ and examples/image-generate-b64-json/
//
// Generate images from text prompts using the image generation API.
// Demonstrates URL response format (default) and base64 JSON response format.
//
// Run with: gleam run -m example/image_generate

import example/env
import gleam/int
import gleam/io
import gleam/list
import gleam/httpc
import gleam/option.{None, Some}
import gleam/string
import glopenai/config
import glopenai/image

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // Generate with URL response (default)
  io.println("--- Image generation (URL response) ---")
  let request =
    image.new_create_request(prompt: "cats on sofa and carpet in living room")
    |> image.with_n(1)
    |> image.with_response_format(image.Url)
    |> image.with_size(image.Size256x256)
    |> image.with_user("glopenai")

  let http_request = image.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = image.create_response(http_response)

  list.each(response.data, fn(img) {
    case img {
      image.ImageUrl(url, revised_prompt) -> {
        io.println("Image URL: " <> url)
        print_revised_prompt(revised_prompt)
      }
      image.ImageB64Json(_, _) -> io.println("(unexpected b64 response)")
    }
  })

  // Generate with base64 JSON response
  io.println("\n--- Image generation (base64 JSON response) ---")
  let request =
    image.new_create_request(
      prompt: "Generate a logo for an open-source Gleam library",
    )
    |> image.with_n(1)
    |> image.with_response_format(image.B64Json)
    |> image.with_size(image.Size256x256)
    |> image.with_user("glopenai")

  let http_request = image.create_request(cfg, request)
  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = image.create_response(http_response)

  list.each(response.data, fn(img) {
    case img {
      image.ImageB64Json(b64, revised_prompt) -> {
        // In a real app you'd decode the base64 and save to a file
        io.println(
          "Received base64 image data ("
          <> int.to_string(string.length(b64))
          <> " characters)",
        )
        print_revised_prompt(revised_prompt)
      }
      image.ImageUrl(_, _) -> io.println("(unexpected url response)")
    }
  })
}

fn print_revised_prompt(revised_prompt: option.Option(String)) -> Nil {
  case revised_prompt {
    Some(prompt) -> io.println("Revised prompt: " <> prompt)
    None -> Nil
  }
}
