// SPDX-License-Identifier: Apache-2.0

///|
fn r2_coordinates(point : Vec3) -> (Double, Double, Double) {
  (point.x, point.y, point.z)
}

///|
test "scaled triangle normals and representable areas" {
  for size in [1.0e-200, 1.0e-100, 1.0, 1.0e100, 1.0e200] {
    let triangle = Triangle::from_vertices(
      Vec3::zero(),
      Vec3::new(size, 0.0, 0.0),
      Vec3::new(0.0, size, 0.0),
    )
    assert_false(triangle_is_degenerate(triangle))
    assert_eq(r2_coordinates(triangle.computed_normal()), (0.0, 0.0, 1.0))
    if size == 1.0e-200 || size == 1.0e200 {
      assert_true(triangle.area_checked() is Err(_))
    } else {
      let expected = size * size / 2.0
      assert_true(
        (triangle.area_checked().unwrap() / expected - 1.0).abs() < 1.0e-14,
      )
    }
  }
  let anisotropic = Triangle::from_vertices(
    Vec3::zero(),
    Vec3::new(1.0e200, 0.0, 0.0),
    Vec3::new(0.0, 1.0e-200, 0.0),
  )
  assert_eq(r2_coordinates(anisotropic.computed_normal()), (0.0, 0.0, 1.0))
  assert_true((anisotropic.area_checked().unwrap() - 0.5).abs() < 1.0e-14)
  let span = Triangle::from_vertices(
    Vec3::new(-1.0e308, 0.0, 0.0),
    Vec3::new(1.0e308, 0.0, 0.0),
    Vec3::new(-1.0e308, 1.0e-308, 0.0),
  )
  assert_eq(r2_coordinates(span.computed_normal()), (0.0, 0.0, 1.0))
  assert_true((span.area_checked().unwrap() - 1.0).abs() < 1.0e-14)
  let unresolved = Triangle::from_vertices(
    Vec3::zero(),
    Vec3::new(1.0e308, 0.0, 0.0),
    Vec3::new(1.0e308, 1.0e-308, 0.0),
  )
  assert_true(unresolved.area_checked() is Err(_))
}

///|
test "checked nearest point has no fabricated empty or invalid hit" {
  assert_true(
    Mesh::empty().nearest_point_checked(Vec3::zero()).unwrap() is None,
  )
  assert_true(
    Mesh::empty().nearest_point_checked(Vec3::new(0.0 / 0.0, 0.0, 0.0))
    is Err(_),
  )
  let mesh = Mesh::new([
    Triangle::from_vertices(
      Vec3::zero(),
      Vec3::new(1.0, 0.0, 0.0),
      Vec3::new(0.0, 1.0, 0.0),
    ),
  ])
  let (distance, point) = mesh
    .nearest_point_checked(Vec3::new(0.25, 0.25, 2.0))
    .unwrap()
    .unwrap()
  assert_eq(distance, 2.0)
  assert_eq(r2_coordinates(point), (0.25, 0.25, 0.0))
  assert_true(
    mesh.nearest_point_checked(Vec3::new(1.0 / 0.0, 0.0, 0.0)) is Err(_),
  )
  assert_true(
    Mesh::new([
      Triangle::from_vertices(
        Vec3::new(0.0 / 0.0, 0.0, 0.0),
        Vec3::zero(),
        Vec3::zero(),
      ),
    ]).nearest_point_checked(Vec3::zero())
    is Err(_),
  )
  assert_true(Mesh::empty().nearest_point(Vec3::zero()).0.is_inf())
}

///|
test "nearest point scaling and degenerate segments" {
  for scale in [1.0e-200, 1.0e-100, 1.0e100, 1.0e200] {
    let mesh = Mesh::new([
      Triangle::from_vertices(
        Vec3::zero(),
        Vec3::new(scale, 0.0, 0.0),
        Vec3::new(0.0, scale, 0.0),
      ),
    ])
    let (distance, point) = mesh
      .nearest_point_checked(Vec3::new(scale / 4.0, scale / 4.0, scale))
      .unwrap()
      .unwrap()
    assert_true((distance / scale - 1.0).abs() < 1.0e-14)
    assert_true((point.x / scale - 0.25).abs() < 1.0e-14)
  }
  let line = Mesh::new([
    Triangle::from_vertices(
      Vec3::zero(),
      Vec3::new(2.0, 0.0, 0.0),
      Vec3::new(1.0, 0.0, 0.0),
    ),
  ])
  let (distance, point) = line
    .nearest_point_checked(Vec3::new(1.5, 1.0, 0.0))
    .unwrap()
    .unwrap()
  assert_eq(distance, 1.0)
  assert_eq(r2_coordinates(point), (1.5, 0.0, 0.0))
}

///|
test "polygon operation budgets refuse work explicitly" {
  let vertices = [
    Vec3::new(0.0, 0.0, 0.0),
    Vec3::new(2.0, 0.0, 0.0),
    Vec3::new(2.0, 2.0, 0.0),
    Vec3::new(1.0, 1.0, 0.0),
    Vec3::new(0.0, 2.0, 0.0),
  ]
  guard triangulate_polygon(vertices, max_work=0) is Err(message) else {
    fail("expected work budget error")
  }
  assert_true(message.has_prefix("resource_limit:"))
  assert_eq(triangulate_polygon(vertices).unwrap().length(), 3)
  let large : Array[Vec3] = []
  for i in 0..<2200 {
    let angle = i.to_double() * 6.283185307179586 / 2200.0
    let radius = if i % 2 == 0 { 1.0 } else { 0.7 }
    large.push(
      Vec3::new(radius * @math.cos(angle), radius * @math.sin(angle), 0.0),
    )
  }
  guard triangulate_polygon(large) is Err(message) else {
    fail("expected bounded large concave polygon")
  }
  assert_true(message.has_prefix("resource_limit:"))
}

///|
test "SVG checked paint never accepts external resources" {
  for
    stroke in [
      "url(https://example.com/paint.svg#x)", "url(#x)", "rgb(1,2,3);fill:url(x)",
      "\" onload=\"bad", "var(--paint)",
    ] {
    assert_true(
      render_svg_checked(cube_mesh(), { ..PreviewOptions::default(), stroke, })
      is Err(_),
    )
  }
  for stroke in ["#abc", "#abcd", "#a0B1c2", "#aabbccdd", "black", "none"] {
    assert_true(
      render_svg_checked(cube_mesh(), { ..PreviewOptions::default(), stroke, })
      is Ok(_),
    )
  }
}
