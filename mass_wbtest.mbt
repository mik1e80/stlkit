// 白盒测试：质量属性（重心、转动惯量）。
//
// 这块**必须拿有解析解的形状对**。体积算错顶多是数字不对，
// 转动惯量的公式里有一堆 1/10、1/20、平行轴定理的符号，
// 写错一个就全错，而且从结果上很难看出来「大概是错的」。
//
// 所以只测长方体——它的重心和转动惯量都有闭式解：
//
//     重心   = 几何中心
//     I_xx   = m(b² + c²) / 12
//     I_yy   = m(a² + c²) / 12
//     I_zz   = m(a² + b²) / 12
//
// 边长取成不一样的值（而不是立方体），这样三个轴能分开验证——
// 立方体三个轴相等，公式里 a/b/c 搞混了也看不出来。

///|
/// 按量级比较浮点数。
///
/// `close` 用的是绝对容差 1e-9，对单位立方体那种量级（数值 ~1）够用。
/// 但转动惯量动辄几十万，几次累加下来误差就有 1e-9 量级，绝对容差会误报。
/// 主惯量还要过一遍反三角函数，误差再大一点。
///
/// 判断实现对不对要看**相对**误差：这里观测到的是 3.6e-15 量级，
/// 容差给 1e-12 留了三个数量级的余量
fn close_rel(a : Double, b : Double) -> Bool {
  let scale = a.abs().max(b.abs())
  if scale == 0.0 {
    return true
  }
  (a - b).abs() / scale < 1.0e-12
}

///|
/// 造一个长方体 [0,a] × [0,b] × [0,c]。
///
/// 三角剖分和 unit_cube_triangles 完全一样，只是边长可调，
/// 保证绕向朝外（那么体积就是正的）
fn box_mesh(a : Double, b : Double, c : Double) -> Mesh {
  let v000 = Vec3::new(0.0, 0.0, 0.0)
  let v100 = Vec3::new(a, 0.0, 0.0)
  let v110 = Vec3::new(a, b, 0.0)
  let v010 = Vec3::new(0.0, b, 0.0)
  let v001 = Vec3::new(0.0, 0.0, c)
  let v101 = Vec3::new(a, 0.0, c)
  let v111 = Vec3::new(a, b, c)
  let v011 = Vec3::new(0.0, b, c)
  let triangles : Array[Triangle] = []
  for t in [
    (v000, v010, v110),
    (v000, v110, v100),
    (v001, v101, v111),
    (v001, v111, v011),
    (v000, v100, v101),
    (v000, v101, v001),
    (v010, v011, v111),
    (v010, v111, v110),
    (v000, v001, v011),
    (v000, v011, v010),
    (v100, v110, v111),
    (v100, v111, v101),
  ] {
    let (x, y, z) = t
    triangles.push(Triangle::from_vertices(x, y, z))
  }
  Mesh::new(triangles)
}

// ── 重心 ────────────────────────────────────────────────────────────────

///|
test "单位立方体的重心在正中间" {
  let mesh = box_mesh(1.0, 1.0, 1.0)
  let c = mesh.center_mass()
  assert_true(close(c.x, 0.5))
  assert_true(close(c.y, 0.5))
  assert_true(close(c.z, 0.5))
}

///|
test "长方体的重心在各边中点" {
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let c = mesh.center_mass()
  assert_true(close(c.x, 5.0))
  assert_true(close(c.y, 10.0))
  assert_true(close(c.z, 15.0))
}

///|
test "重心不在原点也能算对" {
  // 平移之后重心跟着走。这条顺便验证了「四面体分解用原点当顶点」
  // 这件事不影响结果——原点选在哪都该给出同一个物理答案
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let shifted : Array[Triangle] = []
  for t in mesh.triangles {
    shifted.push(Triangle::from_vertices(
      Vec3::new(t.a.x + 100.0, t.a.y - 50.0, t.a.z),
      Vec3::new(t.b.x + 100.0, t.b.y - 50.0, t.b.z),
      Vec3::new(t.c.x + 100.0, t.c.y - 50.0, t.c.z),
    ))
  }
  let c = Mesh::new(shifted).center_mass()
  assert_true(close(c.x, 105.0))
  assert_true(close(c.y, -40.0))
  assert_true(close(c.z, 15.0))
}

///|
test "空网格的重心是原点，不崩" {
  let c = Mesh::empty().center_mass()
  assert_true(close(c.x, 0.0))
  assert_true(close(c.y, 0.0))
  assert_true(close(c.z, 0.0))
}

// ── 转动惯量 ────────────────────────────────────────────────────────────

///|
test "单位立方体的转动惯量是 1/6" {
  // 边长 1、质量 1 的立方体，绕任意过重心的轴都是 m·a²/6 = 1/6
  let m = box_mesh(1.0, 1.0, 1.0).moment_inertia()
  let want = 1.0 / 6.0
  assert_true(close(m[0], want))
  assert_true(close(m[4], want))
  assert_true(close(m[8], want))
  // 立方体对称，非对角项应该是 0
  assert_true(close(m[1], 0.0))
  assert_true(close(m[2], 0.0))
  assert_true(close(m[5], 0.0))
}

///|
test "长方体的三个主惯量对得上公式" {
  // 这是最要紧的一条：三条边不一样长，三个轴的公式各不同，
  // 只要 a/b/c 用混了、或者系数写错了，立刻露馅
  let (a, b, c) = (10.0, 20.0, 30.0)
  let mesh = box_mesh(a, b, c)
  let mass = a * b * c
  let m = mesh.moment_inertia()
  assert_true(close(m[0], mass * (b * b + c * c) / 12.0)) // Ixx
  assert_true(close(m[4], mass * (a * a + c * c) / 12.0)) // Iyy
  assert_true(close(m[8], mass * (a * a + b * b) / 12.0)) // Izz
}

///|
test "转动惯量张量是对称的" {
  let m = box_mesh(10.0, 20.0, 30.0).moment_inertia()
  assert_true(close(m[1], m[3]))
  assert_true(close(m[2], m[6]))
  assert_true(close(m[5], m[7]))
}

///|
test "平行轴定理：转动惯量不随平移变，重心才变" {
  // 转动惯量是**关于重心**算的，所以整体平移不该改变它。
  // 这一条专门盯平行轴定理那一步——符号写反的话平移之后数字会飞掉
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let before = mesh.moment_inertia()
  let shifted : Array[Triangle] = []
  for t in mesh.triangles {
    shifted.push(Triangle::from_vertices(
      Vec3::new(t.a.x + 100.0, t.a.y - 50.0, t.a.z),
      Vec3::new(t.b.x + 100.0, t.b.y - 50.0, t.b.z),
      Vec3::new(t.c.x + 100.0, t.c.y - 50.0, t.c.z),
    ))
  }
  let after = Mesh::new(shifted).moment_inertia()
  for k = 0; k < 9; k = k + 1 {
    assert_true(close(before[k], after[k]))
  }
}

///|
test "朝向反了的模型给出同样的质量属性" {
  // 顶点顺序整体写反的模型，有符号体积是负的。物理量不该跟着变负——
  // 一个里外翻了的立方体，它的重心和转动惯量还是那套数
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let flipped : Array[Triangle] = []
  for t in mesh.triangles {
    // 交换后两个顶点，绕向就反了
    flipped.push(Triangle::from_vertices(t.a, t.c, t.b))
  }
  let flipped = Mesh::new(flipped)
  let c = flipped.center_mass()
  assert_true(close(c.x, 5.0))
  assert_true(close(c.y, 10.0))
  assert_true(close(c.z, 15.0))
  let before = mesh.moment_inertia()
  let after = flipped.moment_inertia()
  for k = 0; k < 9; k = k + 1 {
    assert_true(close(before[k], after[k]))
  }
}

// ── 主惯量 ──────────────────────────────────────────────────────────────

///|
test "主惯量就是三个特征值，按从大到小排" {
  // 长方体本来就摆正了，所以特征值就是对角项
  let (a, b, c) = (10.0, 20.0, 30.0)
  let mass = a * b * c
  let want_xx = mass * (b * b + c * c) / 12.0
  let want_yy = mass * (a * a + c * c) / 12.0
  let want_zz = mass * (a * a + b * b) / 12.0
  let p = box_mesh(a, b, c).principal_moments()
  // 10×20×30 算出来 Ixx=650000、Iyy=500000、Izz=250000
  assert_true(close(p[0], want_xx))
  assert_true(close(p[1], want_yy))
  assert_true(close(p[2], want_zz))
}

///|
test "立方体的三个主惯量相等" {
  // 各向同性：绕哪个轴都一样
  let p = box_mesh(2.0, 2.0, 2.0).principal_moments()
  assert_true(close(p[0], p[1]))
  assert_true(close(p[1], p[2]))
}

///|
test "主惯量对旋转过的长方体也对" {
  // 把长方体绕 z 轴转 30 度，特征值不该变（转动惯量是各向的标量和，
  // 特征值和坐标系无关）。这条能验出对角线化写没写对——
  // 只测摆正的形状的话，就算把非对角项全当 0 处理也能过
  let (a, b, c) = (10.0, 20.0, 30.0)
  let mass = a * b * c
  let ang = 3.141592653589793 / 6.0
  let ca = @math.cos(ang)
  let sa = @math.sin(ang)
  let mesh = box_mesh(a, b, c)
  let rotated : Array[Triangle] = []
  let rot = fn(v : Vec3) -> Vec3 {
    Vec3::new(v.x * ca - v.y * sa, v.x * sa + v.y * ca, v.z)
  }
  for t in mesh.triangles {
    rotated.push(Triangle::from_vertices(rot(t.a), rot(t.b), rot(t.c)))
  }
  let p = Mesh::new(rotated).principal_moments()
  let want_xx = mass * (b * b + c * c) / 12.0
  let want_yy = mass * (a * a + c * c) / 12.0
  let want_zz = mass * (a * a + b * b) / 12.0
  assert_true(close_rel(p[0], want_xx))
  assert_true(close_rel(p[1], want_yy))
  assert_true(close_rel(p[2], want_zz))
}

// ── 和别的部分接得上 ────────────────────────────────────────────────────

///|
test "质量属性在 3MF 解析出来的模型上也能用" {
  // box.3mf 是个 10×20×30 的长方体，和上面手算的那个一样
  let data = mf_bytes(cube_model_xml("millimeter", "<item objectid=\"1\"/>"))
  let cube = match parse_3mf(data) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  // 普通立方体：重心在 (0.5, 0.5, 0.5)
  let c = cube.center_mass()
  assert_true(close(c.x, 0.5))
  assert_true(close(c.y, 0.5))
  assert_true(close(c.z, 0.5))
}
