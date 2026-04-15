// Port of: examples/vision-chat/
//
// Chat completion with an image URL input.
//
// Run with: gleam run -m example/vision_chat

import example/env
import gleam/io
import gleam/httpc
import gleam/option.{Some}
import glaoi/chat
import glaoi/config
import glaoi/shared

pub fn main() -> Nil {
  let cfg = config.new(api_key: env.get_api_key())

  // Image Credit: https://unsplash.com/photos/pride-of-lion-on-field-L4-BDd01wmM
  let image_url =
    "https://images.unsplash.com/photo-1554990772-0bea55d510d5?q=80&w=512&auto=format"

  let request =
    chat.new_create_request(model: "gpt-4o-mini", messages: [
      chat.UserMessage(
        content: chat.UserPartsContent([
          chat.UserTextPart("What is this image?"),
          chat.UserImageUrlPart(shared.ImageUrl(
            url: image_url,
            detail: Some(shared.High),
          )),
        ]),
        name: option.None,
      ),
    ])
    |> chat.with_max_completion_tokens(300)

  let http_request = chat.create_request(cfg, request)

  let assert Ok(http_response) = httpc.send(http_request)
  let assert Ok(response) = chat.create_response(http_response)

  io.println("\nResponse:\n")
  case response.choices {
    [choice, ..] ->
      case choice.message.content {
        Some(content) -> io.println(content)
        _ -> io.println("(no content)")
      }
    [] -> io.println("(no choices)")
  }
}
