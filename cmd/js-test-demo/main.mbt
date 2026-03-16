///|
/// JS target demo application

///|
let demo_model : String = "gpt-4.1-mini"

///|
fn demo_messages() -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::System(
      "You are a concise assistant for JavaScript-target smoke tests.",
    ),
    @types.ModelMessage::User(
      content="Tell me whether the weather in Tokyo needs a jacket today.",
      name=None,
    ),
  ]
}

///|
fn demo_tools() -> Array[@types.ToolDefinition] {
  let weather_schema = @types.build_json_schema(
    type_="object",
    properties={
      "city": { "type": "string", "description": "City name" },
      "unit": {
        "type": "string",
        "enum": Json::array([
          Json::string("celsius"),
          Json::string("fahrenheit"),
        ]),
      },
    },
    required=["city"],
  )
  [
    @types.ToolDefinition::new(
      name="get_weather",
      description="Look up the current weather.",
      parameters=weather_schema,
    ),
    @types.ToolDefinition::web_search_preview(
      search_context_size=Some("medium"),
      user_location_country=Some("JP"),
    ),
  ]
}

///|
fn build_demo_request() -> Json {
  @protocol.build_responses_api_body(demo_model, demo_messages(), demo_tools())
}

///|
fn summarize_demo_request(body : Json) -> String {
  match body {
    { "model": String(model), "input": Array(input), "tools": Array(tools), .. } =>
      "model=\{model}, input=\{input.length()}, tools=\{tools.length()}"
    _ => "unexpected request payload"
  }
}

///|
fn render_demo_output() -> String {
  let body = build_demo_request()
  "JS target test demo\nsummary: \{summarize_demo_request(body)}\nbody:\n\{body.stringify()}"
}

///|
fn main {
  println(render_demo_output())
}
