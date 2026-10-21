///|
test "ray direction: scaled axes return geometric distance and the nearest point" {
  let mesh = cube_mesh()
  for scale in [1.0e-300, 0.25, 1.0, 2.0, 1.0e300] {
    let origin = Vec3::new(0.25, 0.5, -1.0)
    let hit = mesh.ray_cast(origin, Vec3::new(0.0, 0.0, scale)).unwrap()
    assert_true(close(hit.distance, 1.0))
    assert_true(close(hit.point.x, 0.25))
    assert_true(close(hit.point.y, 0.5))
    assert_true(close(hit.point.z, 0.0))
    assert_true(close(hit.point.sub(origin).length(), hit.distance))
    let from_above = mesh
      .ray_cast(Vec3::new(0.25, 0.5, 5.0), Vec3::new(0.0, 0.0, -scale))
      .unwrap()
    assert_true(close(from_above.distance, 4.0))
    assert_true(close(from_above.point.z, 1.0))
  }
}

///|
test "ray direction: oblique positive rescaling preserves point and distance" {
  let mesh = cube_mesh()
  let origin = Vec3::new(0.25, 0.25, -1.0)
  let expected_distance = (1.0 + 0.25 * 0.25 + 0.125 * 0.125).sqrt()
  for scale in [1.0e-200, 0.5, 1.0, 7.0, 1.0e200] {
    let hit = mesh
      .ray_cast(origin, Vec3::new(0.5 * scale, 0.25 * scale, 2.0 * scale))
      .unwrap()
    assert_true(close(hit.distance, expected_distance))
    assert_true(close(hit.point.x, 0.5))
    assert_true(close(hit.point.y, 0.375))
    assert_true(close(hit.point.z, 0.0))
    assert_true(close(hit.distance, hit.point.sub(origin).length()))
  }
}

///|
test "ray direction: zero and nonfinite inputs do not produce hits" {
  let mesh = cube_mesh()
  let origin = Vec3::new(0.25, 0.5, -1.0)
  let nan = @string.parse_double("nan")
  let inf = @string.parse_double("inf")
  for
    dir in [
      Vec3::zero(),
      Vec3::new(-0.0, 0.0, 0.0),
      Vec3::new(nan, 0.0, 1.0),
      Vec3::new(0.0, inf, 1.0),
      Vec3::new(0.0, 0.0, -inf),
    ] {
    assert_true(mesh.ray_cast(origin, dir) is None)
  }
  assert_true(
    mesh.ray_cast(Vec3::new(nan, 0.0, 0.0), Vec3::new(0.0, 0.0, 1.0)) is None,
  )
}

///|
test "ray direction: ray_triangle keeps the low-level ray parameter contract" {
  let origin = Vec3::new(0.25, 0.25, -1.0)
  let a = Vec3::zero()
  let b = Vec3::new(1.0, 0.0, 0.0)
  let c = Vec3::new(0.0, 1.0, 0.0)
  let t = ray_triangle(origin, Vec3::new(0.0, 0.0, 2.0), a, b, c).unwrap()
  assert_true(close(t, 0.5))
  let hit = Mesh::new([Triangle::from_vertices(a, b, c)])
    .ray_cast(origin, Vec3::new(0.0, 0.0, 2.0))
    .unwrap()
  assert_true(close(hit.distance, 1.0))
}
