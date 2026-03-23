///|
/// CLI options for the real-provider verification harness.

///|
struct CliOptions {
  help : Bool
  list : Bool
  filters : Array[String]
  fixtures_dir : String?
}

///|
fn CliOptions::default() -> CliOptions {
  let filters : Array[String] = []
  push_filter_values(filters, @sys.get_env_var("REALCHECK_FILTER").unwrap_or(""))
  {
    help: false,
    list: false,
    filters,
    fixtures_dir: match @sys.get_env_var("REALCHECK_FIXTURE_DIR") {
      Some(path) if path != "" => Some(path)
      _ => None
    },
  }
}

///|
fn parse_real_client_check_args(args : Array[String]) -> CliOptions {
  let opts = CliOptions::default()
  let start = if args.length() > 0 { 1 } else { 0 }
  parse_real_client_check_args_from(args, start, opts)
}

///|
fn parse_real_client_check_args_from(
  args : Array[String],
  start : Int,
  opts : CliOptions,
) -> CliOptions {
  let mut result = opts
  let mut i = start
  while i < args.length() {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      result = { ..result, help: true }
    } else if arg == "--list" {
      result = { ..result, list: true }
    } else if arg == "--filter" || arg == "-f" {
      i = i + 1
      if i < args.length() {
        push_filter_values(result.filters, args[i])
      }
    } else if arg == "--fixtures-dir" || arg == "--save-fixtures" {
      i = i + 1
      if i < args.length() && args[i] != "" {
        result = { ..result, fixtures_dir: Some(args[i]) }
      }
    }
    i = i + 1
  }
  result
}

///|
fn push_filter_values(filters : Array[String], raw : String) -> Unit {
  if raw == "" {
    return
  }
  for item in raw.split(",").map(StringView::to_string).collect() {
    let normalized = item.trim(chars=" \n\r\t").to_string()
    if normalized != "" && not(filters.contains(normalized)) {
      filters.push(normalized)
    }
  }
}

///|
fn register_checks(registry : Array[String], names : Array[String]) -> Unit {
  for name in names {
    if not(registry.contains(name)) {
      registry.push(name)
    }
  }
}

///|
fn should_run_check(opts : CliOptions, name : String) -> Bool {
  if opts.filters.length() == 0 {
    return true
  }
  for filter in opts.filters {
    if filter == name || name.has_prefix(filter) || name.contains(filter) {
      return true
    }
  }
  false
}

///|
fn any_selected_check(opts : CliOptions, names : Array[String]) -> Bool {
  if opts.filters.length() == 0 {
    return true
  }
  for name in names {
    if should_run_check(opts, name) {
      return true
    }
  }
  false
}

///|
fn selected_check_count(opts : CliOptions, names : Array[String]) -> Int {
  let mut count = 0
  for name in names {
    if should_run_check(opts, name) {
      count += 1
    }
  }
  count
}

///|
fn print_available_checks(names : Array[String]) -> Unit {
  println("available real-client-check cases:")
  for name in names {
    println("  " + name)
  }
}

///|
fn print_real_client_check_help() -> Unit {
  println(
    "Real provider check harness\n\nUsage: real-client-check [options]\n\nOptions:\n  -f, --filter <expr>      Run only checks whose names match the filter (repeatable, comma-separated)\n      --list               List available check names and exit\n      --fixtures-dir <dir> Save successful check reports as JSON fixtures in <dir>\n  -h, --help               Show this help message\n\nEnvironment:\n  REALCHECK_FILTER         Default filter when --filter is omitted\n  REALCHECK_FIXTURE_DIR    Default fixture output directory",
  )
}
