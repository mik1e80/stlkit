///|
test "质量属性保留合法立方体及解析值" {
  let mesh = cube_mesh()
  assert_true(check_printability(mesh, 0.0).mass_properties_available())
  let c = mesh.center_mass()
  assert_true((c.x - 0.5).abs() < 1.0e-9)
  assert_true((c.y - 0.5).abs() < 1.0e-9)
  assert_true((c.z - 0.5).abs() < 1.0e-9)
  for moment in mesh.principal_moments() {
    assert_true((moment - 1.0 / 6.0).abs() < 1.0e-9)
  }
}

///|
test "闭合且正体积的退化网格也必须暂停质量属性" {
  // 将一个底角移到三点共线的位置，顶点仍不同，边计数仍闭合。
  let transform = fn(p : Vec3) -> Vec3 {
    if p.x == 1.0 && p.y == 0.0 && p.z == 0.0 {
      Vec3::new(0.5, 0.5, 0.0)
    } else {
      p
    }
  }
  let mesh = Mesh::new(
    cube_mesh().triangles.map(t => {
      Triangle::from_vertices(transform(t.a), transform(t.b), transform(t.c))
    }),
  )
  let review = check_printability(mesh, 0.0)
  assert_true(review.validation.is_watertight())
  assert_eq(review.validation.degenerate_count, 1)
  assert_true(review.winding.consistent)
  assert_true(review.winding.orientation_reliable())
  assert_false(review.mass_properties_available())
}

///|
test "空网格开放绕向冲突和朝内模型不输出质量属性" {
  for
    mesh in [
      Mesh::empty(),
      cube_mesh_without(1),
      cube_inside_out(),
      mixed_orientation_parts(),
    ] {
    assert_false(check_printability(mesh, 0.0).mass_properties_available())
  }
  let triangles = cube_mesh().triangles.copy()
  triangles[0] = flip_winding(triangles[0])
  let review = check_printability(Mesh::new(triangles), 0.0)
  assert_true(review.validation.is_watertight())
  assert_false(review.winding.consistent)
  assert_false(review.mass_properties_available())
  let fixed = repair(Mesh::new(triangles), RepairOptions::default())
  assert_true(check_printability(fixed.mesh, 0.0).mass_properties_available())
}

///|
test "潜在重叠的正体积分量不能输出质量属性" {
  let triangles = cube_mesh().triangles.copy()
  let transform = fn(p : Vec3) -> Vec3 { Vec3::new(p.x + 0.5, p.y, p.z) }
  for t in cube_mesh().triangles {
    triangles.push(
      Triangle::from_vertices(transform(t.a), transform(t.b), transform(t.c)),
    )
  }
  let review = check_printability(Mesh::new(triangles), 0.0)
  assert_true(review.validation.is_watertight())
  assert_true(
    review.winding.components.all(c => c.orientation == PositiveVolume),
  )
  assert_false(review.mass_properties_available())
}

///|
test "薄壁或声明法线反向不单独阻断质量属性" {
  let thin = check_printability(box_mesh(1.0, 1.0, 0.1), 0.8)
  assert_true(thin.needs_review())
  assert_true(thin.mass_properties_available())
  let triangles = cube_mesh().triangles.map(t => {
    ..t,
    normal: t.computed_normal().scale(-1.0),
  })
  let review = check_printability(Mesh::new(triangles), 0.0)
  assert_eq(review.validation.wrong_normal_count, 12)
  assert_true(review.needs_review())
  assert_true(review.mass_properties_available())
}
