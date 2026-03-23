///|
/// JSON Schema normalizer for OpenAI API compatibility
///
/// Normalizes JSON Schema to meet OpenAI's strict mode requirements:
/// 1. All properties must be in the required array
/// 2. Remove uri format (OpenAI doesn't support it)
/// 3. Set additionalProperties to false for all objects

///|
/// Normalize a JSON Schema for OpenAI strict mode compatibility
/// - Adds all properties to required array for object schemas
/// - Removes uri format from string properties
/// - Sets additionalProperties to false for object schemas
pub fn normalize_json_schema_for_openai(schema : Json) -> Json {
  @types.normalize_json_schema_for_openai(schema)
}

///|
/// Recursively normalize a schema
pub fn schema_needs_normalization(schema : Json) -> Bool {
  @types.schema_needs_normalization(schema)
}
