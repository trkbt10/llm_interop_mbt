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
pub fn HttpResponse::json(status : Int, body : Json) -> HttpResponse {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  { status, headers, body: body.stringify() }
}

///|
pub fn HttpResponse::error(status : Int, message : String) -> HttpResponse {
  HttpResponse::json(status, { "error": { "message": message } })
}

///|
pub fn HttpResponse::ok(body : Json) -> HttpResponse {
  HttpResponse::json(200, body)
}

///|
/// Add CORS headers
pub fn add_cors_headers(resp : HttpResponse) -> HttpResponse {
  resp.headers["Access-Control-Allow-Origin"] = "*"
  resp.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
  resp.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
  resp
}
