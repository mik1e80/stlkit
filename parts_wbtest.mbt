// 白盒测试：数零件（连通块）。
//
// 这块的核心难点是「什么算连在一起」。判据是**共用边**，不是共用顶点，
// 也不是几何上挨得近——所以下面的用例专门把几种「看着连着、实际是断的」
// 和「看着是两个、实际连着」的情况分开测。

///|
/// 把单位立方体平移到别处，用来拼多个零件的网格。
fn shifted_cube(
  dx : Double,
  dy : Double,
  dz : Double,
) -> Array[(Vec3, Vec3, Vec3)] {
  let out : Array[(Vec3, Vec3, Vec3)] = []
  for t in unit_cube_triangles() {
    let (a, b, c) = t
    out.push((
      Vec3::new(a.x + dx, a.y + dy, a.z + dz),
      Vec3::new(b.x + dx, b.y + dy, b.z + dz),
      Vec3::new(c.x + dx, c.y + dy, c.z + dz),
    ))
  }
  out
}

///|
/// 用一组三角形建网格。
fn mesh_of(triples : Array[(Vec3, Vec3, Vec3)]) -> Mesh {
  let triangles : Array[Triangle] = []
  for t in triples {
    let (a, b, c) = t
    triangles.push(Triangle::from_vertices(a, b, c))
  }
  Mesh::new(triangles)
}

///|
/// 把两批三角形接起来。
fn concat(
  first : Array[(Vec3, Vec3, Vec3)],
  second : Array[(Vec3, Vec3, Vec3)],
) -> Array[(Vec3, Vec3, Vec3)] {
  let out = first
  for t in second {
    out.push(t)
  }
  out
}

// ── 基本情形 ────────────────────────────────────────────────────────────

///|
test "单个立方体是一个零件" {
  assert_eq(count_parts_default(cube_mesh()), 1)
}

///|
test "空网格是零个零件" {
  assert_eq(count_parts_default(Mesh::empty()), 0)
}

///|
test "分开的两个立方体是两个零件" {
  let mesh = mesh_of(concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(5.0, 0.0, 0.0)))
  assert_eq(count_parts_default(mesh), 2)
  // 顺便确认它们各自都是水密的——分开并不等于坏
  let check = validate_default(mesh)
  assert_true(check.is_watertight())
}

///|
test "三个立方体就是三个零件" {
  let mesh = mesh_of(
    concat(
      concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(5.0, 0.0, 0.0)),
      shifted_cube(10.0, 0.0, 0.0),
    ),
  )
  assert_eq(count_parts_default(mesh), 3)
}

// ── 边界：什么算连在一起 ────────────────────────────────────────────────

///|
test "面对面贴住算一个零件（共用了边）" {
  // 平移正好 1.0，第二个立方体的左面和第一个的右面重合。
  // 那两个面是**共用边**的，所以拓扑上连成一体。
  //
  // 注意几何上它们也是水密的、能打印的——两个立方体拼成一个长方体，
  // 只是中间多了一层内壁。这里只关心连通性判得对不对
  let mesh = mesh_of(concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(1.0, 0.0, 0.0)))
  assert_eq(count_parts_default(mesh), 1)
}

///|
test "只碰到一个角不算连在一起" {
  // 平移 (1,1,1)：第二个立方体的一个角正好落在第一个的角上，
  // **共用了一个顶点，但没有共用任何一条边**。
  //
  // 切片时这种接触是断的——打印出来就是两个东西碰着，
  // 拿起来就分开了。所以必须报 2 而不是 1。
  //
  // 这条是「用共边而不是共顶点判断」的关键用例：
  // 判据要是写成「顶点相同就算连着」，这里就会错报成 1
  let mesh = mesh_of(concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(1.0, 1.0, 1.0)))
  assert_eq(count_parts_default(mesh), 2)
}

///|
test "挨得很近但没有共同顶点，是两个零件" {
  // 只差 0.001 毫米，肉眼和预览图上看都是贴着的，但拓扑上完全没关系。
  // 焊接容差是 1e-6，盖不住这 0.001 的缝，所以不该被焊到一起
  let mesh = mesh_of(
    concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(1.001, 0.0, 0.0)),
  )
  assert_eq(count_parts_default(mesh), 2)
}

// ── 和别的检查的关系 ────────────────────────────────────────────────────

///|
test "破洞不影响零件数" {
  // 拿掉一个面只是开了个洞，几何还连在一起
  assert_eq(count_parts_default(cube_mesh_without(1)), 1)
  assert_eq(count_parts_default(cube_mesh_without(6)), 1)
}

///|
test "退化面不会把零件数算错" {
  // 三个点重合的面，自己和自己不构成连接
  let text = "solid x\n  facet normal 0 0 1\n    outer loop\n" +
    "      vertex 0 0 0\n      vertex 0 0 0\n      vertex 0 0 0\n" +
    "    endloop\n  endfacet\nendsolid x\n"
  let degenerate = match parse_stl_ascii(text) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  assert_eq(count_parts_default(degenerate), 1)

  // 把它和一个正常的立方体放一起，应该是 2（那个退化面自己一块）
  let mesh = mesh_of(concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(5.0, 0.0, 0.0)))
  assert_eq(count_parts_default(concat_mesh(mesh, degenerate)), 3)
}

///|
/// 把两个网格的三角形接起来。
fn concat_mesh(a : Mesh, b : Mesh) -> Mesh {
  let triangles : Array[Triangle] = []
  for t in a.triangles {
    triangles.push(t)
  }
  for t in b.triangles {
    triangles.push(t)
  }
  Mesh::new(triangles)
}

// ── 和绕向检查用的是同一套连通性 ────────────────────────────────────────

///|
test "零件数和绕向检查的分块对得上" {
  // 绕向检查内部也是按连通块分别遍历的。两个零件分开测：
  // 每个都自洽，整体就不该报「绕向不一致」
  let mesh = mesh_of(concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(5.0, 0.0, 0.0)))
  assert_eq(count_parts_default(mesh), 2)
  let winding = check_winding_default(mesh)
  assert_eq(winding.flipped_faces, 0)
}

// ── 欧拉示性数 ──────────────────────────────────────────────────────────

///|
test "欧拉示性数：立方体是 2" {
  // V − E + F = 8 − 18 + 12 = 2，也就是球面拓扑
  let check = validate_default(cube_mesh())
  assert_eq(check.unique_vertex_count, 8)
  assert_eq(check.unique_edge_count, 18)
  assert_eq(check.triangle_count, 12)
  assert_eq(check.euler_number(), 2)
}

///|
test "欧拉示性数：两个分开的立方体是 4" {
  let mesh = mesh_of(concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(5.0, 0.0, 0.0)))
  let check = validate_default(mesh)
  // V = 16、E = 36、F = 24 → 16 − 36 + 24 = 4
  assert_eq(check.unique_vertex_count, 16)
  assert_eq(check.unique_edge_count, 36)
  assert_eq(check.euler_number(), 4)
  // 都是实心块没有洞时，χ 应该正好等于零件数 × 2。
  // 这个恒等式把两项独立的统计绑在一起：哪边算错了都会露馅
  assert_eq(check.euler_number(), count_parts_default(mesh) * 2)
}

///|
test "面对面贴住的两个立方体是非流形的（5 条边各被 4 个面共用）" {
  // 这条测试连我自己都猜错了两次：先猜「贴住就是连成一体、χ 回到 2」，
  // 实测不是；又猜「只有中间那条对角线是非流形边」，也不是。
  // 实测是**贴合面上 5 条边各被 4 个面共用**。
  //
  // 算法是这样的——贴合的那个正方形在 x=1 平面上，有 5 条边
  // （4 条边 + 1 条对角线），每条都被 4 个三角形用到：
  //
  //   4 条边上的边：在每个立方体里，它既是贴合面的边，**同时也是那个
  //                立方体的普通棱**（比如底面和右面共用的那条），
  //                所以每个立方体贡献 2 个三角形，合起来 4 个
  //   对角线：     两个立方体的贴合面各有 2 个三角形共用它，合起来 4 个
  //
  // 结论：**「把两个模型拼起来」不是把顶点对齐就完事**。中间那层
  // 必须真的处理掉（合并掉内部面），否则切片软件在这里判不出该往
  // 哪一侧填材料。模型看起来是完好的，导出来却是个坏网格
  let mesh = mesh_of(concat(shifted_cube(0.0, 0.0, 0.0), shifted_cube(1.0, 0.0, 0.0)))
  let check = validate_default(mesh)
  // 连是连着的：共用边了，所以算一个零件
  assert_eq(count_parts_default(mesh), 1)
  // 而欧拉数在这种网格上没有拓扑含义——它压根不是个曲面。
  // 8+8−4=12 个顶点、18+18−5=31 条边、24 个面，χ = 12−31+24 = 5
  assert_eq(check.unique_vertex_count, 12)
  assert_eq(check.unique_edge_count, 31)
  assert_eq(check.euler_number(), 5)
  // 拓扑是坏的
  assert_eq(check.non_manifold_edge_count, 5)
  assert_eq(check.boundary_edge_count, 0)
  assert_false(check.is_watertight())
}

///|
test "破洞的网格欧拉数会变，所以只在结论水密时才报" {
  // 拿掉一个面：V = 8、E = 18、F = 11 → 8 − 18 + 11 = 1。
  // 这个数不再是 2，但它没有拓扑含义（网格根本就没闭合），
  // 所以 CLI 里是「水密才显示欧拉数」
  let check = validate_default(cube_mesh_without(1))
  assert_false(check.is_watertight())
  assert_eq(check.euler_number(), 1)
}
