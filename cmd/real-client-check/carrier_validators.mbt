///|
fn validate_openai_responses_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"text\":{\"format\":")) {
    raise ValidationFailed("OpenAI Responses request missed text.format carrier")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("OpenAI Responses request leaked uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "OpenAI Responses request missed strict normalization",
    )
  }
  "responses:text.format normalized(openai)"
}

///|
fn validate_openai_chat_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("OpenAI Chat request missed response_format")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("OpenAI Chat request leaked uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed("OpenAI Chat request missed strict normalization")
  }
  "chat:response_format normalized(openai)"
}

///|
fn validate_openai_responses_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"text\":{\"format\":{\"type\":\"json_object\"")) {
    raise ValidationFailed("OpenAI Responses request missed json_object text.format")
  }
  "responses:text.format json_object"
}

///|
fn validate_openai_chat_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_object\"")) {
    raise ValidationFailed("OpenAI Chat request missed json_object response_format")
  }
  "chat:response_format json_object"
}

///|
fn validate_anthropic_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"output_config\":{\"format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("Anthropic request missed output_config.format carrier")
  }
  if not(body.contains("\"format\":\"uri\"")) {
    raise ValidationFailed("Anthropic request dropped raw uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Anthropic request missed required additionalProperties=false normalization",
    )
  }
  "anthropic:output_config.format raw(uri-preserved)+additionalProperties:false"
}

///|
fn validate_anthropic_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"output_config\":{\"format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("Anthropic request missed output_config.format carrier")
  }
  if not(body.contains("\"schema\":{\"type\":\"object\"")) {
    raise ValidationFailed("Anthropic json_object request missed object schema")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Anthropic json_object request missed additionalProperties=false normalization",
    )
  }
  "anthropic:output_config.format json_object-via-schema"
}

///|
fn validate_gemini_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"responseMimeType\":\"application/json\"")) {
    raise ValidationFailed("Gemini request missed responseMimeType")
  }
  if not(body.contains("\"responseJsonSchema\"")) {
    raise ValidationFailed("Gemini request missed responseJsonSchema")
  }
  if not(body.contains("\"format\":\"uri\"")) {
    raise ValidationFailed("Gemini request dropped raw uri format")
  }
  if body.contains("\"additionalProperties\":false") {
    raise ValidationFailed("Gemini request unexpectedly normalized schema")
  }
  "gemini:responseJsonSchema raw(uri-preserved)"
}

///|
fn validate_gemini_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"responseMimeType\":\"application/json\"")) {
    raise ValidationFailed("Gemini request missed responseMimeType")
  }
  if body.contains("\"responseJsonSchema\"") || body.contains("\"responseSchema\"") {
    raise ValidationFailed("Gemini json_object request unexpectedly carried schema")
  }
  "gemini:responseMimeType json_object"
}

///|
fn validate_groq_json_object_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_object\"")) {
    raise ValidationFailed("Groq request missed json_object response_format")
  }
  "groq:chat json_object"
}

///|
fn validate_gateway_openai_to_anthropic_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"system\":\"Return only the requested JSON object with no extra prose.\"")) {
    raise ValidationFailed("Anthropic translated request missed system prompt")
  }
  if not(body.contains("\"output_config\":{\"format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("Anthropic translated request missed output_config.format carrier")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("Anthropic translated request leaked raw uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Anthropic translated request missed OpenAI strict normalization",
    )
  }
  "gateway openai->anthropic->openai normalized(openai)"
}

///|
fn validate_gateway_openai_to_anthropic_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"system\":\"Return only the requested JSON object with no extra prose.\"")) {
    raise ValidationFailed("Anthropic translated request missed system prompt")
  }
  ignore(validate_anthropic_json_object_carrier(body))
  "gateway openai->anthropic->openai json_object"
}

///|
fn validate_gateway_openai_to_gemini_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"systemInstruction\"")) {
    raise ValidationFailed("Gemini translated request missed systemInstruction")
  }
  if not(body.contains("Return only the requested JSON object with no extra prose.")) {
    raise ValidationFailed("Gemini translated request missed system prompt text")
  }
  if not(body.contains("\"responseMimeType\":\"application/json\"")) {
    raise ValidationFailed("Gemini translated request missed responseMimeType")
  }
  if not(body.contains("\"responseJsonSchema\"")) {
    raise ValidationFailed("Gemini translated request missed responseJsonSchema")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("Gemini translated request leaked raw uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Gemini translated request missed OpenAI strict normalization",
    )
  }
  "gateway openai->gemini->openai normalized(openai)"
}

///|
fn validate_gateway_openai_to_gemini_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"systemInstruction\"")) {
    raise ValidationFailed("Gemini translated request missed systemInstruction")
  }
  if not(body.contains("Return only the requested JSON object with no extra prose.")) {
    raise ValidationFailed("Gemini translated request missed system prompt text")
  }
  ignore(validate_gemini_json_object_carrier(body))
  "gateway openai->gemini->openai json_object"
}
