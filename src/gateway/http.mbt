///|
/// HTTP response types and helpers

///|
/// HTTP response
pub(all) struct HttpResponse {
  status : Int
  headers : Map[String, String]
  body : String
} derive(Show)

///|
/// Create a JSON response with the given status code and body.
pub fn HttpResponse::json(status : Int, body : Json) -> HttpResponse {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  { status, headers, body: body.stringify() }
}

///|
/// Create an error JSON response with the given status code and message.
pub fn HttpResponse::error(status : Int, message : String) -> HttpResponse {
  HttpResponse::json(status, { "error": { "message": message } })
}

///|
/// Create a 200 OK JSON response with the given body.
pub fn HttpResponse::ok(body : Json) -> HttpResponse {
  HttpResponse::json(200, body)
}

///|
/// Result of handling an HTTP request
pub(all) enum HandleResult {
  /// Non-streaming: caller writes response to connection
  Response(HttpResponse)
  /// Streaming: handler already wrote SSE events to connection
  Streamed
}

///|
/// Set CORS headers on a header map
pub fn set_cors_headers(headers : Map[String, String]) -> Unit {
  headers["Access-Control-Allow-Origin"] = "*"
  headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
  headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
}

///|
/// Add CORS headers to an HttpResponse
pub fn add_cors_headers(resp : HttpResponse) -> HttpResponse {
  set_cors_headers(resp.headers)
  resp
}
