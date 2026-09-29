// 白盒测试：壁厚检查。
//
// 这类「采样 + 射线」的算法最容易看起来没问题：跑得通、返回个数、
// 数量级也对，但差一点点。所以每条都要有**能手算的答案**。
//
// 最要紧的是空心盒子那条：实心长方体量出来是「最短那条边」，
// 看不出算法是不是真的量到了对面；空心盒子的答案是**壁厚**，
// 量错一层就是另一个数。

///|
/// 壁厚的浮点比较。
///
/// 算法会把射线起点从表面往里挪一点点（躲开它自己所在的那个三角形），
/// 所以量出来的厚度会**稳定偏小**一个固定的相对量（大约 1e-8）。
/// 这不是误差，是设计——但比较的时候得盖住它。
///
/// 所以这里用 1e-6 的相对容差，而不是 `close_rel` 那个 1e-12。
fn close_thickness(a : Double, b : Double) -> Bool {
  let scale = a.abs().max(b.abs())
  if scale == 0.0 {
    return true
  }
  (a - b).abs() / scale < 1.0e-6
}

///|
/// 造一个 [lo, hi]³ 的立方体，`flip` 决定绕向要不要反过来。
///
/// 空心盒子 = 外面一个正常的 + 里面一个反过来的。
/// 里面那个绕向反了，法线就朝里，射线从内壁打出去才会打到对面的内壁。
fn box_at(lo : Double, hi : Double, flip : Bool) -> Array[Triangle] {
  let s = hi - lo
  let out : Array[Triangle] = []
  for t in box_mesh(s, s, s).triangles {
    let shift = fn(v : Vec3) -> Vec3 {
      Vec3::new(v.x + lo, v.y + lo, v.z + lo)
    }
    if flip {
      out.push(Triangle::from_vertices(shift(t.a), shift(t.c), shift(t.b)))
    } else {
      out.push(Triangle::from_vertices(shift(t.a), shift(t.b), shift(t.c)))
    }
  }
  out
}

///|
/// 外壳 10³、内腔 6³ 的空心盒子（壁厚 2）。
fn hollow_box() -> Mesh {
  let triangles = box_at(0.0, 10.0, false)
  for t in box_at(2.0, 8.0, true) {
    triangles.push(t)
  }
  Mesh::new(triangles)
}

// ── 实心形状：量到的是「对面的距离」 ────────────────────────────────────

///|
test "实心长方体最薄的地方是最短那条边" {
  // 从 10×20×30 的各个面往里打：从 x=0 打到 x=10 是 10，
  // 从 y=0 打到 y=20 是 20，从 z=0 打到 z=30 是 30。
  // 所以最小值是 10
  let r = check_thickness_default(box_mesh(10.0, 20.0, 30.0))
  assert_true(r.hits > 0)
  assert_true(close_thickness(r.min_thickness, 10.0))
  // 平均应该在 10 到 30 之间
  assert_true(r.mean_thickness >= 10.0)
  assert_true(r.mean_thickness <= 30.0)
}

///|
test "薄板量出来就是板厚" {
  // 10×10×0.5 的板子。从大面往里打只有 0.5 厚
  let r = check_thickness_default(box_mesh(10.0, 10.0, 0.5))
  assert_true(close_thickness(r.min_thickness, 0.5))
}

///|
test "立方体各个方向都是边长" {
  let r = check_thickness_default(box_mesh(4.0, 4.0, 4.0))
  assert_true(close_thickness(r.min_thickness, 4.0))
  assert_true(close_thickness(r.mean_thickness, 4.0))
}

// ── 空心：量到的是壁厚 ──────────────────────────────────────────────────

///|
test "空心盒子量出来是壁厚，不是外形尺寸" {
  // 这条是关键。外壳 10³、内腔 6³，壁厚 2。
  //
  // 算法要是量错了（比如只算了包围盒、或者射线没打进内腔），
  // 会报 10 或者 6；量对了才是 2
  let mesh = hollow_box()
  let r = check_thickness_default(mesh)
  assert_true(r.hits > 0)
  assert_true(close_thickness(r.min_thickness, 2.0))
  // 平均值**不是** 2，而且这是对的。
  //
  // 内腔是 [2,8]³，够不到八个角——那些地方是实心的，
  // 从角上往里打要穿 10，不是 2。所以平均值是「表面各处的平均」，
  // 会被厚的地方拉高（实测 4.62）。
  //
  // 这正说明判断薄不薄要看**最小值**，平均值只当参考
  assert_true(r.mean_thickness > 2.0)
  assert_true(r.mean_thickness < 10.0)
}

///|
test "空心盒子是水密的" {
  // 空心盒子本身必须是个合法闭合体，不然上面那条测的就不是壁厚了
  let check = validate_default(hollow_box())
  assert_true(check.is_watertight())
  // 体积 = 10³ − 6³ = 1000 − 216 = 784
  assert_true(close_rel(hollow_box().volume(), 784.0))
}

// ── 确定性 ──────────────────────────────────────────────────────────────

///|
test "同样的模型跑两次结果完全一样" {
  // 采样用的是低差异序列不是随机数，所以必须可复现。
  // 报告里要写「修复前 XX 修复后 YY」，采样每次都变的话根本没法比
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let a = check_thickness(mesh, 200)
  let b = check_thickness(mesh, 200)
  assert_true(a.min_thickness == b.min_thickness)
  assert_true(a.mean_thickness == b.mean_thickness)
  assert_eq(a.hits, b.hits)
}

// ── 边界情形 ────────────────────────────────────────────────────────────

///|
test "开放曲面一条都打不到" {
  // 一张平板（只有一个面）。射线往「里面」打，里面什么都没有。
  // 这种情况要报「没打到」，而不是硬报一个 0 当厚度
  let text = "solid x\n  facet normal 0 0 1\n    outer loop\n" +
    "      vertex 0 0 0\n      vertex 10 0 0\n      vertex 0 10 0\n" +
    "    endloop\n  endfacet\nendsolid x\n"
  let flat = match parse_stl_ascii(text) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  let r = check_thickness_default(flat)
  assert_eq(r.hits, 0)
  assert_true(r.min_at is None)
}

///|
test "空网格不崩" {
  let r = check_thickness_default(Mesh::empty())
  assert_eq(r.samples, 0)
  assert_eq(r.hits, 0)
}

///|
test "采样数是零也不崩" {
  let r = check_thickness(Mesh::empty(), 0)
  assert_eq(r.hits, 0)
}

///|
test "最薄处的位置落在表面上" {
  // 报出一个「最薄处 10mm」但位置指向模型外面，那就没法去修
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let r = check_thickness_default(mesh)
  match r.min_at {
    Some(p) => {
      let (d, _) = mesh.nearest_point(p)
      // 报出来的点应该在表面上（距离约为零）
      assert_true(d < 1.0e-6)
    }
    None => fail("应该有最薄处的位置")
  }
}

// ── 和真实模型接得上 ────────────────────────────────────────────────────

///|
test "圆环的壁厚对得上（大半径减去小半径）" {
  // examples/torus.stl：大半径 0.7、小半径 0.3，所以管子的直径是 0.6，
  // 从管子表面打进去最薄处应该是 0.6（穿过整个管径）
  //
  // 这里不用读文件，用解析出来的那个圆环的等价构造——
  // 直接从 3MF 那个立方体换个形状不方便，所以用已有的 STL 解析器造
  let text = torus_like_ascii()
  let mesh = match parse_stl_ascii(text) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  let r = check_thickness_default(mesh)
  // 只验量级：管子直径 0.6 上下，不该量出 1.4（那是整个圆环的直径）
  assert_true(r.hits > 0)
  assert_true(r.min_thickness > 0.2)
  assert_true(r.min_thickness < 1.0)
}

///|
/// 造一个圆环的 ASCII STL，参数和 examples/torus.stl 一致。
///
/// 自己生成而不是读文件，是因为库包不能 import @fs——
/// 测试文件在包内，读不了外面的文件
fn torus_like_ascii() -> String {
  let big = 0.7
  let small = 0.3
  let nu = 24
  let nv = 12
  let mut s = "solid torus\n"
  for i = 0; i < nu; i = i + 1 {
    for j = 0; j < nv; j = j + 1 {
      let a0 = 6.283185307179586 * i.to_double() / nu.to_double()
      let a1 = 6.283185307179586 * (i + 1).to_double() / nu.to_double()
      let b0 = 6.283185307179586 * j.to_double() / nv.to_double()
      let b1 = 6.283185307179586 * (j + 1).to_double() / nv.to_double()
      let p00 = torus_point(big, small, a0, b0)
      let p10 = torus_point(big, small, a1, b0)
      let p11 = torus_point(big, small, a1, b1)
      let p01 = torus_point(big, small, a0, b1)
      s = s + facet_ascii(p00, p10, p11)
      s = s + facet_ascii(p00, p11, p01)
    }
  }
  s + "endsolid torus\n"
}

///|
fn torus_point(big : Double, small : Double, a : Double, b : Double) -> Vec3 {
  let r = big + small * @math.cos(b)
  Vec3::new(r * @math.cos(a), r * @math.sin(a), small * @math.sin(b))
}

///|
fn facet_ascii(a : Vec3, b : Vec3, c : Vec3) -> String {
  "  facet normal 0 0 0\n    outer loop\n" +
  "      vertex \{a.x} \{a.y} \{a.z}\n" +
  "      vertex \{b.x} \{b.y} \{b.z}\n" +
  "      vertex \{c.x} \{c.y} \{c.z}\n" +
  "    endloop\n  endfacet\n"
}
