///|
/// Provider-native structured-output config captured during request parsing.
///
/// The normalized `ResponseFormat` enum is the cross-provider intent layer.
/// This sidecar preserves the exact wire-level shape when a provider has extra
/// schema semantics or field names that the shared enum cannot express.
pub(all) struct ResponseFormatContext {
  surface : String
  raw : Json
}
