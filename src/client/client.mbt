///|
/// LLM API Client — gateway-based, all ModelApi providers via HttpTransport

///|
pub suberror ClientError {
  HttpError(String)
  ParseError(String)
  ApiError(code~ : Int, message~ : String)
} derive(Show)
