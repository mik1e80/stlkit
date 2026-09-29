// 白盒测试：有向包围盒。
//
// 最关键的一条是「**旋转过的长方体，OBB 不变**」。这正是 OBB 存在的理由：
// 轴对齐包围盒对斜着摆的模型会虚胖，OBB 贴着模型走。
// 只测摆正的形状的话，把 OBB 退化成 AABB 也能全过。

///|
/// 把网格整体旋转（绕 z 轴）。
fn rotate_z(mesh : Mesh, angle : Double) -> Mesh {
  let ca = @math.cos(angle)
  let sa = @math.sin(angle)
  let out : Array[Triangle] = []
  for t in mesh.triangles {
    let rot = fn(v : Vec3) -> Vec3 {
      Vec3::new(v.x * ca - v.y * sa, v.x * sa + v.y * ca, v.z)
    }
    out.push(Triangle::from_vertices(rot(t.a), rot(t.b), rot(t.c)))
  }
  Mesh::new(out)
}

///|
/// 点是不是在盒子里（留一点浮点余量）。
fn inside_obb(obb : Obb, v : Vec3) -> Bool {
  let d = v.sub(obb.center)
  for k = 0; k < 3; k = k + 1 {
    if d.dot(obb.axes[k]).abs() > obb.half[k] + 1.0e-9 {
      return false
    }
  }
  true
}

// ── 基本情形 ────────────────────────────────────────────────────────────

///|
test "轴对齐的长方体，OBB 和轴对齐包围盒一致" {
  let obb = match box_mesh(10.0, 20.0, 30.0).oriented_bounding_box() {
    Some(o) => o
    None => fail("不该是空的")
  }
  let size = obb.size()
  assert_true(close_rel(size.x, 30.0))
  assert_true(close_rel(size.y, 20.0))
  assert_true(close_rel(size.z, 10.0))
  assert_true(close_rel(obb.center.x, 5.0))
  assert_true(close_rel(obb.center.y, 10.0))
  assert_true(close_rel(obb.center.z, 15.0))
  assert_true(close_rel(obb.volume(), 6000.0))
}

///|
test "空网格没有包围盒" {
  assert_true(Mesh::empty().oriented_bounding_box() is None)
}

///|
test "立方体的三条边一样长" {
  let obb = match box_mesh(4.0, 4.0, 4.0).oriented_bounding_box() {
    Some(o) => o
    None => fail("不该是空的")
  }
  let size = obb.size()
  assert_true(close_rel(size.x, size.y))
  assert_true(close_rel(size.y, size.z))
  assert_true(close_rel(size.x, 4.0))
}

// ── OBB 的价值：旋转不变 ────────────────────────────────────────────────

///|
test "旋转过的长方体，OBB 的尺寸不变" {
  // 这条是 OBB 存在的全部理由。绕 z 轴转 30 度之后：
  //   轴对齐包围盒会虚胖成 10·cos30+20·sin30 之类的尺寸
  //   OBB 应该**一点都不变**，还是 10 / 20 / 30
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let obb = match rotate_z(mesh, 3.141592653589793 / 6.0).oriented_bounding_box() {
    Some(o) => o
    None => fail("不该是空的")
  }
  let size = obb.size()
  assert_true(close_rel(size.x, 30.0))
  assert_true(close_rel(size.y, 20.0))
  assert_true(close_rel(size.z, 10.0))
  assert_true(close_rel(obb.volume(), 6000.0))
}

///|
test "旋转之后 OBB 比轴对齐包围盒小" {
  // 同一个旋转过的模型，两种盒子摆一起比。斜着放的长方体，
  // 轴对齐的那个会明显虚胖——这正是加 OBB 的意义
  let mesh = rotate_z(box_mesh(10.0, 20.0, 30.0), 0.7)
  let obb = match mesh.oriented_bounding_box() {
    Some(o) => o
    None => fail("不该是空的")
  }
  let aabb = match mesh.bounding_box() {
    Some(b) => b
    None => fail("不该是空的")
  }
  let aabb_size = aabb.size()
  let aabb_volume = aabb_size.x * aabb_size.y * aabb_size.z
  assert_true(obb.volume() < aabb_volume)
  // 而且 OBB 的体积应该接近真实的长方体 6000，AABB 才明显更大
  assert_true(close_rel(obb.volume(), 6000.0))
  assert_true(aabb_volume > 7000.0)
}

// ── 性质：盒子必须真的包住 ──────────────────────────────────────────────

///|
test "所有顶点都在盒子里" {
  // 算出来的盒子要是漏了一个顶点，那它就不是包围盒了。
  // 这条用几个不同朝向的形状都验一遍
  for angle in [0.0, 0.3, 0.7, 1.2, 2.5] {
    let mesh = rotate_z(box_mesh(3.0, 7.0, 11.0), angle)
    let obb = match mesh.oriented_bounding_box() {
      Some(o) => o
      None => fail("不该是空的")
    }
    for t in mesh.triangles {
      for v in [t.a, t.b, t.c] {
        if !inside_obb(obb, v) {
          fail("角度 \{angle}：顶点 \{v.x}, \{v.y}, \{v.z} 跑到盒子外面了")
        }
      }
    }
  }
}

///|
test "三个轴互相垂直而且是单位长度" {
  // PCA 求出来的主轴应该是一组标准正交基。歪了的话「包围盒」就不是长方体了
  let obb = match rotate_z(box_mesh(3.0, 7.0, 11.0), 0.9).oriented_bounding_box() {
    Some(o) => o
    None => fail("不该是空的")
  }
  for i = 0; i < 3; i = i + 1 {
    assert_true(close_rel(obb.axes[i].length(), 1.0))
    for j = i + 1; j < 3; j = j + 1 {
      assert_true(close(obb.axes[i].dot(obb.axes[j]), 0.0))
    }
  }
}

// ── 和别的部分接得上 ────────────────────────────────────────────────────

///|
test "OBB 在 3MF 解析出来的模型上也能用" {
  let data = mf_bytes(cube_model_xml("millimeter", "<item objectid=\"1\"/>"))
  let cube = match parse_3mf(data) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  let obb = match cube.oriented_bounding_box() {
    Some(o) => o
    None => fail("不该是空的")
  }
  // 单位立方体
  let size = obb.size()
  assert_true(close_rel(size.x, 1.0))
  assert_true(close_rel(size.y, 1.0))
  assert_true(close_rel(size.z, 1.0))
  assert_true(close_rel(obb.volume(), 1.0))
}
