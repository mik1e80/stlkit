// SPDX-License-Identifier: Apache-2.0

///|
test "web resource settings apply to analyze preview and repair exports" {
  let encoded = @base64.encode(b"v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
  assert_eq(configure_limits(1, 1), "")
  assert_true(
    analyze_error(encoded).contains("resource_limit: max_input_bytes"),
  )
  assert_eq(analyze(encoded), "")
  assert_eq(preview(encoded), "")
  assert_eq(fixed_stl(encoded), "")
  assert_true(fix_error(encoded).contains("resource_limit:"))
  assert_true(configure_limits(-1, 1) != "")
  assert_true(analyze_error(encoded).contains("resource_limit:"))
  assert_eq(configure_limits(16777216, 500000), "")
  assert_true(analyze(encoded) != "")
}
