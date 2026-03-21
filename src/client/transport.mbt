///|
/// HTTP transport abstraction for LLM client.
/// Allows host runtimes (e.g., mukuro's NativeHttpClient) to inject their own HTTP implementation.

///|
/// Transport-level errors — raised by HttpTransport implementations.
/// Intentionally separate from ClientError so external packages can construct them freely.
pub suberror TransportError {
  NetworkError(String)
  TimeoutError
} derive(Show)

///|
pub(all) struct TransportRequest {
  url : String
  http_method : String
  headers : Map[String, String]
  body : String?
}

///|
pub(all) struct TransportResponse {
  status : Int
  body : String
}

///|
/// HTTP transport trait — implemented by host runtimes.
/// Raises TransportError (not ClientError) so implementations don't depend on client internals.
pub(open) trait HttpTransport {
  async request(Self, TransportRequest) -> TransportResponse raise TransportError
}

///|
/// Factory: create a NetworkError for external packages implementing HttpTransport
pub fn transport_network_error(message : String) -> TransportError {
  NetworkError(message)
}

///|
/// Factory: create a TimeoutError for external packages implementing HttpTransport
pub fn transport_timeout_error() -> TransportError {
  TimeoutError
}
