// SPDX-License-Identifier: Apache-2.0

///|
test "public resource budgets preserve existing caller and bound output" {
  let text = "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
  let mesh = @stlkit.parse_obj(text).unwrap()
  assert_eq(mesh.triangle_count(), 1)
  let limits = { ..@stlkit.ParseLimits::default(), max_triangles: 0, }
  match @stlkit.parse_obj(text, limits~) {
    Err(message) =>
      assert_true(message.contains("resource_limit: max_triangles"))
    Ok(_) => fail("zero triangle budget must reject the face")
  }
}

///|
test "public scanner reports sticky limit error before finish" {
  let mesh = @stlkit.parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").unwrap()
  let data = @stlkit.write_stl_binary(mesh)
  let scanner = @stlkit.StlScanner::new(limits={
    ..@stlkit.ParseLimits::default(),
    max_triangles: 0,
  })
  scanner.feed(data[:84].to_owned())
  let error = scanner.error().unwrap()
  assert_true(error.contains("resource_limit: max_triangles"))
  scanner.feed(data[84:].to_owned())
  assert_eq(scanner.error(), Some(error))
  assert_true(scanner.finish() is Err(_))
}
