///|
/// Structured response format requested from the model.
pub(all) enum ResponseFormat {
  /// Default plain-text output.
  Text
  /// Legacy JSON mode without an explicit schema.
  JsonObject
  /// Structured JSON output constrained by a schema.
  JsonSchema(
    name~ : String?,
    schema~ : Json,
    description~ : String?,
    strict~ : Bool?
  )
} derive(Show, Eq)
