///|
/// Shared support for the real-provider verification harness.
///
/// This command uses the public client entry points with a native HTTP transport
/// and sends actual upstream requests. It is intentionally separate from the
/// library test suite because it requires network access and provider API keys.

///|
let request_timeout_ms : Int = 60000

///|
let expected_url : String = "https://example.com/interop-check"

///|
let expected_company : String = "Berkshire Hathaway"

///|
let expected_file_url : String =
  "https://www.berkshirehathaway.com/letters/2024ltr.pdf"

///|
let expected_inline_file_name : String = "company.txt"

///|
let expected_inline_file_text : String = "Berkshire Hathaway"

///|
let expected_inline_file_base64 : String = "QmVya3NoaXJlIEhhdGhhd2F5"

///|
let expected_pdf_file_name : String = "company.pdf"

///|
let expected_pdf_file_content : String =
  "%PDF-1.4\n" +
  "1 0 obj\n" +
  "<< /Type /Catalog /Pages 2 0 R >>\n" +
  "endobj\n" +
  "2 0 obj\n" +
  "<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n" +
  "endobj\n" +
  "3 0 obj\n" +
  "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\n" +
  "endobj\n" +
  "4 0 obj\n" +
  "<< /Length 52 >>\n" +
  "stream\n" +
  "BT\n" +
  "/F1 18 Tf\n" +
  "72 96 Td\n" +
  "(Berkshire Hathaway) Tj\n" +
  "ET\n" +
  "endstream\n" +
  "endobj\n" +
  "5 0 obj\n" +
  "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\n" +
  "endobj\n" +
  "xref\n" +
  "0 6\n" +
  "0000000000 65535 f \n" +
  "0000000009 00000 n \n" +
  "0000000058 00000 n \n" +
  "0000000115 00000 n \n" +
  "0000000241 00000 n \n" +
  "0000000343 00000 n \n" +
  "trailer\n" +
  "<< /Root 1 0 R /Size 6 >>\n" +
  "startxref\n" +
  "413\n" +
  "%%EOF\n"

///|
let expected_pdf_file_base64 : String =
  "JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCAzMDAgMTQ0XSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA1MiA+PgpzdHJlYW0KQlQKL0YxIDE4IFRmCjcyIDk2IFRkCihCZXJrc2hpcmUgSGF0aGF3YXkpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAvVHlwZTEgL0Jhc2VGb250IC9IZWx2ZXRpY2EgPj4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI0MSAwMDAwMCBuIAowMDAwMDAwMzQzIDAwMDAwIG4gCnRyYWlsZXIKPDwgL1Jvb3QgMSAwIFIgL1NpemUgNiA+PgpzdGFydHhyZWYKNDEzCiUlRU9GCg=="

///|
struct FileFixture {
  filename : String
  media_type : String
  raw_content : String
  base64_data : String
}

///|
fn text_file_fixture() -> FileFixture {
  {
    filename: expected_inline_file_name,
    media_type: "text/plain",
    raw_content: expected_inline_file_text,
    base64_data: expected_inline_file_base64,
  }
}

///|
fn pdf_file_fixture() -> FileFixture {
  {
    filename: expected_pdf_file_name,
    media_type: "application/pdf",
    raw_content: expected_pdf_file_content,
    base64_data: expected_pdf_file_base64,
  }
}

///|
fn expected_tool_url(label : String) -> String {
  expected_url + "/" + label
}

///|
suberror LiveCheckError {
  ModelUnavailable(String)
  ValidationFailed(String)
} derive(Show)

///|
struct NativeHttpTransport {
  mut last_url : String
  mut last_body : String
  mut last_response_body : String
}

///|
fn NativeHttpTransport::new() -> NativeHttpTransport {
  { last_url: "", last_body: "", last_response_body: "" }
}

///|
impl @client.HttpTransport for NativeHttpTransport with request(self, req) {
  self.last_url = sanitize_url(req.url)
  self.last_body = req.body.unwrap_or("")
  let body = req.body.unwrap_or("")
  let (response, data) = @async.with_timeout(request_timeout_ms, () => {
    @http.post(req.url, body, headers=req.headers)
  }) catch {
    @async.TimeoutError => raise @client.transport_timeout_error()
    err => raise @client.transport_network_error(err.to_string())
  }
  let text = data.text() catch { _ => "" }
  self.last_response_body = text
  { status: response.code, body: text }
}

///|
struct NativeStreamReader {
  client : @http.Client
  mut closed : Bool
}

///|
fn NativeStreamReader::new(client : @http.Client) -> NativeStreamReader {
  { client, closed: false }
}

///|
impl @client.StreamReader for NativeStreamReader with read(self) {
  if self.closed {
    return None
  }
  let chunk = @async.with_timeout(request_timeout_ms, () => {
    self.client.read_some(max_len=4096)
  }) catch {
    @async.TimeoutError => {
      self.client.close()
      self.closed = true
      raise @client.transport_timeout_error()
    }
    err => {
      self.client.close()
      self.closed = true
      raise @client.transport_network_error(err.to_string())
    }
  }
  match chunk {
    None => {
      self.client.close()
      self.closed = true
      None
    }
    Some(bytes) => Some(bytes)
  }
}

///|
struct NativeStreamingTransport {
  mut last_url : String
  mut last_body : String
}

///|
fn NativeStreamingTransport::new() -> NativeStreamingTransport {
  { last_url: "", last_body: "" }
}

///|
impl @client.StreamingHttpTransport for NativeStreamingTransport with request_stream(
  self,
  req,
) {
  self.last_url = sanitize_url(req.url)
  self.last_body = req.body.unwrap_or("")
  let client = @async.with_timeout(request_timeout_ms, () => {
    @http.post_stream(req.url, headers=req.headers)
  }) catch {
    @async.TimeoutError => raise @client.transport_timeout_error()
    err => raise @client.transport_network_error(err.to_string())
  }
  let body = req.body.unwrap_or("")
  let response = @async.with_timeout(request_timeout_ms, () => {
    if body != "" {
      client.write(body)
      client.flush()
    }
    client.end_request()
  }) catch {
    @async.TimeoutError => {
      client.close()
      raise @client.transport_timeout_error()
    }
    err => {
      client.close()
      raise @client.transport_network_error(err.to_string())
    }
  }
  let reader = NativeStreamReader::new(client)
  { status: response.code, reader }
}

///|
struct ExtractedToolCall {
  call : @types.ToolCallRequest
  assistant_content : String
}

///|
fn env(name : String) -> String {
  @sys.get_env_var(name).unwrap_or("")
}

///|
fn sanitize_url(url : String) -> String {
  guard url.find("key=") is Some(start) else { return url }
  let prefix = url[:start + 4].to_string()
  let rest = url[start + 4:]
  match rest.find("&") {
    Some(end) => prefix + "***" + rest[end:].to_string()
    None => prefix + "***"
  }
}

///|
