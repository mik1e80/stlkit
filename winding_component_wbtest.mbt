///|
fn mixed_orientation_parts() -> Mesh {
  let triangles = box_mesh(2.0, 2.0, 2.0).triangles.copy()
  for t in cube_inside_out().triangles {
    let translate = fn(p : Vec3) -> Vec3 { Vec3::new(p.x + 5.0, p.y, p.z) }
    triangles.push(
      Triangle::from_vertices(translate(t.a), translate(t.b), translate(t.c)),
    )
  }
  Mesh::new(triangles)
}

///|
test "positive total volume cannot hide an inward disconnected part" {
  let mesh = mixed_orientation_parts()
  assert_true(check_winding_default(mesh).signed_volume > 0.0)
  let review = check_printability(mesh, 0.0)
  assert_true(review.inward())
  assert_true(review.needs_review())
  assert_true(review.thickness_unavailable())
}

///|
test "unify winding orients independent closed components separately" {
  let fixed = unify_winding(mixed_orientation_parts(), default_weld_tolerance())
  assert_true(
    (check_winding_default(fixed).signed_volume - 9.0).abs() < 1.0e-10,
  )
}

///|
test "component reports identify original faces and opposite signed volumes" {
  let report = check_winding_default(mixed_orientation_parts())
  assert_eq(report.components.length(), 2)
  assert_eq(report.components[0].index, 0)
  assert_eq(report.components[1].index, 1)
  assert_eq(report.components[0].faces.length(), 12)
  assert_eq(report.components[1].faces.length(), 12)
  assert_true(report.components[0].faces.all(i => i < 12))
  assert_true(report.components[1].faces.all(i => i >= 12))
  assert_true((report.components[0].signed_volume - 8.0).abs() < 1.0e-12)
  assert_true((report.components[1].signed_volume + 1.0).abs() < 1.0e-12)
  assert_true(report.components[0].orientation == PositiveVolume)
  assert_true(report.components[1].orientation == NegativeVolume)
  assert_eq(report.negative_components(), 1)
  assert_false(report.orientation_reliable())
}

///|
test "component sign survives input order large translation and scaling" {
  for scale in [0.001, 1.0, 1000.0] {
    let original = mixed_orientation_parts().triangles
    let triangles = []
    for i = original.length() - 1; i >= 0; i = i - 1 {
      let t = original[i]
      let transform = fn(p : Vec3) -> Vec3 {
        Vec3::new(p.x * scale + 1.0e6, p.y * scale - 2.0e6, p.z * scale + 3.0e6)
      }
      triangles.push(
        Triangle::from_vertices(transform(t.a), transform(t.b), transform(t.c)),
      )
    }
    let report = check_winding_default(Mesh::new(triangles))
    assert_eq(report.negative_components(), 1)
    assert_true(report.components[0].orientation == NegativeVolume)
    assert_true(report.components[1].orientation == PositiveVolume)
    assert_true(
      (report.components[0].signed_volume / (scale * scale * scale) + 1.0).abs() <
      1.0e-5,
    )
  }
}

///|
test "repair counts isolated component reversal without relying on normal updates" {
  let fixed = repair(mixed_orientation_parts(), {
    ..RepairOptions::default(),
    recompute_normals: false,
  })
  assert_eq(fixed.flipped_faces, 0)
  assert_eq(fixed.reoriented_components, 1)
  assert_true(fixed.changed())
  let report = check_winding_default(fixed.mesh)
  assert_eq(report.negative_components(), 0)
  assert_true(report.orientation_reliable())
}

///|
test "nested cavity sign is reported and not automatically inverted" {
  let mesh = hollow_box()
  let before = check_winding_default(mesh)
  assert_eq(before.components.length(), 2)
  assert_eq(before.negative_components(), 1)
  assert_true(before.components.all(c => c.potentially_nested))
  let fixed = unify_winding(mesh, default_weld_tolerance())
  let after = check_winding_default(fixed)
  assert_eq(after.negative_components(), 1)
  assert_true((after.signed_volume - 784.0).abs() < 1.0e-10)
  assert_true(check_printability(mesh, 0.0).needs_review())
}

///|
test "open zero volume and nonmanifold components have indeterminate orientation" {
  let t = Triangle::from_vertices(
    Vec3::new(0.0, 0.0, 0.0),
    Vec3::new(1.0, 0.0, 0.0),
    Vec3::new(0.0, 1.0, 0.0),
  )
  for triangles in [[t], [t, flip_winding(t)], [t, t, t]] {
    let report = check_winding_default(Mesh::new(triangles))
    assert_eq(report.components.length(), 1)
    assert_true(report.components[0].orientation == Indeterminate)
    assert_false(report.orientation_reliable())
  }
}
