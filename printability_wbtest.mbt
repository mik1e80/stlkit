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
  for t in cube_mesh().triangles { out.push(Triangle::from_vertices(t.a, t.c, t.b)) }
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
