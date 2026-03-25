///|
/// Shared helpers for Gemini grounding metadata -> interop annotations.

///|
fn collect_gemini_grounding_annotations(
  candidate : Json,
  rendered_text : String,
) -> Array[@types.ResponseAnnotation] {
  let annotations : Array[@types.ResponseAnnotation] = []
  match candidate {
    {
      "groundingMetadata": {
        "groundingSupports": Array(supports),
        "groundingChunks": Array(chunks),
        ..
      },
      ..
    } => {
      let mut search_start = 0
      for support in supports {
        match
          resolve_gemini_grounding_segment(rendered_text, support, search_start) {
          Some((segment_text, start_index, end_index)) => {
            for chunk_index in gemini_grounding_chunk_indices(support) {
              match chunks.get(chunk_index) {
                Some(chunk) => {
                  let annotation = @types.ResponseAnnotation::gemini_grounding_citation(
                    chunk_index~,
                    chunk~,
                    support~,
                    cited_text=segment_text,
                    start_index~,
                    end_index~,
                  )
                  if not(annotations.contains(annotation)) {
                    annotations.push(annotation)
                  }
                }
                None => ()
              }
            }
            if segment_text.length() > 0 {
              search_start = end_index
            }
          }
          None => ()
        }
      }
    }
    _ => ()
  }
  annotations
}

///|
fn resolve_gemini_grounding_segment(
  rendered_text : String,
  support : Json,
  search_start : Int,
) -> (String, Int, Int)? {
  let segment_text = match support {
    { "segment": { "text": String(text), .. }, .. } => text
    _ => ""
  }
  if segment_text.length() > 0 {
    match @utils.find_substr(rendered_text, segment_text, search_start) {
      Some(index) => Some((segment_text, index, index + segment_text.length()))
      None =>
        match @utils.find_substr(rendered_text, segment_text, 0) {
          Some(index) =>
            Some((segment_text, index, index + segment_text.length()))
          None => None
        }
    }
  } else {
    match support {
      {
        "segment": {
          "startIndex": Number(start_index, ..),
          "endIndex": Number(end_index, ..),
          ..
        },
        ..
      } => {
        let start = start_index.to_int()
        let end_ = end_index.to_int()
        if start >= 0 && end_ >= start && end_ <= rendered_text.length() {
          Some(("", start, end_))
        } else {
          None
        }
      }
      _ => None
    }
  }
}

///|
fn gemini_grounding_chunk_indices(support : Json) -> Array[Int] {
  match support {
    { "groundingChunkIndices": Array(indices), .. } => {
      let result : Array[Int] = []
      for index in indices {
        match index {
          Number(value, ..) => result.push(value.to_int())
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
fn response_annotations_to_grounding_metadata(
  annotations : Array[@types.ResponseAnnotation],
  rendered_text : String,
) -> Json? {
  let chunks : Array[Json] = []
  let supports : Array[Json] = []
  for annotation in annotations {
    match
      grounding_entry_from_response_annotation(
        annotation,
        rendered_text,
        chunks.length(),
      ) {
      Some((chunk, support)) => {
        chunks.push(chunk)
        supports.push(support)
      }
      None =>
        abort(
          "Gemini grounding bridge cannot represent response annotation without loss: " +
          annotation.to_interop_json().stringify(),
        )
    }
  }
  if chunks.length() == 0 {
    None
  } else {
    Some({
      "groundingChunks": Json::array(chunks),
      "groundingSupports": Json::array(supports),
    })
  }
}

///|
fn grounding_entry_from_response_annotation(
  annotation : @types.ResponseAnnotation,
  rendered_text : String,
  chunk_index : Int,
) -> (Json, Json)? {
  match annotation {
    @types.ResponseAnnotation::UrlCitation(
      title~,
      url~,
      start_index~,
      end_index~
    ) =>
      Some(
        (
          build_web_grounding_chunk(url, title),
          build_grounding_support(
            chunk_index, rendered_text, "", start_index, end_index,
          ),
        ),
      )
    @types.ResponseAnnotation::WebSearchResultCitation(
      cited_text~,
      title~,
      url~,
      start_index~,
      end_index~,
      ..
    ) =>
      Some(
        (
          build_web_grounding_chunk(url, Some(title)),
          build_grounding_support(
            chunk_index, rendered_text, cited_text, start_index, end_index,
          ),
        ),
      )
    @types.ResponseAnnotation::GeminiGroundingCitation(
      chunk~,
      cited_text~,
      start_index~,
      end_index~,
      ..
    ) =>
      Some(
        (
          chunk,
          build_grounding_support(
            chunk_index, rendered_text, cited_text, start_index, end_index,
          ),
        ),
      )
    _ => None
  }
}

///|
fn build_web_grounding_chunk(url : String, title : String?) -> Json {
  let web : Map[String, Json] = { "uri": Json::string(url) }
  match title {
    Some(value) if value.length() > 0 => web["title"] = Json::string(value)
    _ => ()
  }
  { "web": Json::object(web) }
}

///|
fn build_grounding_support(
  chunk_index : Int,
  rendered_text : String,
  fallback_text : String,
  start_index : Int,
  end_index : Int,
) -> Json {
  {
    "groundingChunkIndices": Json::array([Json::number(chunk_index.to_double())]),
    "segment": {
      "text": grounding_segment_text(
        rendered_text, fallback_text, start_index, end_index,
      ),
      "startIndex": start_index,
      "endIndex": end_index,
    },
  }
}

///|
fn grounding_segment_text(
  rendered_text : String,
  fallback_text : String,
  start_index : Int,
  end_index : Int,
) -> String {
  if start_index >= 0 &&
    end_index >= start_index &&
    end_index <= rendered_text.length() {
    let buf = StringBuilder::new()
    for i = start_index; i < end_index; i = i + 1 {
      buf.write_char(rendered_text[i].to_int().unsafe_to_char())
    }
    buf.to_string()
  } else {
    fallback_text
  }
}
