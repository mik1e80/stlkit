///|
test "normal scope: perpendicular and nonunit declarations are not reverse normals" {
  let base = Triangle::from_vertices(
    Vec3::new(0.0, 0.0, 0.0),
    Vec3::new(1.0, 0.0, 0.0),
    Vec3::new(0.0, 1.0, 0.0),
  )
  let perpendicular = { ..base, normal: Vec3::new(1.0, 0.0, 0.0), }
  let nonunit = { ..base, normal: Vec3::new(0.0, 0.0, 2.0), }
  let report = validate_default(Mesh::new([perpendicular, nonunit]))
  assert_eq(report.wrong_normal_count, 0)
  assert_eq(report.degenerate_count, 0)
}

///|
test "normal scope: unequal OBJ vertex normals are discarded rather than validated" {
  let vertices = "v 0 0 0\nv 1 0 0\nv 0 1 0\n"
  let mixed = parse_obj(vertices + "vn 0 0 -1\nvn 0 0 -2\nf 1//1 2//1 3//2\n").unwrap()
  assert_true(mixed.triangles[0].normal.is_zero(0.0))
  assert_eq(validate_default(mixed).wrong_normal_count, 0)
  let shared = parse_obj(vertices + "vn 0 0 -1\nf 1//1 2//1 3//1\n").unwrap()
  assert_eq(validate_default(shared).wrong_normal_count, 1)
}
