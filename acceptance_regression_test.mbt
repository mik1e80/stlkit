// SPDX-License-Identifier: Apache-2.0

///|
test "checked export and numeric guard are usable through public API" {
  let source = "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n"
  let mesh = @stlkit.parse_obj(source).unwrap()
  assert_true(mesh.mass_properties_numeric_valid())
  let bytes = @stlkit.write_stl_binary_checked(mesh).unwrap()
  assert_eq(@stlkit.parse_mesh(bytes).unwrap().triangle_count(), 4)
}
