///|
test "合法OBJ制表符分隔应被识别" {
  let text = "v\t0\t0\t0\nv\t1\t0\t0\nv\t0\t1\t0\nf\t1\t2\t3\n"
  match parse_obj(text) {
    Ok(mesh) => assert_eq(mesh.triangle_count(), 1)
    Err(msg) => fail("OBJ tabs: " + msg)
  }
}

///|
test "凹多边形三角化应保持面积" {
  let text = "v 0 0 0\nv 2 0 0\nv 2 2 0\nv 1 0.5 0\nv 0 2 0\nf 1 2 3 4 5\n"
  let mesh = match parse_obj(text) {
    Ok(m) => m
    Err(msg) => fail(msg)
  }
  assert_true(close(mesh.surface_area(), 2.5))
}

///|
test "凹多边形反向输入保持面积和绕向" {
  let mesh = parse_or_fail(
    "v 0 0 0\nv 2 0 0\nv 2 2 0\nv 1 0.5 0\nv 0 2 0\nf 5 4 3 2 1 # comment\n",
  )
  assert_true(close(mesh.surface_area(), 2.5))
  for t in mesh.triangles {
    assert_true(t.computed_normal().z < 0.0)
  }
}

///|
test "YZ平面的凹多边形同样能切分" {
  let mesh = parse_or_fail(
    "v 7 0 0\nv 7 2 0\nv 7 2 2\nv 7 1 0.5\nv 7 0 2\nf 1 2 3 4 5\n",
  )
  assert_true(close(mesh.surface_area(), 2.5))
  for t in mesh.triangles {
    assert_true(t.computed_normal().x > 0.0)
  }
}

///|
test "PLY凹多边形与OBJ面积一致" {
  let text = "ply\nformat ascii 1.0\nelement vertex 5\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n2 0 0\n2 2 0\n1 0.5 0\n0 2 0\n5 0 1 2 3 4\n"
  let mesh = match parse_ply(@utf8.encode(text)) {
    Ok(m) => m
    Err(msg) => fail(msg)
  }
  assert_true(close(mesh.surface_area(), 2.5))
}

///|
test "自相交多边形明确报错" {
  match parse_obj("v 0 0 0\nv 1 1 0\nv 0 1 0\nv 1 0 0\nf 1 2 3 4\n") {
    Ok(_) => fail("不能将自相交面伪装成正常几何")
    Err(msg) => assert_true(msg.contains("第 5 行"))
  }
}

///|
test "非平面多边形明确报错" {
  match parse_obj("v 0 0 0\nv 1 0 0\nv 1 1 1\nv 0 1 0\nf 1 2 3 4\n") {
    Ok(_) => fail("不能猜非平面面片的三角化")
    Err(msg) => assert_true(msg.contains("不共面"))
  }
}
