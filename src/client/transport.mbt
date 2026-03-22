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
/// Streaming response — status code + chunk-by-chunk reader.
pub(all) struct StreamingResponse {
  status : Int
  reader : &StreamReader
}

///|
/// HTTP transport trait — full request-response.
/// Implemented by host runtimes.
pub(open) trait HttpTransport {
  async request(Self, TransportRequest) -> TransportResponse raise TransportError
}

///|
/// Streaming HTTP transport trait — returns a reader for chunked response.
/// Host runtimes implement this to support SSE streaming from LLM backends.
pub(open) trait StreamingHttpTransport {
  async request_stream(Self, TransportRequest) -> StreamingResponse raise TransportError
}

///|
/// Reads chunks of response body. Returns None on EOF.
pub(open) trait StreamReader {
  async read(Self) -> Bytes? raise TransportError
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

///|
/// Decode bytes to string, returning empty string on decode failure.
fn bytes_to_string_lossy(bytes : Bytes) -> String {
  @utf8.decode(bytes[:]) catch {
    _ => ""
  }
}

///|
/// Read all remaining data from a stream reader into a string.
async fn read_all_from_stream(reader : &StreamReader) -> String {
  let buf = StringBuilder::new()
  while true {
    let chunk = reader.read() catch { _ => break }
    match chunk {
      None => break
      Some(bytes) => buf.write_string(bytes_to_string_lossy(bytes))
    }
  }
  buf.to_string()
}
