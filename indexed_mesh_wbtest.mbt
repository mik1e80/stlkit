// SPDX-License-Identifier: Apache-2.0

///|
test "indexed cube preserves analytic geometry topology and declared normals" {
  let original = cube_mesh()
  let indexed = original.to_indexed().unwrap()
  assert_eq(indexed.vertex_count(), 8)
  assert_eq(indexed.triangle_count(), 12)
  assert_eq(indexed.unused_vertex_count(), 0)
  assert_true((indexed.surface_area() - 6.0).abs() < 1.0e-12)
  assert_true((indexed.volume() - 1.0).abs() < 1.0e-12)
  let report = indexed.validate()
  assert_eq(report.unique_vertex_count, 8)
  assert_eq(report.boundary_edge_count, 0)
  assert_eq(report.euler_number(), 2)
  let roundtrip = indexed.to_mesh()
  for i, triangle in roundtrip.triangles {
    for
      (actual, expected) in [
        (triangle.a, original.triangles[i].a),
        (triangle.b, original.triangles[i].b),
        (triangle.c, original.triangles[i].c),
        (triangle.normal, original.triangles[i].normal),
      ] {
      assert_eq(actual.x, expected.x)
      assert_eq(actual.y, expected.y)
      assert_eq(actual.z, expected.z)
    }
  }
  let left = indexed.bounding_box().unwrap()
  let right = original.bounding_box().unwrap()
  assert_eq(left.min.x, right.min.x)
  assert_eq(left.max.z, right.max.z)
}

///|
test "indexed constructor validates every index position and normal" {
  let vertices = [Vec3::zero(), Vec3::new(1, 0, 0), Vec3::new(0, 1, 0)]
  for
    face in [
      { a: -1, b: 1, c: 2, },
      { a: 0, b: 3, c: 2, },
      { a: 0, b: 1, c: 99, },
    ] {
    assert_true(IndexedMesh::new(vertices, [face]) is Err(_))
  }
  assert_true(IndexedMesh::new([], [{ a: 0, b: 0, c: 0, }]) is Err(_))
  let infinity = @string.parse_double("inf")
  assert_true(IndexedMesh::new([Vec3::new(infinity, 0, 0)], []) is Err(_))
  assert_true(IndexedMesh::new(vertices, [], normals=[Vec3::zero()]) is Err(_))
  assert_true(
    IndexedMesh::new(vertices, [{ a: 0, b: 1, c: 2, }], normals=[
      Vec3::new(0, infinity, 0),
    ])
    is Err(_),
  )
}

///|
test "indexed owns arrays and returns detached snapshots" {
  let vertices = [Vec3::zero(), Vec3::new(1, 0, 0), Vec3::new(0, 1, 0)]
  let faces : Array[Face3] = [{ a: 0, b: 1, c: 2, }]
  let normals = [Vec3::new(0, 0, 2)]
  let indexed = IndexedMesh::new(vertices, faces, normals~).unwrap()
  vertices[0] = Vec3::new(99, 99, 99)
  faces[0] = { a: 99, b: 99, c: 99, }
  normals[0] = Vec3::zero()
  let copied_vertices = indexed.vertices()
  copied_vertices[0] = Vec3::new(88, 0, 0)
  let copied_faces = indexed.faces()
  copied_faces[0] = { a: 77, b: 77, c: 77, }
  let copied_normals = indexed.declared_normals()
  copied_normals[0] = Vec3::zero()
  assert_eq(indexed.to_mesh().triangles[0].a.x, 0.0)
  assert_eq(indexed.to_mesh().triangles[0].normal.z, 2.0)
  assert_true((indexed.surface_area() - 0.5).abs() < 1.0e-12)
}

///|
test "indexed retains unused vertices without altering referenced bounds" {
  let indexed = IndexedMesh::new(
    [
      Vec3::zero(),
      Vec3::new(1, 0, 0),
      Vec3::new(0, 1, 0),
      Vec3::new(999, 999, 999),
    ],
    [{ a: 0, b: 1, c: 2, }],
  ).unwrap()
  assert_eq(indexed.vertex_count(), 4)
  assert_eq(indexed.unused_vertex_count(), 1)
  assert_eq(indexed.bounding_box().unwrap().max.x, 1.0)
  let no_faces = IndexedMesh::new([Vec3::new(999, 0, 0)], []).unwrap()
  assert_true(no_faces.bounding_box() is None)
  assert_eq(no_faces.unused_vertex_count(), 1)
  assert_true(no_faces.to_mesh().is_empty())
}

///|
test "indexed conversion uses exact coordinates and canonical signed zero" {
  let a = Vec3::zero()
  let b = Vec3::new(1, 0, 0)
  let c = Vec3::new(0, 1, 0)
  let mesh = Mesh::new([
    Triangle::from_vertices(a, b, c),
    Triangle::from_vertices(Vec3::new(-0.0, 0, 0), b, c),
    Triangle::from_vertices(Vec3::new(1.0e-9, 0, 0), b, c),
  ])
  let indexed = mesh.to_indexed().unwrap()
  assert_eq(indexed.vertex_count(), 4)
  assert_eq(indexed.triangle_count(), 3)
  assert_true((indexed.surface_area() - mesh.surface_area()).abs() < 1.0e-12)
}

///|
test "indexed preserves face orientation duplicates and degenerate evidence" {
  let mesh = Mesh::new([
    {
      normal: Vec3::new(0, 0, 2),
      a: Vec3::zero(),
      b: Vec3::new(1, 0, 0),
      c: Vec3::new(0, 1, 0),
    },
    Triangle::from_vertices(
      Vec3::zero(),
      Vec3::new(0, 1, 0),
      Vec3::new(1, 0, 0),
    ),
    Triangle::from_vertices(Vec3::zero(), Vec3::zero(), Vec3::zero()),
  ])
  let indexed = mesh.to_indexed().unwrap()
  assert_eq(indexed.to_mesh().triangles[0].normal.z, 2.0)
  assert_eq(indexed.triangle_count(), 3)
  assert_eq(indexed.validate().degenerate_count, 1)
  assert_true(indexed.to_mesh().triangles[1].computed_normal().z < 0.0)
  assert_eq(
    indexed.validate().boundary_edge_count,
    validate_default(mesh).boundary_edge_count,
  )
}
