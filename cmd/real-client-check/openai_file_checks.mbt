///|
async fn run_openai_file_checks(
  opts : CliOptions,
  reports : Array[CheckReport],
  failures : Array[String],
  api_key : String,
  responses_provider : @gateway.ProviderConfig,
  chat_provider : @gateway.ProviderConfig,
  candidates : Array[String],
) -> Unit {
  let text_fixture = text_file_fixture()
  let pdf_fixture = pdf_file_fixture()
  let mut uploaded_text_file_id : String? = None
  let mut uploaded_pdf_file_id : String? = None

  if should_run_check(opts, "openai.responses.sync.file_url") {
    let report = Some(
      run_responses_sync_check_with_messages(
        "openai.responses.sync.file_url",
        responses_provider,
        candidates,
        company_response_format(),
        file_url_messages(),
        validate_company_response,
        (body) =>
          validate_openai_responses_input_file_carrier(
            body,
            "\"file_url\":\"\{expected_file_url}\"",
            "responses:input_file.file_url + text.format normalized(openai)",
            None,
          ),
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_url", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_url", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.file_url") {
    let report = Some(
      run_stream_check_with_messages(
        "openai.responses.stream.file_url",
        responses_provider,
        candidates,
        company_response_format(),
        file_url_messages(),
        validate_company_response,
        (body) =>
          validate_openai_responses_input_file_carrier(
            body,
            "\"file_url\":\"\{expected_file_url}\"",
            "responses:input_file.file_url + text.format normalized(openai)",
            None,
          ),
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_url", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_url", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.file_data") {
    let report = Some(
      run_responses_sync_check_with_messages(
        "openai.responses.sync.file_data",
        responses_provider,
        candidates,
        company_response_format(),
        file_data_messages(),
        validate_company_response,
        (body) =>
          validate_openai_responses_input_file_carrier(
            body,
            "\"file_data\":\"data:\{text_fixture.media_type};base64,\{text_fixture.base64_data}\"",
            "responses:input_file.file_data + text.format normalized(openai)",
            Some(text_fixture.filename),
          ),
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_data", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_data", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.file_data") {
    let report = Some(
      run_stream_check_with_messages(
        "openai.responses.stream.file_data",
        responses_provider,
        candidates,
        company_response_format(),
        file_data_messages(),
        validate_company_response,
        (body) =>
          validate_openai_responses_input_file_carrier(
            body,
            "\"file_data\":\"data:\{text_fixture.media_type};base64,\{text_fixture.base64_data}\"",
            "responses:input_file.file_data + text.format normalized(openai)",
            Some(text_fixture.filename),
          ),
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_data", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_data", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.file_data") {
    let report = Some(
      run_chat_check(
        "openai.chat.sync.file_data",
        chat_provider,
        candidates,
        Some(company_response_format()),
        chat_file_data_messages(),
        validate_company_response,
        (body) =>
          validate_openai_chat_file_carrier(
            body,
            "\"file_data\":\"data:\{pdf_fixture.media_type};base64,\{pdf_fixture.base64_data}\"",
            "chat:file.file_data + response_format normalized(openai)",
            Some(pdf_fixture.filename),
          ),
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_data", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_data", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.file_id") {
    let report = Some({
      let file_id = match uploaded_text_file_id {
        Some(id) => id
        None => {
          let id = upload_openai_file(api_key, text_fixture)
          uploaded_text_file_id = Some(id)
          id
        }
      }
      run_responses_sync_check_with_messages(
        "openai.responses.sync.file_id",
        responses_provider,
        candidates,
        company_response_format(),
        file_id_messages(file_id),
        validate_company_response,
        (body) =>
          validate_openai_responses_input_file_carrier(
            body,
            "\"file_id\":\"\{file_id}\"",
            "responses:input_file.file_id + text.format normalized(openai)",
            None,
          ),
      )
    }) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_id", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_id", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.file_id") {
    let report = Some({
      let file_id = match uploaded_text_file_id {
        Some(id) => id
        None => {
          let id = upload_openai_file(api_key, text_fixture)
          uploaded_text_file_id = Some(id)
          id
        }
      }
      run_stream_check_with_messages(
        "openai.responses.stream.file_id",
        responses_provider,
        candidates,
        company_response_format(),
        file_id_messages(file_id),
        validate_company_response,
        (body) =>
          validate_openai_responses_input_file_carrier(
            body,
            "\"file_id\":\"\{file_id}\"",
            "responses:input_file.file_id + text.format normalized(openai)",
            None,
          ),
      )
    }) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_id", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_id", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.file_id") {
    let report = Some({
      let file_id = match uploaded_pdf_file_id {
        Some(id) => id
        None => {
          let id = upload_openai_file(api_key, pdf_fixture)
          uploaded_pdf_file_id = Some(id)
          id
        }
      }
      run_chat_check(
        "openai.chat.sync.file_id",
        chat_provider,
        candidates,
        Some(company_response_format()),
        chat_file_id_messages(file_id),
        validate_company_response,
        (body) =>
          validate_openai_chat_file_carrier(
            body,
            "\"file_id\":\"\{file_id}\"",
            "chat:file.file_id + response_format normalized(openai)",
            None,
          ),
      )
    }) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_id", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_id", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
}
