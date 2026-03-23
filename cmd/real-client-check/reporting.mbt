///|
/// Reporting and optional fixture capture helpers for real-provider checks.

///|
struct CheckReport {
  name : String
  model : String
  mode : String
  request_url : String
  carrier_summary : String
  event_types : Array[String]
  response_text : String
}

///|
fn CheckReport::to_json(self : CheckReport) -> Json {
  {
    "name": self.name,
    "model": self.model,
    "mode": self.mode,
    "request_url": self.request_url,
    "carrier_summary": self.carrier_summary,
    "event_types": Json::array(
      self.event_types.map(fn(event_type) { Json::string(event_type) }),
    ),
    "response_text": self.response_text,
  }
}

///|
fn print_report(report : CheckReport) -> Unit {
  let events = report.event_types.join(",")
  println(
    "[ok] \{report.name} mode=\{report.mode} model=\{report.model}\n  url=\{report.request_url}\n  carrier=\{report.carrier_summary}\n  events=\{events}\n  response=\{report.response_text}",
  )
}

///|
fn print_skip(name : String, reason : String) -> Unit {
  println("[skip] \{name} \{reason}")
}

///|
fn print_failure(name : String, message : String) -> Unit {
  println("[fail] \{name} \{message}")
}

///|
fn print_warning(name : String, message : String) -> Unit {
  println("[warn] \{name} \{message}")
}

///|
fn persist_check_report_if_configured(
  opts : CliOptions,
  report : CheckReport,
) -> Unit {
  match opts.fixtures_dir {
    Some(dir) =>
      write_check_report_fixture(dir, report) catch {
        err =>
          print_warning(
            report.name,
            "failed to save fixture report: " + err.to_string(),
          )
      }
    None => ()
  }
}

///|
fn record_check_success(
  opts : CliOptions,
  reports : Array[CheckReport],
  report : CheckReport,
) -> Unit {
  reports.push(report)
  print_report(report)
  persist_check_report_if_configured(opts, report)
}

///|
fn write_check_report_fixture(
  dir : String,
  report : CheckReport,
) -> Unit raise @fs.IOError {
  ensure_dir_recursive(dir)
  let path = if dir.has_suffix("/") {
    dir + sanitize_fixture_name(report.name) + ".json"
  } else {
    dir + "/" + sanitize_fixture_name(report.name) + ".json"
  }
  @fs.write_string_to_file(
    path,
    report.to_json().stringify(indent=2) + "\n",
  )
}

///|
fn ensure_dir_recursive(dir : String) -> Unit raise @fs.IOError {
  let normalized = dir.trim(chars=" \n\r\t").to_string()
  if normalized == "" || normalized == "." {
    return
  }
  let mut current = if normalized.has_prefix("/") { "/" } else { "" }
  let parts = normalized.split("/").map(StringView::to_string).collect()
  for part in parts {
    if part == "" || part == "." {
      continue
    }
    current = match current {
      "" => part
      "/" => "/" + part
      _ => current + "/" + part
    }
    if not(path_is_dir(current)) {
      @fs.create_dir(current)
    }
  }
}

///|
fn path_is_dir(path : String) -> Bool {
  @fs.is_dir(path) catch { _ => false }
}

///|
fn sanitize_fixture_name(name : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < name.length(); i = i + 1 {
    let ch = name[i].to_int().unsafe_to_char()
    let allowed =
      ('a' <= ch && ch <= 'z') ||
      ('A' <= ch && ch <= 'Z') ||
      ('0' <= ch && ch <= '9') ||
      ch == '.' ||
      ch == '-' ||
      ch == '_'
    buf.write_char(if allowed { ch } else { '_' })
  }
  buf.to_string()
}
