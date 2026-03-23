///|
/// Whitebox coverage for transform_context helper negatives

///|
test "helper fields return None for non-object and mismatched types" {
  assert_eq(object_bool_field(Json::string("oops"), "strict"), None)
  assert_eq(object_bool_field({ "strict": "false" }, "strict"), None)
  assert_eq(object_json_field(Json::string("oops"), "schema"), None)
}
