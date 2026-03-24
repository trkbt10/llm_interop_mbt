///|
/// Shared parsing for Anthropic text/document citations.

///|
fn append_anthropic_text_block_annotations(
  target : Array[@types.ResponseAnnotation],
  block : Json,
  start_index : Int,
  end_index : Int,
) -> Unit {
  match block {
    { "citations": Array(citations), .. } =>
      append_anthropic_citations(target, citations, start_index, end_index)
    _ => ()
  }
}

///|
fn append_anthropic_citation(
  target : Array[@types.ResponseAnnotation],
  citation : Json,
  start_index : Int,
  end_index : Int,
) -> Unit {
  let annotation = parse_anthropic_citation(citation, start_index, end_index)
  if not(target.contains(annotation)) {
    target.push(annotation)
  }
}

///|
fn append_anthropic_citations(
  target : Array[@types.ResponseAnnotation],
  citations : Array[Json],
  start_index : Int,
  end_index : Int,
) -> Unit {
  for citation in citations {
    append_anthropic_citation(target, citation, start_index, end_index)
  }
}

///|
fn parse_anthropic_citation(
  citation : Json,
  start_index : Int,
  end_index : Int,
) -> @types.ResponseAnnotation {
  match citation {
    { "type": String("char_location"), .. } =>
      @types.ResponseAnnotation::document_char_citation(
        cited_text=anthropic_citation_required_string(citation, "cited_text"),
        document_index=anthropic_citation_required_int(
          citation, "document_index",
        ),
        document_title=anthropic_citation_required_string(
          citation, "document_title",
        ),
        file_id=anthropic_citation_required_string(citation, "file_id"),
        start_char_index=anthropic_citation_required_int(
          citation, "start_char_index",
        ),
        end_char_index=anthropic_citation_required_int(
          citation, "end_char_index",
        ),
        start_index~,
        end_index~,
      )
    { "type": String("page_location"), .. } =>
      @types.ResponseAnnotation::document_page_citation(
        cited_text=anthropic_citation_required_string(citation, "cited_text"),
        document_index=anthropic_citation_required_int(
          citation, "document_index",
        ),
        document_title=anthropic_citation_required_string(
          citation, "document_title",
        ),
        file_id=anthropic_citation_required_string(citation, "file_id"),
        start_page_number=anthropic_citation_required_int(
          citation, "start_page_number",
        ),
        end_page_number=anthropic_citation_required_int(
          citation, "end_page_number",
        ),
        start_index~,
        end_index~,
      )
    { "type": String("content_block_location"), .. } =>
      @types.ResponseAnnotation::document_content_block_citation(
        cited_text=anthropic_citation_required_string(citation, "cited_text"),
        document_index=anthropic_citation_required_int(
          citation, "document_index",
        ),
        document_title=anthropic_citation_required_string(
          citation, "document_title",
        ),
        file_id=anthropic_citation_required_string(citation, "file_id"),
        start_block_index=anthropic_citation_required_int(
          citation, "start_block_index",
        ),
        end_block_index=anthropic_citation_required_int(
          citation, "end_block_index",
        ),
        start_index~,
        end_index~,
      )
    { "type": String("web_search_result_location"), .. } =>
      @types.ResponseAnnotation::web_search_result_citation(
        cited_text=anthropic_citation_required_string(citation, "cited_text"),
        encrypted_index=anthropic_citation_required_string(
          citation, "encrypted_index",
        ),
        title=anthropic_citation_required_string(citation, "title"),
        url=anthropic_citation_required_string(citation, "url"),
        start_index~,
        end_index~,
      )
    { "type": String("search_result_location"), .. } =>
      @types.ResponseAnnotation::search_result_citation(
        cited_text=anthropic_citation_required_string(citation, "cited_text"),
        search_result_index=anthropic_citation_required_int(
          citation, "search_result_index",
        ),
        source=anthropic_citation_required_string(citation, "source"),
        title=anthropic_citation_required_string(citation, "title"),
        start_block_index=anthropic_citation_required_int(
          citation, "start_block_index",
        ),
        end_block_index=anthropic_citation_required_int(
          citation, "end_block_index",
        ),
        start_index~,
        end_index~,
      )
    { "type": String(_), .. } =>
      abort("Unsupported Anthropic citation type: " + citation.stringify())
    _ =>
      abort(
        "Anthropic citation must be an object with a supported type: " +
        citation.stringify(),
      )
  }
}

///|
fn anthropic_citation_required_string(
  citation : Json,
  field : String,
) -> String {
  match citation {
    Object(fields) =>
      match fields.get(field) {
        Some(String(value)) => value
        _ =>
          abort(
            "Anthropic citation is missing required string field \{field}: " +
            citation.stringify(),
          )
      }
    _ =>
      abort(
        "Anthropic citation must be an object with field \{field}: " +
        citation.stringify(),
      )
  }
}

///|
fn anthropic_citation_required_int(citation : Json, field : String) -> Int {
  match citation {
    Object(fields) =>
      match fields.get(field) {
        Some(Number(value, ..)) => value.to_int()
        _ =>
          abort(
            "Anthropic citation is missing required numeric field \{field}: " +
            citation.stringify(),
          )
      }
    _ =>
      abort(
        "Anthropic citation must be an object with field \{field}: " +
        citation.stringify(),
      )
  }
}
