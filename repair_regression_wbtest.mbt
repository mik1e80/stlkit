///|
test "共线但不重合的三点应报告退化面" {
  let tri = Triangle::from_vertices(Vec3::new(0.0, 0.0, 0.0), Vec3::new(1.0, 0.0, 0.0), Vec3::new(2.0, 0.0, 0.0))
  let mesh = Mesh::new([tri])
  let report = validate_default(mesh)
  assert_eq(report.degenerate_count, 1)
}


///|
test "修复两处独立破洞应报告2个洞" {
  let out = cube_mesh_without(1).triangles.copy()
  for t in cube_mesh_without(1).triangles {
    let shift = fn(v : Vec3) -> Vec3 { Vec3::new(v.x + 5.0, v.y, v.z) }
    out.push(Triangle::from_vertices(shift(t.a), shift(t.b), shift(t.c)))
  }
  let result = repair(Mesh::new(out), RepairOptions::default())
  assert_eq(result.filled_holes, 2)
}


///|
test "共线退化面应可删除" {
  let mesh = Mesh::new([Triangle::from_vertices(Vec3::new(0.0, 0.0, 0.0), Vec3::new(1.0, 0.0, 0.0), Vec3::new(2.0, 0.0, 0.0))])
  let result = repair(mesh, { ..RepairOptions::normals_only(), drop_degenerate: true, })
  assert_eq(result.removed_degenerate, 1)
}

