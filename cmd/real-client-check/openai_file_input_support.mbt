///|
fn validate_openai_responses_input_file_carrier(
  body : String,
  expected_fragment : String,
  summary : String,
  filename : String?,
) -> String raise LiveCheckError {
  ignore(validate_openai_responses_carrier(body))
  if not(body.contains("\"type\":\"input_file\"")) {
    raise ValidationFailed("OpenAI Responses request missed input_file part")
  }
  if not(body.contains(expected_fragment)) {
    raise ValidationFailed(
      "OpenAI Responses request missed expected input_file carrier: " +
        expected_fragment,
    )
  }
  match filename {
    Some(name) =>
      if not(body.contains("\"filename\":\"\{name}\"")) {
        raise ValidationFailed("OpenAI Responses request missed input filename")
      }
    None => ()
  }
  summary
}

///|
fn validate_openai_chat_file_carrier(
  body : String,
  expected_fragment : String,
  summary : String,
  filename : String?,
) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("OpenAI Chat request missed response_format")
  }
  if not(body.contains("\"type\":\"file\"")) {
    raise ValidationFailed("OpenAI Chat request missed file content part")
  }
  if not(body.contains(expected_fragment)) {
    raise ValidationFailed(
      "OpenAI Chat request missed expected file carrier: " + expected_fragment,
    )
  }
  match filename {
    Some(name) =>
      if not(body.contains("\"filename\":\"\{name}\"")) {
        raise ValidationFailed("OpenAI Chat request missed file filename")
      }
    None => ()
  }
  summary
}

///|
fn build_openai_file_upload_body(
  boundary : String,
  filename : String,
  mime_type : String,
  content : String,
) -> String {
  "--\{boundary}\r\n" +
  "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n" +
  "user_data\r\n" +
  "--\{boundary}\r\n" +
  "Content-Disposition: form-data; name=\"file\"; filename=\"\{filename}\"\r\n" +
  "Content-Type: \{mime_type}\r\n\r\n" +
  content +
  "\r\n--\{boundary}--\r\n"
}

///|
async fn upload_openai_file(
  api_key : String,
  fixture : FileFixture,
) -> String raise LiveCheckError {
  let boundary = "llm_interop_realcheck_upload_boundary"
  let body = build_openai_file_upload_body(
    boundary,
    fixture.filename,
    fixture.media_type,
    fixture.raw_content,
  )
  let headers = {
    "Authorization": "Bearer " + api_key,
    "Content-Type": "multipart/form-data; boundary=" + boundary,
  }
  let (response, data) = @async.with_timeout(request_timeout_ms, () => {
    @http.post("https://api.openai.com/v1/files", body, headers=headers)
  }) catch {
    @async.TimeoutError =>
      raise ValidationFailed("openai file upload timed out: " + fixture.filename)
    err =>
      raise ValidationFailed(
        "openai file upload transport error: " +
          fixture.filename +
          " " +
          err.to_string(),
      )
  }
  let text = data.text() catch { _ => "" }
  if response.code < 200 || response.code >= 300 {
    raise ValidationFailed(
      "openai file upload failed: " +
        fixture.filename +
        " " +
        response.code.to_string() +
        " " +
        text,
    )
  }
  let json = @json.parse(text) catch {
    err =>
      raise ValidationFailed(
        "openai file upload returned invalid JSON: " +
          fixture.filename +
          " " +
          err.to_string(),
      )
  }
  match json {
    { "id": String(file_id), .. } => file_id
    _ => raise ValidationFailed("openai file upload response missed file id")
  }
}
