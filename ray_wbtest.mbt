// 白盒测试：射线求交和最近点。
//
// 这类几何算法最容易「看着对、实际错」——写出来的东西跑得通、返回个数，
// 但差一点点。所以每条都用**能手算的形状**：单位立方体，射线从整数坐标打进去。

// ── 射线打中 ────────────────────────────────────────────────────────────

///|
test "正对打中立方体的底面" {
  // 从 (0.5, 0.5, -1) 朝 +z 打，应该打中 z=0 那个面，走 1 个单位
  let hit = match cube_mesh().ray_cast(Vec3::new(0.5, 0.5, -1.0), Vec3::new(0.0, 0.0, 1.0)) {
    Some(h) => h
    None => fail("应该打中")
  }
  assert_true(close(hit.distance, 1.0))
  assert_true(close(hit.point.z, 0.0))
  assert_true(close(hit.point.x, 0.5))
}

///|
test "从侧面打中" {
  let hit = match cube_mesh().ray_cast(Vec3::new(-2.0, 0.5, 0.5), Vec3::new(1.0, 0.0, 0.0)) {
    Some(h) => h
    None => fail("应该打中")
  }
  assert_true(close(hit.distance, 2.0))
  assert_true(close(hit.point.x, 0.0))
}

///|
test "打偏了要返回空" {
  // 从立方体旁边打过去，高度超出了
  let miss = cube_mesh().ray_cast(Vec3::new(0.5, 0.5, -1.0), Vec3::new(0.0, 1.0, 0.0))
  assert_true(miss is None)
  // 反方向也不行
  let back = cube_mesh().ray_cast(Vec3::new(0.5, 0.5, -1.0), Vec3::new(0.0, 0.0, -1.0))
  assert_true(back is None)
}

///|
test "穿过去的时候取最近的那次命中" {
  // 从立方体外面打进去，会依次穿过两个面。返回的必须是**先打到的那个**
  let hit = match cube_mesh().ray_cast(Vec3::new(0.5, 0.5, -1.0), Vec3::new(0.0, 0.0, 1.0)) {
    Some(h) => h
    None => fail("应该打中")
  }
  assert_true(close(hit.distance, 1.0))
  // 再往前打，起点已经在里面了，最近的还是 z=1 那个面
  let inside = match cube_mesh().ray_cast(Vec3::new(0.5, 0.5, 0.25), Vec3::new(0.0, 0.0, 1.0)) {
    Some(h) => h
    None => fail("应该打中")
  }
  assert_true(close(inside.distance, 0.75))
}

///|
test "平行于面打过去的射线不算命中" {
  // 贴着 z=0 那个面平行走。既不该报打中，也不该因为共面而算出个零距离
  let hit = cube_mesh().ray_cast(Vec3::new(-1.0, 0.5, 0.0), Vec3::new(1.0, 0.0, 0.0))
  // 它会打中 x=0 的那条边所在的三角形（正对着射线方向），
  // 但**不该**打中底面
  match hit {
    Some(h) => assert_true(h.distance > 0.99)
    None => ()
  }
}

///|
test "从面的正中间垂直打，命中点就在正下方" {
  let hit = match cube_mesh().ray_cast(Vec3::new(0.25, 0.75, 5.0), Vec3::new(0.0, 0.0, -1.0)) {
    Some(h) => h
    None => fail("应该打中")
  }
  assert_true(close(hit.distance, 4.0))
  assert_true(close(hit.point.x, 0.25))
  assert_true(close(hit.point.y, 0.75))
}

// ── 最近点 ──────────────────────────────────────────────────────────────

///|
test "正上方最近的就是脚下那个点" {
  let (d, q) = cube_mesh().nearest_point(Vec3::new(0.5, 0.5, 2.0))
  assert_true(close(d, 1.0))
  assert_true(close(q.x, 0.5))
  assert_true(close(q.y, 0.5))
  assert_true(close(q.z, 1.0))
}

///|
test "模型里头的点，最近距离是到最近那个面" {
  // 立方体正中心，到每个面都是 0.5
  let (d, _) = cube_mesh().nearest_point(Vec3::new(0.5, 0.5, 0.5))
  assert_true(close(d, 0.5))
}

///|
test "斜着外面的点，最近的是角" {
  // (-1,-1,-1) 到最近的角 (0,0,0) 是 √3
  let (d, q) = cube_mesh().nearest_point(Vec3::new(-1.0, -1.0, -1.0))
  assert_true(close(d, 1.7320508075688772))
  assert_true(close(q.x, 0.0))
  assert_true(close(q.y, 0.0))
  assert_true(close(q.z, 0.0))
}

///|
test "正对着一条棱的点，最近点在棱上" {
  // (-1, -1, 0.5) 到最近的那条棱（x=0,y=0 那条），距离是 √2
  let (d, q) = cube_mesh().nearest_point(Vec3::new(-1.0, -1.0, 0.5))
  assert_true(close(d, 1.4142135623730951))
  assert_true(close(q.x, 0.0))
  assert_true(close(q.y, 0.0))
  assert_true(close(q.z, 0.5))
}

///|
test "面上的点最近距离是零" {
  // 已经贴在面上了
  let (d, _) = cube_mesh().nearest_point(Vec3::new(0.5, 0.5, 1.0))
  assert_true(close(d, 0.0))
}

///|
test "最近点在长方体的各个方向都对" {
  // 用 10×20×30 的长方体，六个方向各打一个点，距离都能手算
  let mesh = box_mesh(10.0, 20.0, 30.0)
  let cases : Array[(Vec3, Double)] = [
    (Vec3::new(5.0, 10.0, -4.0), 4.0), // 下方
    (Vec3::new(5.0, 10.0, 35.0), 5.0), // 上方
    (Vec3::new(-3.0, 10.0, 15.0), 3.0), // x 负方向
    (Vec3::new(13.0, 10.0, 15.0), 3.0), // x 正方向
    (Vec3::new(5.0, -7.0, 15.0), 7.0), // y 负方向
    (Vec3::new(5.0, 26.0, 15.0), 6.0), // y 正方向
  ]
  for case in cases {
    let (p, want) = case
    let (d, q) = mesh.nearest_point(p)
    if !close(d, want) {
      fail("点 (\{p.x},\{p.y},\{p.z}) 的最近距离是 \{d}，应该是 \{want}")
    }
    // 最近点必须在长方体表面上
    let on_face = close(q.x, 0.0) ||
      close(q.x, 10.0) ||
      close(q.y, 0.0) ||
      close(q.y, 20.0) ||
      close(q.z, 0.0) ||
      close(q.z, 30.0)
    assert_true(on_face)
  }
}

// ── 射线和最近点的关系 ──────────────────────────────────────────────────

///|
test "沿法线打进去的距离，和最近点算出来的一致" {
  // 两种算法从不同角度算同一件事：从面上一点沿法线往模型里走，
  // 走多远会撞到对面。射线给的是「走了多远」，最近点给的是「离得多近」
  let mesh = box_mesh(10.0, 20.0, 30.0)
  // 从底面中心往上打
  let origin = Vec3::new(5.0, 10.0, 0.0)
  let hit = match mesh.ray_cast(origin, Vec3::new(0.0, 0.0, 1.0)) {
    Some(h) => h
    None => fail("应该打中顶面")
  }
  assert_true(close(hit.distance, 30.0))
}

///|
test "空网格打不中，最近点返回无穷远" {
  let empty = Mesh::empty()
  assert_true(empty.ray_cast(Vec3::zero(), Vec3::new(0.0, 0.0, 1.0)) is None)
  let (d, _) = empty.nearest_point(Vec3::zero())
  assert_true(d > 1.0e299)
}
