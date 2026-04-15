// glaoi - Sans-IO OpenAI API client for Gleam
//
// This library builds HTTP requests and parses HTTP responses for the OpenAI API.
// It does not send or receive HTTP — you bring your own HTTP client.

import glaoi/config
import glaoi/error

pub type Config =
  config.Config

pub type AzureConfig =
  config.AzureConfig

pub type GlaoiError =
  error.GlaoiError

pub type ApiError =
  error.ApiError
