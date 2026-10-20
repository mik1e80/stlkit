///|
test "薄板触发参考壁厚提醒，阈值可调整" {
  let mesh = box_mesh(1.0, 1.0, 0.1)
  let report = check_printability(mesh, 0.8)
  assert_true(report.thin_wall())
  assert_true(report.needs_review())
  assert_false(check_printability(mesh, 0.05).thin_wall())
  assert_false(check_printability(mesh, 0.0).thin_wall())
}

///|
test "整体朝内模型不能给出通过结论" {
  let out : Array[Triangle] = []
  for t in cube_mesh().triangles {
    out.push(Triangle::from_vertices(t.a, t.c, t.b))
  }
  let mesh = Mesh::new(out)
  let report = check_printability(mesh, 0.8)
  assert_true(report.inward())
  assert_true(report.needs_review())
  assert_true(report.thickness_unavailable())
  let fixed = repair(mesh, RepairOptions::default())
  assert_false(check_printability(fixed.mesh, 0.8).inward())
}

///|
test "正确模型结论保留检查边界" {
  let report = check_printability(cube_mesh(), 0.8)
  assert_false(report.needs_review())
  assert_true(report.verdict().contains("仍需确认"))
  assert_false(report.verdict().contains("可以直接"))
}

///|
test "空网格和开放网格不能作为打印通过" {
  assert_true(check_printability(Mesh::empty(), 0.8).needs_review())
  assert_true(check_printability(cube_mesh_without(1), 0.8).needs_review())
}

///|
test "printability counts negative components despite a positive aggregate volume" {
  let triangles = mixed_orientation_parts().triangles.copy()
  for t in cube_inside_out().triangles {
    let translate = fn(p : Vec3) -> Vec3 { Vec3::new(p.x + 8.0, p.y, p.z) }
    triangles.push(
      Triangle::from_vertices(translate(t.a), translate(t.b), translate(t.c)),
    )
  }
  let mesh = Mesh::new(triangles)
  let review = check_printability(mesh, 0.0)
  assert_true((review.winding.signed_volume - 6.0).abs() < 1.0e-12)
  assert_eq(review.inward_component_count(), 2)
  assert_true(review.inward())
  assert_true(review.needs_review())
  let fixed = repair(mesh, RepairOptions::default())
  let after = check_printability(fixed.mesh, 0.0)
  assert_eq(after.inward_component_count(), 0)
  assert_false(after.inward())
  assert_false(after.needs_review())
}

///|
test "needs review checks inward components independently of thickness availability" {
  let healthy = check_printability(cube_mesh(), 0.0)
  assert_false(healthy.needs_review())
  let review = check_printability(mixed_orientation_parts(), 0.0)
  // 公开报告允许调用方替换字段；即使提供了有命中的厚度报告，也不能掩盖朝向问题。
  let with_thickness = { ..review, thickness: healthy.thickness, }
  assert_false(with_thickness.thickness_unavailable())
  assert_false(with_thickness.thin_wall())
  assert_eq(with_thickness.inward_component_count(), 1)
  assert_true(with_thickness.needs_review())
}

///|
test "needs review checks indeterminate orientation independently of thickness" {
  let t = Triangle::from_vertices(
    Vec3::new(0.0, 0.0, 0.0),
    Vec3::new(1.0, 0.0, 0.0),
    Vec3::new(0.0, 1.0, 0.0),
  )
  let review = check_printability(Mesh::new([t, flip_winding(t)]), 0.0)
  assert_true(review.validation.is_watertight())
  assert_eq(review.validation.degenerate_count, 0)
  assert_eq(review.validation.wrong_normal_count, 0)
  assert_eq(review.winding.flipped_faces, 0)
  assert_true(review.winding.components[0].orientation == Indeterminate)
  let with_thickness = {
    ..review,
    thickness: check_printability(cube_mesh(), 0.0).thickness,
  }
  assert_eq(with_thickness.inward_component_count(), 0)
  assert_false(with_thickness.thickness_unavailable())
  assert_true(with_thickness.needs_review())
}

///|
test "needs review checks potentially overlapping positive shells independently of thickness" {
  let triangles = cube_mesh().triangles.copy()
  for t in cube_mesh().triangles {
    let translate = fn(p : Vec3) -> Vec3 { Vec3::new(p.x + 0.5, p.y, p.z) }
    triangles.push(
      Triangle::from_vertices(translate(t.a), translate(t.b), translate(t.c)),
    )
  }
  let review = check_printability(Mesh::new(triangles), 0.0)
  assert_true(review.validation.is_watertight())
  assert_eq(review.validation.degenerate_count, 0)
  assert_eq(review.validation.wrong_normal_count, 0)
  assert_eq(review.winding.flipped_faces, 0)
  assert_eq(review.winding.components.length(), 2)
  assert_true(
    review.winding.components.all(c => c.orientation == PositiveVolume),
  )
  assert_true(review.winding.components.all(c => c.potentially_nested))
  let with_thickness = {
    ..review,
    thickness: check_printability(cube_mesh(), 0.0).thickness,
  }
  assert_eq(with_thickness.inward_component_count(), 0)
  assert_false(with_thickness.thickness_unavailable())
  assert_true(with_thickness.needs_review())
}
