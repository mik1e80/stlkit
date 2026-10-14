///|
test "流式坐标低21位碰撞不应改变拓扑" {
  let mesh = Mesh::new([
    Triangle::from_vertices(Vec3::new(0.0, 0.0, 0.0), Vec3::new(0.25, 0.0, 0.0), Vec3::new(0.0, 0.25, 0.0)),
    Triangle::from_vertices(Vec3::new(2.097152, 0.0, 0.0), Vec3::new(2.347152, 0.0, 0.0), Vec3::new(2.097152, 0.25, 0.0)),
  ])
  let bytes = write_stl_binary(mesh)
  let parsed = match parse_stl_binary(bytes) { Ok(m) => m; Err(msg) => fail(msg) }
  let full = validate_default(parsed)
  let stream = match stream_stl_binary(bytes) { Ok(r) => r; Err(msg) => fail(msg) }
  assert_eq(stream.unique_vertex_count, full.unique_vertex_count)
}


///|
test "大坐标平移不应使立方体顶点合并" {
  let out : Array[Triangle] = []
  for t in cube_mesh().triangles {
    let shift = fn(v : Vec3) -> Vec3 { Vec3::new(v.x + 3000.0, v.y, v.z) }
    out.push(Triangle::from_vertices(shift(t.a), shift(t.b), shift(t.c)))
  }
  let report = validate_default(Mesh::new(out))
  assert_eq(report.unique_vertex_count, 8)
}


///|
test "PLY导出回读不应合并不同顶点" {
  let mesh = Mesh::new([
    Triangle::from_vertices(Vec3::new(0.0, 0.0, 0.0), Vec3::new(0.25, 0.0, 0.0), Vec3::new(0.0, 0.25, 0.0)),
    Triangle::from_vertices(Vec3::new(2.097152, 0.0, 0.0), Vec3::new(2.347152, 0.0, 0.0), Vec3::new(2.097152, 0.25, 0.0)),
  ])
  let restored = match parse_ply(write_ply_binary(mesh)) { Ok(m) => m; Err(msg) => fail(msg) }
  let full = validate_default(mesh)
  let after = validate_default(restored)
  assert_eq(after.unique_vertex_count, full.unique_vertex_count)
}
