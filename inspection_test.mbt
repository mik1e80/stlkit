// SPDX-License-Identifier: Apache-2.0

///|
test "public checked parser and machine report are additive" {
  let mesh = @stlkit.parse_mesh_checked(b"v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").unwrap()
  assert_eq(mesh.triangle_count(), 1)
  let report = @stlkit.inspection_json(mesh, format=@stlkit.Obj, samples=1).unwrap()
  assert_true(report.stringify().contains("\"schema_version\":1"))
  assert_eq(@stlkit.Obj.id(), "obj")
  guard @stlkit.parse_mesh_checked(b"invalid") is Err(error) else {
    fail("expected error")
  }
  assert_eq(error.code(), "unknown_format")
  assert_true(error.message().length() > 0)
}
