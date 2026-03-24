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
              match gemini_grounding_chunk_url_title(chunks, chunk_index) {
                Some((url, title)) => {
                  let annotation = @types.ResponseAnnotation::url_citation(
                    url~,
                    title~,
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
fn gemini_grounding_chunk_url_title(
  chunks : Array[Json],
  index : Int,
) -> (String, String?)? {
  match chunks.get(index) {
    Some(chunk) =>
      match chunk {
        { "web": { "uri": String(url), .. }, .. } => {
          let title = match chunk {
            { "web": { "title": String(value), .. }, .. } => Some(value)
            _ => None
          }
          Some((url, title))
        }
        { "retrievedContext": { "uri": String(url), .. }, .. } => {
          let title = match chunk {
            { "retrievedContext": { "title": String(value), .. }, .. } =>
              Some(value)
            _ => None
          }
          Some((url, title))
        }
        { "maps": { "uri": String(url), .. }, .. } => {
          let title = match chunk {
            { "maps": { "title": String(value), .. }, .. } => Some(value)
            _ => None
          }
          Some((url, title))
        }
        { "image": { "sourceUri": String(url), .. }, .. } => {
          let title = match chunk {
            { "image": { "title": String(value), .. }, .. } => Some(value)
            _ => None
          }
          Some((url, title))
        }
        _ => None
      }
    None => None
  }
}
