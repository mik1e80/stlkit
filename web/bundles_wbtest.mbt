// SPDX-License-Identifier: Apache-2.0

///|
fn bundle_fields(text : String) -> Map[String, Json] raise {
  guard @json.parse(text) is Object(fields) else { fail("expected bundle") }
  fields
}

///|
fn bundle_tetrahedron() -> String {
  @base64.encode(
    b"v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 2 3 4\n",
  )
}

///|
test "bundle analysis uses one parse and shares preview" {
  let fields = bundle_fields(analyze_bundle(bundle_tetrahedron(), 0.0))
  assert_eq(fields.get("ok"), Some(Json(true)))
  guard fields.get("work") is Some(Object(work)) else {
    fail("missing work counts")
  }
  assert_eq(work.get("parses"), Some(Json(1)))
  assert_eq(work.get("repairs"), Some(Json(0)))
  assert_eq(work.get("exports"), Some(Json(0)))
  assert_eq(work.get("reviews"), Some(Json(1)))
  guard fields.get("svg") is Some(String(svg)) else { fail("missing preview") }
  assert_true(svg.contains("<svg"))
}

///|
test "fix bundle repairs and exports once then rereads actual output once" {
  let fields = bundle_fields(fix_bundle(bundle_tetrahedron(), 0.0))
  assert_eq(fields.get("ok"), Some(Json(true)))
  guard fields.get("work") is Some(Object(work)) else {
    fail("missing work counts")
  }
  assert_eq(work.get("parses"), Some(Json(2)))
  assert_eq(work.get("repairs"), Some(Json(1)))
  assert_eq(work.get("exports"), Some(Json(1)))
  assert_eq(work.get("reviews"), Some(Json(1)))
  guard fields.get("stl_base64") is Some(String(encoded)) else {
    fail("missing actual STL")
  }
  let bytes = @base64.decode(encoded)
  assert_eq(@stlkit.parse_mesh(bytes).unwrap().triangle_count(), 4)
  guard fields.get("report") is Some(String(report)) else {
    fail("missing final report")
  }
  assert_true(report.contains("三角形|4"))
  assert_true(report.contains("边界边|0"))
}

///|
test "bundle reports errors and distinguishes unavailable preview" {
  assert_eq(
    bundle_fields(analyze_bundle("?", 0.0)).get("ok"),
    Some(Json(false)),
  )
  assert_eq(
    bundle_fields(fix_bundle(bundle_tetrahedron(), -1.0)).get("ok"),
    Some(Json(false)),
  )
  let extreme = @base64.encode(
    b"v -1e308 0 0\nv 1e308 0 0\nv 0 1e-308 0\nf 1 2 3\n",
  )
  let fields = bundle_fields(analyze_bundle(extreme, 0.0))
  assert_eq(fields.get("ok"), Some(Json(true)))
  assert_eq(fields.get("svg"), Some(Json("")))
  guard fields.get("preview_error") is Some(String(error)) else {
    fail("missing refusal reason")
  }
  assert_true(error.contains("not representable"))
  assert_eq(preview(extreme), "")
}

///|
test "browser caps cannot be raised to CLI limits" {
  assert_true(configure_limits(33554433, 500000) != "")
  assert_true(configure_limits(33554432, 500001) != "")
  assert_eq(configure_limits(33554432, 500000), "")
  assert_eq(configure_limits(16777216, 500000), "")
}
