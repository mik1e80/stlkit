///|
test "streaming storage grows even when vertices are reused" {
  let triangles = cube_mesh().triangles.copy()
  let one = StlScanner::new()
  one.feed(write_stl_binary(Mesh::new(triangles)))
  one.finish().unwrap() |> ignore
  assert_eq(one.storage().unique_vertices, 8)
  assert_eq(one.storage().edge_records, 36)
  for t in cube_mesh().triangles {
    triangles.push(t)
  }
  let twice = StlScanner::new()
  twice.feed(write_stl_binary(Mesh::new(triangles)))
  twice.finish().unwrap() |> ignore
  assert_eq(twice.storage().unique_vertices, 8)
  assert_eq(twice.storage().edge_records, 72)
  assert_eq(twice.storage().pending_bytes, 0)
  assert_true(
    twice.storage().peak_buffered_bytes > one.storage().peak_buffered_bytes,
  )
}

///|
test "review is a mesh report with an explicit sampling budget" {
  let mesh = box_mesh(10.0, 10.0, 0.5)
  let review = check_printability(mesh, 0.8, samples=24)
  assert_eq(review.thickness.unwrap().samples, 24)
  assert_true(review.thin_wall())
  assert_true(review.verdict().contains("不构成可打印结论"))
  assert_true(review_scope().contains("工艺未评估"))
  let disabled = check_printability(mesh, 0.0, samples=0)
  assert_true(disabled.thickness_unavailable())
  assert_true(disabled.needs_review())
}
