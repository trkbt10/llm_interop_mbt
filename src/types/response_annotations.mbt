///|
/// Shared helpers for response annotations and the extended interop JSON form.

///|
pub fn ResponseAnnotation::start_index(self : ResponseAnnotation) -> Int {
  match self {
    UrlCitation(start_index~, ..)
    | DocumentCharCitation(start_index~, ..)
    | DocumentPageCitation(start_index~, ..)
    | DocumentContentBlockCitation(start_index~, ..)
    | WebSearchResultCitation(start_index~, ..)
    | SearchResultCitation(start_index~, ..) => start_index
  }
}

///|
pub fn ResponseAnnotation::end_index(self : ResponseAnnotation) -> Int {
  match self {
    UrlCitation(end_index~, ..)
    | DocumentCharCitation(end_index~, ..)
    | DocumentPageCitation(end_index~, ..)
    | DocumentContentBlockCitation(end_index~, ..)
    | WebSearchResultCitation(end_index~, ..)
    | SearchResultCitation(end_index~, ..) => end_index
  }
}

///|
pub fn ResponseAnnotation::to_interop_json(self : ResponseAnnotation) -> Json {
  match self {
    UrlCitation(title~, url~, start_index~, end_index~) => {
      let result : Map[String, Json] = {
        "type": Json::string("url_citation"),
        "url": Json::string(url),
        "start_index": Json::number(start_index.to_double()),
        "end_index": Json::number(end_index.to_double()),
      }
      match title {
        Some(value) => result["title"] = Json::string(value)
        None => ()
      }
      Json::object(result)
    }
    DocumentCharCitation(
      cited_text~,
      document_index~,
      document_title~,
      file_id~,
      start_char_index~,
      end_char_index~,
      start_index~,
      end_index~
    ) =>
      {
        "type": "char_location",
        "cited_text": cited_text,
        "document_index": document_index,
        "document_title": document_title,
        "file_id": file_id,
        "start_char_index": start_char_index,
        "end_char_index": end_char_index,
        "start_index": start_index,
        "end_index": end_index,
      }
    DocumentPageCitation(
      cited_text~,
      document_index~,
      document_title~,
      file_id~,
      start_page_number~,
      end_page_number~,
      start_index~,
      end_index~
    ) =>
      {
        "type": "page_location",
        "cited_text": cited_text,
        "document_index": document_index,
        "document_title": document_title,
        "file_id": file_id,
        "start_page_number": start_page_number,
        "end_page_number": end_page_number,
        "start_index": start_index,
        "end_index": end_index,
      }
    DocumentContentBlockCitation(
      cited_text~,
      document_index~,
      document_title~,
      file_id~,
      start_block_index~,
      end_block_index~,
      start_index~,
      end_index~
    ) =>
      {
        "type": "content_block_location",
        "cited_text": cited_text,
        "document_index": document_index,
        "document_title": document_title,
        "file_id": file_id,
        "start_block_index": start_block_index,
        "end_block_index": end_block_index,
        "start_index": start_index,
        "end_index": end_index,
      }
    WebSearchResultCitation(
      cited_text~,
      encrypted_index~,
      title~,
      url~,
      start_index~,
      end_index~
    ) =>
      {
        "type": "web_search_result_location",
        "cited_text": cited_text,
        "encrypted_index": encrypted_index,
        "title": title,
        "url": url,
        "start_index": start_index,
        "end_index": end_index,
      }
    SearchResultCitation(
      cited_text~,
      search_result_index~,
      source~,
      title~,
      start_block_index~,
      end_block_index~,
      start_index~,
      end_index~
    ) =>
      {
        "type": "search_result_location",
        "cited_text": cited_text,
        "search_result_index": search_result_index,
        "source": source,
        "title": title,
        "start_block_index": start_block_index,
        "end_block_index": end_block_index,
        "start_index": start_index,
        "end_index": end_index,
      }
  }
}

///|
pub fn parse_interop_response_annotation(
  annotation : Json,
) -> ResponseAnnotation {
  match annotation {
    {
      "type": String("url_citation"),
      "url": String(url),
      "start_index": Number(start, ..),
      "end_index": Number(end_, ..),
      ..
    } => {
      let title = match annotation {
        { "title": String(value), .. } => Some(value)
        _ => None
      }
      ResponseAnnotation::url_citation(
        url~,
        start_index=start.to_int(),
        end_index=end_.to_int(),
        title~,
      )
    }
    { "type": String("char_location"), .. } =>
      ResponseAnnotation::document_char_citation(
        cited_text=annotation_required_string(annotation, "cited_text"),
        document_index=annotation_required_int(annotation, "document_index"),
        document_title=annotation_required_string(annotation, "document_title"),
        file_id=annotation_required_string(annotation, "file_id"),
        start_char_index=annotation_required_int(annotation, "start_char_index"),
        end_char_index=annotation_required_int(annotation, "end_char_index"),
        start_index=annotation_required_int(annotation, "start_index"),
        end_index=annotation_required_int(annotation, "end_index"),
      )
    { "type": String("page_location"), .. } =>
      ResponseAnnotation::document_page_citation(
        cited_text=annotation_required_string(annotation, "cited_text"),
        document_index=annotation_required_int(annotation, "document_index"),
        document_title=annotation_required_string(annotation, "document_title"),
        file_id=annotation_required_string(annotation, "file_id"),
        start_page_number=annotation_required_int(
          annotation, "start_page_number",
        ),
        end_page_number=annotation_required_int(annotation, "end_page_number"),
        start_index=annotation_required_int(annotation, "start_index"),
        end_index=annotation_required_int(annotation, "end_index"),
      )
    { "type": String("content_block_location"), .. } =>
      ResponseAnnotation::document_content_block_citation(
        cited_text=annotation_required_string(annotation, "cited_text"),
        document_index=annotation_required_int(annotation, "document_index"),
        document_title=annotation_required_string(annotation, "document_title"),
        file_id=annotation_required_string(annotation, "file_id"),
        start_block_index=annotation_required_int(
          annotation, "start_block_index",
        ),
        end_block_index=annotation_required_int(annotation, "end_block_index"),
        start_index=annotation_required_int(annotation, "start_index"),
        end_index=annotation_required_int(annotation, "end_index"),
      )
    { "type": String("web_search_result_location"), .. } =>
      ResponseAnnotation::web_search_result_citation(
        cited_text=annotation_required_string(annotation, "cited_text"),
        encrypted_index=annotation_required_string(
          annotation, "encrypted_index",
        ),
        title=annotation_required_string(annotation, "title"),
        url=annotation_required_string(annotation, "url"),
        start_index=annotation_required_int(annotation, "start_index"),
        end_index=annotation_required_int(annotation, "end_index"),
      )
    { "type": String("search_result_location"), .. } =>
      ResponseAnnotation::search_result_citation(
        cited_text=annotation_required_string(annotation, "cited_text"),
        search_result_index=annotation_required_int(
          annotation, "search_result_index",
        ),
        source=annotation_required_string(annotation, "source"),
        title=annotation_required_string(annotation, "title"),
        start_block_index=annotation_required_int(
          annotation, "start_block_index",
        ),
        end_block_index=annotation_required_int(annotation, "end_block_index"),
        start_index=annotation_required_int(annotation, "start_index"),
        end_index=annotation_required_int(annotation, "end_index"),
      )
    { "type": String(_), .. } =>
      abort("Unsupported response annotation type: " + annotation.stringify())
    _ =>
      abort(
        "Response annotation must be an object with a supported type: " +
        annotation.stringify(),
      )
  }
}

///|
fn annotation_required_string(annotation : Json, field : String) -> String {
  match annotation {
    Object(fields) =>
      match fields.get(field) {
        Some(String(value)) => value
        _ =>
          abort(
            "Response annotation is missing required string field \{field}: " +
            annotation.stringify(),
          )
      }
    _ =>
      abort(
        "Response annotation must be an object with field \{field}: " +
        annotation.stringify(),
      )
  }
}

///|
fn annotation_required_int(annotation : Json, field : String) -> Int {
  match annotation {
    Object(fields) =>
      match fields.get(field) {
        Some(Number(value, ..)) => value.to_int()
        _ =>
          abort(
            "Response annotation is missing required numeric field \{field}: " +
            annotation.stringify(),
          )
      }
    _ =>
      abort(
        "Response annotation must be an object with field \{field}: " +
        annotation.stringify(),
      )
  }
}
