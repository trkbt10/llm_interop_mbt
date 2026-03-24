async fn main {
  let opts = parse_real_client_check_args(@sys.get_cli_args())
  if opts.help {
    print_real_client_check_help()
    return
  }
  let declared : Array[String] = []
  let reports : Array[CheckReport] = []
  let failures : Array[String] = []
  if not(opts.list) {
    println("real client check starting")
  }
  run_openai_checks(opts, declared, reports, failures)
  run_anthropic_check(opts, declared, reports, failures)
  run_gemini_check(opts, declared, reports, failures)
  run_groq_check(opts, declared, reports, failures)
  if opts.list {
    print_available_checks(declared)
    return
  }
  if selected_check_count(opts, declared) == 0 {
    print_failure("real-client-check", "no checks matched the current filter")
    @sys.exit(1)
  }
  println(
    "real client check finished: ok=\{reports.length()} fail=\{failures.length()}",
  )
  if failures.length() > 0 {
    @sys.exit(1)
  }
}
