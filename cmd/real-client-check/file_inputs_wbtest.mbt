test "openai file upload body encodes purpose and file payload" {
  let body = build_openai_file_upload_body(
    "boundary-1",
    "company.txt",
    "text/plain",
    "Berkshire Hathaway",
  )
  assert_true(body.contains("name=\"purpose\""))
  assert_true(body.contains("\r\n\r\nuser_data\r\n"))
  assert_true(body.contains("filename=\"company.txt\""))
  assert_true(body.contains("Content-Type: text/plain"))
  assert_true(body.contains("Berkshire Hathaway"))
}

///|
test "file input message helpers keep document and file ref carriers distinct" {
  match file_data_messages() {
    [
      @types.ModelMessage::User(content_parts=Some(parts), ..),
    ] => {
      assert_eq(parts.length(), 2)
      assert_true(parts[1] is @types.ContentPart::Document(..))
    }
    _ => fail("Expected file_data message")
  }
  match file_id_messages("file_123") {
    [
      @types.ModelMessage::User(content_parts=Some(parts), ..),
    ] => {
      assert_eq(parts.length(), 2)
      assert_true(parts[1] is @types.ContentPart::FileRef(..))
    }
    _ => fail("Expected file_id message")
  }
}
